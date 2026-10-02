import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/firebase_service.dart';
import '../utils/score_color.dart';

const _ink = Color(0xFF3F3F3F);
const _teal = Color(0xFF0E8A8A);
const _muted = Color(0xFF808080);
const _placeholder = Color(0xFFE0E0E0);

final _albums = FirebaseService.firestore.collection('albums');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedRankTab = 0;
  late final TabController _rankTabController;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _newReleasesStream;
  Future<List<_Album>>? _allAlbumsFuture;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _rankTabController = TabController(length: 2, vsync: this);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _newReleasesStream = _albums
        .where(
          'releaseDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 30)),
          ),
        )
        .orderBy('releaseDate', descending: true)
        .limit(10)
        .snapshots();
  }

  Future<List<_Album>> _loadAllAlbums() async {
    final snapshot = await _albums.get();
    return snapshot.docs.map(_Album.fromDocument).toList();
  }

  void _onSearchFocusChanged() => setState(() {});

  void _onSearchChanged(String _) {
    if (_searchController.text.trim().isNotEmpty) {
      _allAlbumsFuture ??= _loadAllAlbums();
    }
    setState(() {});
  }

  void _openSearchResults(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _searchFocusNode.unfocus();
    context.push(
      Uri(path: '/search', queryParameters: {'q': query}).toString(),
    );
  }

  @override
  void dispose() {
    _rankTabController.dispose();
    _searchFocusNode
      ..removeListener(_onSearchFocusChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _newReleasesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F5F5),
            body: Center(
              child: Text('Could not load albums.\n${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F5F5),
            body: Center(child: CircularProgressIndicator(color: _teal)),
          );
        }

        final releases = snapshot.data!.docs.map(_Album.fromDocument).toList();
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 56, bottom: 24),
                    child: Center(
                      child: SizedBox(
                        height: 220,
                        child: Image.asset(
                          'assets/assets/AQUINO CCE106 LOGO CROPPED.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(
                              'DISCOGRADE',
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: _ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [_searchField(), _searchResultsDropdown()],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _AiDiscoveryBanner(
                      onTap: () => context.push('/ai-discovery'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel('NEW RELEASES'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: releases.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: AlbumCard(album: releases[index]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _SectionLabel('POPULAR NOW'),
                  const SizedBox(height: 12),
                  _AlbumCarousel(
                    query: _albums
                        .orderBy('communityScore', descending: true)
                        .limit(10),
                    showAnticipatedBadge: true,
                  ),
                  const SizedBox(height: 28),
                  const _SectionLabel('DISCOVER'),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _rankTabs(),
                  ),
                  _RankedAlbums(
                    query: _selectedRankTab == 0
                        ? _albums
                              .orderBy('ratingCount', descending: true)
                              .limit(20)
                        : _albums
                              .orderBy('communityScore', descending: true)
                              .limit(20),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _searchField() {
    final focused = _searchFocusNode.hasFocus;
    final hasQuery = _searchController.text.isNotEmpty;
    final borderColor = focused ? _teal : const Color(0xFFD4D4D4);

    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      textInputAction: TextInputAction.search,
      onChanged: _onSearchChanged,
      onSubmitted: _openSearchResults,
      decoration: InputDecoration(
        hintText: 'Search albums or artists',
        hintStyle: GoogleFonts.inter(fontSize: 14, color: _muted),
        prefixIcon: IconButton(
          tooltip: 'Search',
          onPressed: hasQuery
              ? () => _openSearchResults(_searchController.text)
              : null,
          icon: Icon(Icons.search_rounded, color: focused ? _teal : _muted),
        ),
        suffixIcon: hasQuery
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                color: focused ? _teal : _muted,
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                  _searchFocusNode.requestFocus();
                },
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _teal, width: 1.8),
        ),
      ),
    );
  }

  Widget _searchResultsDropdown() {
    final query = _searchController.text.trim().toLowerCase();
    if (!_searchFocusNode.hasFocus || query.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<_Album>>(
      future: _allAlbumsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _searchPanel(
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Could not search albums right now.'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return _searchPanel(
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _teal,
                  ),
                ),
              ),
            ),
          );
        }

        final results = snapshot.data!
            .where(
              (album) =>
                  album.title.toLowerCase().contains(query) ||
                  album.artist.toLowerCase().contains(query),
            )
            .take(8)
            .toList();

        if (results.isEmpty) {
          return _searchPanel(
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No results',
                  style: GoogleFonts.inter(fontSize: 14, color: _muted),
                ),
              ),
            ),
          );
        }

        return _searchPanel(
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              primary: false,
              itemCount: results.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                indent: 68,
                endIndent: 12,
                color: Color(0xFFEDEDED),
              ),
              itemBuilder: (context, index) => _AlbumSearchResult(
                album: results[index],
                onTap: () {
                  _searchController.clear();
                  _searchFocusNode.unfocus();
                  setState(() {});
                  context.push(
                    '/album/${Uri.encodeComponent(results[index].id)}',
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _searchPanel(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _teal.withValues(alpha: 0.35)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18000000),
          blurRadius: 14,
          offset: Offset(0, 5),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _rankTabs() => TabBar(
    controller: _rankTabController,
    onTap: (index) => setState(() => _selectedRankTab = index),
    indicator: const UnderlineTabIndicator(
      borderSide: BorderSide(color: _teal, width: 3),
      insets: EdgeInsets.symmetric(horizontal: 12),
    ),
    indicatorSize: TabBarIndicatorSize.label,
    dividerColor: Colors.transparent,
    labelColor: _ink,
    unselectedLabelColor: _muted,
    labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
    tabs: const [
      Tab(text: 'TRENDING'),
      Tab(text: 'TOP RATED'),
    ],
  );
}

class _Album {
  const _Album({required this.id, required this.data});

  factory _Album.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) => _Album(id: doc.id, data: doc.data());

  final String id;
  final Map<String, dynamic> data;

  String get title => data['title'] as String? ?? 'Unknown album';
  String get artist => data['artist'] as String? ?? 'Unknown artist';
  String get coverUrl => data['coverUrl'] as String? ?? '';
  int? get score => _asInt(data['communityScore']);
  DateTime? get releaseDate => _searchDate(data['releaseDate']);

  bool get isAnticipated {
    final date = releaseDate;
    return score == null || (date != null && date.isAfter(DateTime.now()));
  }
}

class _SearchData {
  const _SearchData({required this.albums});

  final List<_Album> albums;
}

enum _SearchContentType { albums, artists }

extension on _SearchContentType {
  String get label => switch (this) {
    _SearchContentType.albums => 'Albums',
    _SearchContentType.artists => 'Artists',
  };
}

enum _SearchSort { highestRated, newest, az }

extension on _SearchSort {
  String get label => switch (this) {
    _SearchSort.highestRated => 'Highest Rated',
    _SearchSort.newest => 'Newest',
    _SearchSort.az => 'A-Z',
  };
}

class _SearchResult {
  const _SearchResult({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    this.score,
    this.date,
    this.albumId,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final int? score;
  final DateTime? date;
  final String? albumId;
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.result, required this.onTap});

  final _SearchResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          _CoverImage(url: result.coverUrl, size: 48, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          if (result.score != null) ...[
            const SizedBox(width: 10),
            _ScoreChip(score: result.score!, size: 38),
          ],
        ],
      ),
    ),
  );
}

DateTime? _searchDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

class _AlbumSearchResult extends StatelessWidget {
  const _AlbumSearchResult({required this.album, required this.onTap});

  final _Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          _CoverImage(url: album.coverUrl, size: 44, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _ScoreChip(score: album.score ?? 0, size: 38),
        ],
      ),
    ),
  );
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.initialQuery});

  final String initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _controller;
  late final Future<_SearchData> _catalogFuture;
  late String _query;
  _SearchContentType _contentType = _SearchContentType.albums;
  _SearchSort _sort = _SearchSort.highestRated;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _controller = TextEditingController(text: _query);
    _catalogFuture = _loadCatalog();
  }

  Future<_SearchData> _loadCatalog() async {
    final albums = await _albums.get();
    return _SearchData(albums: albums.docs.map(_Album.fromDocument).toList());
  }

  List<_SearchResult> _resultsFor(_SearchData data, String query) {
    final results = <_SearchResult>[];
    if (query.isEmpty) return results;

    switch (_contentType) {
      case _SearchContentType.albums:
        results.addAll(
          data.albums
              .where(
                (album) =>
                    album.title.toLowerCase().contains(query) ||
                    album.artist.toLowerCase().contains(query),
              )
              .map(
                (album) => _SearchResult(
                  title: album.title,
                  subtitle: album.artist,
                  coverUrl: album.coverUrl,
                  score: album.score,
                  date: album.releaseDate,
                  albumId: album.id,
                ),
              ),
        );
        break;
      case _SearchContentType.artists:
        final grouped = <String, List<_Album>>{};
        for (final album in data.albums) {
          grouped
              .putIfAbsent(album.artist.trim().toLowerCase(), () => [])
              .add(album);
        }
        for (final albums in grouped.values) {
          final artist = albums.first.artist;
          if (!artist.toLowerCase().contains(query)) continue;
          final rated = albums.where((album) => album.score != null).toList();
          final average = rated.isEmpty
              ? null
              : (rated.fold<int>(0, (total, album) => total + album.score!) /
                        rated.length)
                    .round();
          final mostRecent = albums
              .map((album) => album.releaseDate)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (latest, date) =>
                    latest == null || date.isAfter(latest) ? date : latest,
              );
          results.add(
            _SearchResult(
              title: artist,
              subtitle:
                  '${albums.length} ${albums.length == 1 ? 'album' : 'albums'}',
              coverUrl: albums
                  .firstWhere(
                    (album) => album.coverUrl.isNotEmpty,
                    orElse: () => albums.first,
                  )
                  .coverUrl,
              score: average,
              date: mostRecent,
            ),
          );
        }
        break;
    }

    switch (_sort) {
      case _SearchSort.highestRated:
        results.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
        break;
      case _SearchSort.newest:
        results.sort(
          (a, b) => (b.date?.millisecondsSinceEpoch ?? -1).compareTo(
            a.date?.millisecondsSinceEpoch ?? -1,
          ),
        );
        break;
      case _SearchSort.az:
        results.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
    }
    return results;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        foregroundColor: _ink,
        elevation: 0,
        title: Text(
          'Search',
          style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search albums or artists',
                hintStyle: GoogleFonts.inter(fontSize: 14, color: _muted),
                prefixIcon: const Icon(Icons.search_rounded, color: _teal),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                        color: _teal,
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFD4D4D4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _teal, width: 1.8),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                for (final type in _SearchContentType.values)
                  Expanded(child: _contentTab(type)),
                const SizedBox(width: 4),
                PopupMenuButton<_SearchSort>(
                  tooltip: 'Sort search results',
                  initialValue: _sort,
                  onSelected: (sort) => setState(() => _sort = sort),
                  itemBuilder: (context) => [
                    for (final sort in _SearchSort.values)
                      PopupMenuItem(value: sort, child: Text(sort.label)),
                  ],
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      border: Border.all(color: _ink),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Sort: ${_sort.label}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: _ink,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<_SearchData>(
              future: _catalogFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _SearchMessage(
                    icon: Icons.error_outline_rounded,
                    text: 'Could not load search results. Check your connection and try again.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _teal),
                  );
                }
                if (normalizedQuery.isEmpty) {
                  return const _SearchMessage(
                    icon: Icons.search_rounded,
                    text: 'Search albums and artists by name.',
                  );
                }

                final results = _resultsFor(snapshot.data!, normalizedQuery);

                if (results.isEmpty) {
                  return _SearchMessage(
                    icon: Icons.music_off_rounded,
                    text: 'No results for “${_query.trim()}”.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _SearchResultTile(
                        result: result,
                        onTap: result.albumId != null
                            ? () => context.push(
                                '/album/${Uri.encodeComponent(result.albumId!)}',
                              )
                            : _contentType == _SearchContentType.artists
                            ? () {
                                _controller.text = result.title;
                                setState(() {
                                  _query = result.title;
                                  _contentType = _SearchContentType.albums;
                                });
                              }
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentTab(_SearchContentType type) {
    final selected = _contentType == type;
    return InkWell(
      onTap: () => setState(() => _contentType = type),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 38,
              child: Center(
                child: Text(
                  type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? _ink : _muted,
                  ),
                ),
              ),
            ),
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: selected ? _teal : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: _teal),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: _muted),
          ),
        ],
      ),
    ),
  );
}

int? _asInt(Object? value) => value is num ? value.round() : null;

class _AiDiscoveryBanner extends StatelessWidget {
  const _AiDiscoveryBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFEAF5F4),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: _teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find your next album',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Ask Discograde AI for a personal recommendation',
                    style: GoogleFonts.inter(fontSize: 11, color: _muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, size: 18, color: _teal),
          ],
        ),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: _ink.withValues(alpha: 0.6),
      ),
    ),
  );
}

class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    this.showAnticipatedBadge = false,
  });

  final _Album album;
  final bool showAnticipatedBadge;

  @override
  Widget build(BuildContext context) {
    final anticipated = showAnticipatedBadge && album.isAnticipated;
    return InkWell(
      onTap: () => context.push('/album/${Uri.encodeComponent(album.id)}'),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _CoverImage(url: album.coverUrl, size: 130, radius: 12),
                if (anticipated)
                  const Positioned(
                    top: 7,
                    right: 7,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: _teal,
                      child: Icon(
                        Icons.star_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            Text(
              album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _ink.withValues(alpha: 0.5),
              ),
            ),
            if (album.score != null && !anticipated) ...[
              const SizedBox(height: 4),
              _ScoreChip(score: album.score!, compact: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlbumCarousel extends StatelessWidget {
  const _AlbumCarousel({
    required this.query,
    this.showAnticipatedBadge = false,
  });

  final Query<Map<String, dynamic>> query;
  final bool showAnticipatedBadge;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox(height: 200);
          final albums = snapshot.data!.docs.map(_Album.fromDocument).toList();
          return SizedBox(
            height: 200,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: albums.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: AlbumCard(
                  album: albums[index],
                  showAnticipatedBadge: showAnticipatedBadge,
                ),
              ),
            ),
          );
        },
      );
}

class _RankedAlbums extends StatelessWidget {
  const _RankedAlbums({required this.query});

  final Query<Map<String, dynamic>> query;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox(height: 100);
          final albums = snapshot.data!.docs.map(_Album.fromDocument).toList();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _AlbumListRow(rank: index + 1, album: albums[index]),
          );
        },
      );
}

class _AlbumListRow extends StatelessWidget {
  const _AlbumListRow({required this.rank, required this.album});

  final int rank;
  final _Album album;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/album/${Uri.encodeComponent(album.id)}'),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: GoogleFonts.inter(fontSize: 12, color: _muted),
            ),
          ),
          _CoverImage(url: album.coverUrl, size: 48, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                Text(
                  album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (album.score != null) _ScoreChip(score: album.score!, size: 40),
        ],
      ),
    ),
  );
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.score, this.compact = false, this.size});

  final int score;
  final bool compact;
  final double? size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : null,
    decoration: BoxDecoration(
      color: scorePalette(score),
      borderRadius: BorderRadius.circular(compact ? 20 : 10),
    ),
    alignment: Alignment.center,
    child: Text(
      '$score',
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: compact ? 12 : 14,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url, this.size, this.radius = 12});

  final String url;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? const ColoredBox(color: _placeholder)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, _) => const ColoredBox(color: _placeholder),
              errorWidget: (_, _, _) => const ColoredBox(color: _placeholder),
            ),
    ),
  );
}
