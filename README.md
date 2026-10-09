# Discograde

Flutter starter for a community powered album rating app. It uses Material 3,
Inter typography, Firebase, and a persistent four tab navigation shell.

## Firebase setup

The app calls `Firebase.initializeApp()` at startup. Add the platform Firebase
configuration for each target before running the app (for example, configure
Android and iOS with the FlutterFire CLI).

## AI album discovery

The Home screen includes an album discovery chat powered by Cloudflare Workers
AI (Meta Llama) while Firebase continues to provide authentication and the
Firestore catalog. The Flutter client sends the listener's prompt, a compact
catalog, favorite genres, and recent review scores to a Cloudflare Worker. The
Worker verifies Firebase Auth and App Check tokens before running inference.
It filters model recommendations to album IDs in the supplied catalog, and the
app opens recommendations in the existing album detail screen. Review text is
not sent to the model.

### Deploy the Cloudflare Worker

1. Create a Cloudflare account and make sure Workers AI is enabled. Workers AI
   currently includes a limited daily no-cost allocation; requests made while
   developing also use the account's model allocation. Check Cloudflare's
   current [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/).
2. Install Node.js, then open PowerShell in the `cloudflare` folder:

   ```powershell
   cd "C:\path\to\discograde\cloudflare"
   npx wrangler login
   npx wrangler deploy
   ```

3. Wrangler prints the deployed URL, for example
   `https://discograde-ai.<your-subdomain>.workers.dev`.
4. If you run Flutter Web, edit `ALLOWED_ORIGINS` in `wrangler.jsonc` to include
   the exact origin where the web app is hosted. The default allows local web
   development on port 5000. Android requests do not use browser CORS.
5. From the project root, run Flutter with the Worker URL:

   ```powershell
   flutter run --dart-define=CLOUDFLARE_WORKER_URL=https://discograde-ai.<your-subdomain>.workers.dev
   ```

The Worker uses the Workers AI binding, so no Cloudflare API token is embedded
in Flutter. It accepts requests only when Firebase Auth and App Check tokens
belong to the configured Firebase project and registered Android/Web app IDs.
Keep the Worker URL when building the app, and update the allowed web origin
before hosting a web build.

App Check initializes immediately after Firebase. Debug builds use debug
providers; register the token printed on the first run in Firebase Console at
**App Check > Apps > Manage debug tokens**. Release Android and Apple builds use
Play Integrity and App Attest with Device Check fallback. For a release web
build, provide your Firebase App Check reCAPTCHA v3 site key with
`--dart-define=RECAPTCHA_V3_SITE_KEY=your-site-key`.

## Import albums without Cloud Functions

The local importer can either add one album you search for or automatically
check a list of artists for recent and upcoming albums. It writes to Firestore
using the Firebase Admin SDK and works with the Spark plan. Firestore's normal
Spark usage limits still apply.

1. Install Python 3.10 or newer.
2. From the project root, create a virtual environment and install the importer
   dependency into it:

   ```powershell
   py -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r tools/requirements.txt
   ```

3. In Firebase Console, open **Project settings > Service accounts** and
   generate a private key for the Firebase Admin SDK. Keep the downloaded JSON
   outside this project folder; do not commit or share it.
4. In PowerShell, set the credential path and a contact email for MusicBrainz.
   Replace the example path and email with your own values. The service-account
   path should point to the JSON file you downloaded:

   ```powershell
   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\service-account.json"
   $env:MUSICBRAINZ_CONTACT = "your-email@example.com"
   ```

5. To add one album manually, run the importer and follow its prompts:

   ```powershell
   .\.venv\Scripts\python.exe tools/import_album.py
   ```

### Automatically check selected artists

1. Edit `tools/artists.txt` and add one artist name per line. For an artist
   with an ambiguous name, use `Artist Name | MUSICBRAINZ_ARTIST_ID` on that
   line. The artist ID is the UUID in the artist's MusicBrainz page URL.
2. To import the full catalog of albums and EPs for those artists once, run
   this from the project root. It skips albums already in Firestore:

   ```powershell
   .\.venv\Scripts\python.exe tools/import_album.py --all-releases
   ```

   This can add many albums on the first run and may take a while because the
   catalog API limits request frequency. It imports entries without a known
   release date too. The importer also fetches genres, tracklists, labels,
   formats, and any producer/writer credits MusicBrainz has. For each album it
   uses the earliest available official release for track and label details;
   those can vary by edition. Running it again fills in missing artist or
   detail fields on albums it imported earlier, without creating duplicates.
   To import just one artist without changing `tools/artists.txt`, add the
   `--artist` option:

   ```powershell
   .\.venv\Scripts\python.exe tools/import_album.py --all-releases --artist "Ariana Grande"
   ```

   If MusicBrainz has multiple artists with that exact name, pass the artist
   name and MBID instead: `--artist "Artist Name | MUSICBRAINZ_ARTIST_ID"`.
3. For scheduled runs, save the two settings as Windows user environment
   variables so Task Scheduler can read them. Run this once in PowerShell,
   replacing the example values:

   ```powershell
   [Environment]::SetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS", "C:\path\to\service-account.json", "User")
   [Environment]::SetEnvironmentVariable("MUSICBRAINZ_CONTACT", "your-email@example.com", "User")
   ```

   Close and reopen PowerShell after setting them. These variables store the
   key file's path and your contact email; keep the actual service-account JSON
   outside the project and private.
4. Test the regular sync from the project root. It checks for releases dated
   within the past 30 days or in the future:

   ```powershell
   .\.venv\Scripts\python.exe tools/import_album.py --sync-artists
   ```

5. To run it daily, open **Task Scheduler** in Windows and choose **Create
   Basic Task**. Set a daily trigger. For the action, choose **Start a program**:

   - **Program/script:** the full path to `.venv\Scripts\python.exe` inside
     this project.
   - **Add arguments:** the full path to `tools\import_album.py` followed by
     `--sync-artists`, for example:
     `"C:\path\to\discograde\tools\import_album.py" --sync-artists`
   - **Start in:** the full path to the project folder.

   The computer must be on at the scheduled time. Choose to run the task only
   while you are logged in so it can use your account's environment variables.

The script uses the Admin SDK locally, so it can write without opening album
writes to every app user. No Node.js install or Firebase Functions deployment
is needed.

## Firestore collections

These are the planned collection document shapes. Array fields are marked with
`[]`; nested arrays contain the listed object fields.

- `albums`: `{ id, title, artist, coverUrl, releaseDate, format, label, producers[], writers[], genres[], vibes[], communityScore, ratingCount, trackList[{number, title, duration, score}] }`
- `reviews`: `{ albumId, userId, username, score, text, likes, comments, createdAt }`
- `threads`: `{ albumId, title, artist, coverUrl, replyCount, upvotes, createdAt }`
- `comments`: `{ threadId, userId, username, text, upvotes, createdAt, replies[{userId, username, text, upvotes, createdAt}] }`
- `users`: `{ uid, displayName, handle, avatarUrl, ratingCount, reviewCount, listCount }`
- `lists`: `{ userId, title, albumIds[], coverUrls[], updatedAt }`
