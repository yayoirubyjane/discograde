#!/usr/bin/env python3
"""Search MusicBrainz and import one album into Discograde's Firestore."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud.firestore_v1 import FieldFilter


PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "discograde0901")
USER_AGENT_CONTACT = os.environ.get("MUSICBRAINZ_CONTACT", "").strip()
USER_AGENT_NAME = "DiscogradeAlbumImporter/1.0"
METADATA_DETAILS_VERSION = 3
USER_AGENT = (
    f"{USER_AGENT_NAME} ({USER_AGENT_CONTACT})"
    if USER_AGENT_CONTACT
    else USER_AGENT_NAME
)


def get_json(url: str) -> dict:
    request = Request(
        url,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
    )
    with urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def artist_name(credits: list) -> str:
    parts = []
    for credit in credits:
        if isinstance(credit, str):
            parts.append(credit)
        elif isinstance(credit, dict):
            artist = credit.get("artist") or {}
            parts.append(credit.get("name") or artist.get("name") or "")
            parts.append(credit.get("joinphrase") or "")
    return "".join(parts).strip()


def escape_lucene_phrase(value: str) -> str:
    return re.sub(r'(["\\])', r"\\\1", value)


def respect_musicbrainz_rate_limit() -> None:
    state_file = Path.home() / ".discograde" / "musicbrainz-last-request"
    state_file.parent.mkdir(parents=True, exist_ok=True)
    try:
        previous_request = float(state_file.read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        previous_request = 0.0
    wait_seconds = 1.1 - (time.time() - previous_request)
    if wait_seconds > 0:
        time.sleep(wait_seconds)
    state_file.write_text(str(time.time()), encoding="utf-8")


def search_albums(title: str, artist: str) -> list[dict]:
    respect_musicbrainz_rate_limit()
    query = (
        f'release:"{escape_lucene_phrase(title)}" '
        f'AND artistname:"{escape_lucene_phrase(artist)}"'
    )
    url = "https://musicbrainz.org/ws/2/release-group/?" + urlencode(
        {"query": query, "fmt": "json", "limit": "10"}
    )
    data = get_json(url)
    results = []
    for item in data.get("release-groups", []):
        results.append(
            {
                "id": item.get("id", ""),
                "title": item.get("title", "Unknown album"),
                "artist": artist_name(item.get("artist-credit", [])),
                "release_date": item.get("first-release-date", ""),
                "type": item.get("primary-type", ""),
            }
        )
    return results


def search_artist(artist_entry: str) -> dict | None:
    artist_name_query, separator, artist_id = artist_entry.partition("|")
    artist_name_query = artist_name_query.strip()
    artist_id = artist_id.strip()
    if separator:
        if not re.fullmatch(
            r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
            r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
            artist_id,
        ):
            print(f"Skipped '{artist_entry}': the artist ID is not a valid MBID.")
            return None
        return {"id": artist_id.lower(), "name": artist_name_query}

    respect_musicbrainz_rate_limit()
    query = f'artist:"{escape_lucene_phrase(artist_name_query)}"'
    url = "https://musicbrainz.org/ws/2/artist/?" + urlencode(
        {"query": query, "fmt": "json", "limit": "10"}
    )
    artists = get_json(url).get("artists", [])
    exact_matches = [
        artist
        for artist in artists
        if artist.get("name", "").strip().casefold()
        == artist_name_query.strip().casefold()
    ]
    if len(exact_matches) == 1:
        return exact_matches[0]
    if len(exact_matches) > 1:
        print(
            f"Skipped artist '{artist_name_query}': multiple exact MusicBrainz "
            "matches. Add its MusicBrainz artist ID to tools/artists.txt."
        )
        return None
    print(
        f"Skipped artist '{artist_name_query}': no exact MusicBrainz match. "
        "Check the spelling or add its MusicBrainz artist ID to tools/artists.txt."
    )
    return None


def browse_artist_albums(artist_id: str, fallback_artist_name: str) -> list[dict]:
    results = []
    offset = 0
    page_size = 100
    while True:
        respect_musicbrainz_rate_limit()
        url = "https://musicbrainz.org/ws/2/release-group/?" + urlencode(
            {
                "artist": artist_id,
                "fmt": "json",
                "limit": str(page_size),
                "offset": str(offset),
                "release-group-status": "website-default",
                "inc": "artist-credits+genres",
            }
        )
        data = get_json(url)
        page = data.get("release-groups", [])
        results.extend(
            {
                "id": item.get("id", ""),
                "title": item.get("title", "Unknown album"),
                "artist": artist_name(item.get("artist-credit", []))
                or fallback_artist_name,
                "release_date": item.get("first-release-date", ""),
                "type": item.get("primary-type", ""),
                "genres": [
                    genre["name"]
                    for genre in item.get("genres", [])
                    if genre.get("name")
                ],
            }
            for item in page
            if item.get("primary-type") in {"Album", "EP"}
        )
        offset += len(page)
        if not page or offset >= data.get("release-group-count", 0):
            break
    return results


def get_album_details(release_group_id: str) -> dict:
    respect_musicbrainz_rate_limit()
    group_url = (
        f"https://musicbrainz.org/ws/2/release-group/{release_group_id}?"
        + urlencode(
            {
                "fmt": "json",
                "inc": "genres+tags+releases",
            }
        )
    )
    group = get_json(group_url)
    genres = sorted(
        {
            item["name"]
            for item in group.get("genres", [])
            if item.get("name")
        }
    )

    releases = group.get("releases", [])
    official_releases = [
        release for release in releases
        if str(release.get("status", "")).casefold() == "official"
    ]
    candidates = official_releases or releases
    if not candidates:
        return {"genres": genres}

    selected_release = min(
        candidates,
        key=lambda release: (
            not bool(release.get("date")),
            release.get("date") or "9999",
            release.get("id", ""),
        ),
    )
    release_id = selected_release.get("id")
    if not release_id:
        return {"genres": genres}

    respect_musicbrainz_rate_limit()
    includes = (
        "artist-credits+labels+recordings+media+artist-rels+"
        "recording-level-rels+work-rels+work-level-rels"
    )
    release_url = (
        f"https://musicbrainz.org/ws/2/release/{release_id}?"
        + urlencode({"fmt": "json", "inc": includes})
    )
    # A MusicBrainz release lookup returns the release object at the top level.
    # It is not wrapped in a "release" property.
    release = get_json(release_url)

    track_list = []
    formats = set()
    for medium in sorted(
        release.get("media", []), key=lambda item: item.get("position", 0)
    ):
        medium_format = medium.get("format")
        if medium_format:
            formats.add(medium_format)
        for track in medium.get("tracks", []):
            recording = track.get("recording") or {}
            duration_ms = track.get("length") or recording.get("length")
            duration = None
            if isinstance(duration_ms, (int, float)) and duration_ms >= 0:
                total_seconds = round(duration_ms / 1000)
                duration = f"{total_seconds // 60}:{total_seconds % 60:02d}"
            track_data = {
                "number": len(track_list) + 1,
                "title": track.get("title") or recording.get("title") or "Untitled",
                "score": 0,
            }
            if duration is not None:
                track_data["duration"] = duration
            track_list.append(track_data)

    labels = sorted(
        {
            item.get("label", {}).get("name", "")
            for item in release.get("label-info", [])
            if item.get("label", {}).get("name")
        }
    )
    producers = set()
    writers = set()
    _collect_credits(release, producers, writers)

    details = {"genres": genres, "trackList": track_list}
    if labels:
        details["label"] = ", ".join(labels)
    if formats:
        details["format"] = ", ".join(sorted(formats))
    if producers:
        details["producers"] = sorted(producers, key=str.casefold)
    if writers:
        details["writers"] = sorted(writers, key=str.casefold)
    return details


def _collect_credits(value, producers: set[str], writers: set[str]) -> None:
    if isinstance(value, dict):
        for relation in value.get("relations", []):
            role = str(relation.get("type", "")).casefold()
            artist = relation.get("artist") or {}
            name = str(artist.get("name", "")).strip()
            if name and "producer" in role:
                producers.add(name)
            if name and any(
                credit_type in role
                for credit_type in ("writer", "composer", "lyricist", "songwriter")
            ):
                writers.add(name)
        for child in value.values():
            _collect_credits(child, producers, writers)
    elif isinstance(value, list):
        for child in value:
            _collect_credits(child, producers, writers)


def is_recent_or_upcoming(release_date: str, days: int = 30) -> bool:
    if not release_date:
        return False
    cutoff = datetime.now(timezone.utc).date().toordinal() - days
    cutoff_date = datetime.fromordinal(cutoff).strftime("%Y-%m-%d")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", release_date):
        return release_date >= cutoff_date
    if re.fullmatch(r"\d{4}-\d{2}", release_date):
        return release_date >= cutoff_date[:7]
    if re.fullmatch(r"\d{4}", release_date):
        return release_date >= cutoff_date[:4]
    return False


def sync_artists(
    database,
    artist_file: Path,
    *,
    all_releases: bool = False,
    artist_entries: list[str] | None = None,
) -> int:
    if artist_entries is None:
        if not artist_file.is_file():
            raise RuntimeError(f"Artist list not found: {artist_file}")
        artists = [
            line.strip()
            for line in artist_file.read_text(encoding="utf-8-sig").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
    else:
        artists = [entry.strip() for entry in artist_entries if entry.strip()]
    if not artists:
        print(f"Add artist names to {artist_file} first.")
        return 0

    imported_count = 0
    repaired_count = 0
    errors = 0
    for artist_query in artists:
        try:
            print(f"Checking {artist_query}...")
            artist = search_artist(artist_query)
            if artist is None:
                continue
            albums = browse_artist_albums(artist["id"], artist["name"])
            selected_albums = albums if all_releases else [
                album for album in albums
                if is_recent_or_upcoming(album["release_date"])
            ]
            selected_albums.sort(key=lambda album: album["release_date"])
            scope = "catalog" if all_releases else "recent/upcoming"
            print(f"  Found {len(albums)} album/EP entries; checking {scope}.")
            if not selected_albums:
                print("  No albums match this sync.")
            for album in selected_albums:
                result = import_album(database, album)
                print(f"  {result}")
                if result.startswith("Imported "):
                    imported_count += 1
                elif result.startswith("Updated missing details "):
                    repaired_count += 1
        except Exception as error:
            errors += 1
            print(f"Could not sync {artist_query}: {error}", file=sys.stderr)

    print(
        f"Sync complete. Imported {imported_count} new album(s); "
        f"filled details on {repaired_count} existing album(s)."
    )
    return 1 if errors else 0


def get_cover_url(release_group_id: str) -> str:
    url = f"https://coverartarchive.org/release-group/{release_group_id}"
    try:
        data = get_json(url)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError):
        return ""
    images = data.get("images", [])
    front = next((image for image in images if image.get("front")), None)
    if front is None and images:
        front = images[0]
    if not front:
        return ""
    thumbnails = front.get("thumbnails", {})
    return thumbnails.get("500") or front.get("image", "")


def release_timestamp(value: str) -> datetime | None:
    # Only save a timestamp when the catalog provides an exact day; don't turn
    # a year or month into an invented date that could misfile a new release.
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value or ""):
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def get_firestore_client():
    credential_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if not credential_path:
        raise RuntimeError(
            "Set GOOGLE_APPLICATION_CREDENTIALS to the path of your Firebase "
            "service-account JSON file. Keep that file outside the project."
        )
    if not Path(credential_path).is_file():
        raise RuntimeError(f"Credential file not found: {credential_path}")
    try:
        firebase_admin.get_app()
    except ValueError:
        certificate = credentials.Certificate(credential_path)
        firebase_admin.initialize_app(certificate, {"projectId": PROJECT_ID})
    return firestore.client()


def choose_result(results: list[dict]) -> dict | None:
    if not results:
        print("No matching albums found.")
        return None

    print("\nMatches:")
    for index, album in enumerate(results, start=1):
        details = [album["artist"], album["release_date"], album["type"]]
        suffix = " | ".join(value for value in details if value)
        print(f"  {index}. {album['title']} - {suffix}")

    while True:
        choice = input("Choose a match number (or press Enter to cancel): ").strip()
        if not choice:
            return None
        if choice.isdigit() and 1 <= int(choice) <= len(results):
            return results[int(choice) - 1]
        print(f"Enter a number from 1 to {len(results)}.")


def import_album(database, album: dict) -> str:
    release_group_id = album["id"].lower()
    album_ref = database.collection("albums").document(release_group_id)
    existing_snapshot = album_ref.get()
    if existing_snapshot.exists:
        existing_data = existing_snapshot.to_dict() or {}
        updates = {}
        existing_artist = str(existing_data.get("artist", "")).strip()
        if not existing_artist and album["artist"].strip():
            updates["artist"] = album["artist"]

        if existing_data.get("metadataDetailsVersion") != METADATA_DETAILS_VERSION:
            try:
                details = get_album_details(release_group_id)
                if not details.get("genres") and album.get("genres"):
                    details["genres"] = album["genres"]
                for field, value in details.items():
                    current_value = existing_data.get(field)
                    if value and not current_value:
                        updates[field] = value
                updates["metadataDetailsFetchedAt"] = firestore.SERVER_TIMESTAMP
                updates["metadataDetailsVersion"] = METADATA_DETAILS_VERSION
            except Exception as error:
                print(
                    f"Could not fetch extra details for {album['title']}: {error}",
                    file=sys.stderr,
                )

        if updates:
            album_ref.update(updates)
            return f"Updated missing details on document {release_group_id}."
        return f"Already imported as document {release_group_id}."

    same_title = database.collection("albums").where(
        filter=FieldFilter("title", "==", album["title"])
    ).limit(50).stream()
    for existing in same_title:
        data = existing.to_dict() or {}
        if str(data.get("artist", "")).strip().casefold() == album["artist"].casefold():
            return f"Already in Firestore as document {existing.id}."

    document = {
        "title": album["title"],
        "artist": album["artist"],
        "coverUrl": get_cover_url(release_group_id),
        "communityScore": 0,
        "ratingCount": 0,
        "musicBrainzId": release_group_id,
        "metadataSource": "MusicBrainz",
        "importedAt": firestore.SERVER_TIMESTAMP,
    }
    try:
        details = get_album_details(release_group_id)
        if not details.get("genres") and album.get("genres"):
            details["genres"] = album["genres"]
        document.update(details)
        document["metadataDetailsFetchedAt"] = firestore.SERVER_TIMESTAMP
        document["metadataDetailsVersion"] = METADATA_DETAILS_VERSION
    except Exception as error:
        if album.get("genres"):
            document["genres"] = album["genres"]
        print(
            f"Could not fetch extra details for {album['title']}: {error}",
            file=sys.stderr,
        )
    release_date = release_timestamp(album["release_date"])
    if release_date:
        document["releaseDate"] = release_date
    if album["type"]:
        document["type"] = album["type"]

    album_ref.create(document)
    cover_status = "cover art found" if document["coverUrl"] else "no cover art in archive"
    date_status = "exact release date saved" if release_date else "exact release date unavailable"
    return f"Imported {album['title']} by {album['artist']} ({cover_status}; {date_status})."


def main() -> int:
    if not USER_AGENT_CONTACT:
        print("Set MUSICBRAINZ_CONTACT to an email address for the API User-Agent.")
        return 2

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sync-artists",
        action="store_true",
        help="automatically import recent and upcoming albums from tools/artists.txt",
    )
    parser.add_argument(
        "--all-releases",
        action="store_true",
        help="import every album and EP for listed artists (use for a one-time backfill)",
    )
    parser.add_argument(
        "--artist",
        help="sync only this artist; accepts a name or 'Artist Name | MUSICBRAINZ_ARTIST_ID'",
    )
    arguments = parser.parse_args()

    try:
        database = get_firestore_client()
    except Exception as error:
        print(f"Could not connect to Firestore: {error}", file=sys.stderr)
        return 1

    if arguments.sync_artists or arguments.all_releases or arguments.artist:
        return sync_artists(
            database,
            Path(__file__).with_name("artists.txt"),
            all_releases=arguments.all_releases,
            artist_entries=[arguments.artist] if arguments.artist else None,
        )

    title = input("Album title: ").strip()
    artist = input("Artist: ").strip()
    if not title or not artist:
        print("Both album title and artist are required.")
        return 2

    try:
        print("Searching MusicBrainz...")
        results = search_albums(title, artist)
        selected = choose_result(results)
        if selected is None:
            return 0
        print(import_album(database, selected))
        return 0
    except (HTTPError, URLError, TimeoutError) as error:
        print(f"Catalog request failed: {error}", file=sys.stderr)
        return 1
    except Exception as error:  # Includes Firebase credential and Firestore errors.
        print(f"Import failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
