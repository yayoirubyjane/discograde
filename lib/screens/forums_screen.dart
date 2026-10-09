import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

const _ink = Color(0xFF3F3F3F);
const _muted = Color(0xFF858585);
const _placeholder = Color(0xFFE0E0E0);
const _teal = Color(0xFF0E8A8A);

class ForumsScreen extends StatefulWidget {
  const ForumsScreen({super.key});

  @override
  State<ForumsScreen> createState() => _ForumsScreenState();
}

class _ForumsScreenState extends State<ForumsScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _recentScrollController = ScrollController();
  late final TabController _tabController;
  late final Query<Map<String, dynamic>> _trendingQuery;
  late final Query<Map<String, dynamic>> _recentQuery;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _trendingStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _recentStream;
  QueryDocumentSnapshot<Map<String, dynamic>>? _recentFirstPageLast;

  bool _searching = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _additionalRecent = [];
  final List<Map<String, dynamic>> _localRecentThreads = [];

  @override
  void initState() {
    super.initState();
    final threads = FirebaseFirestore.instance.collection('threads');
    _trendingQuery = threads.orderBy('upvotes', descending: true).limit(20);
    _recentQuery = threads.orderBy('createdAt', descending: true).limit(20);
    _trendingStream = _trendingQuery.snapshots();
    _recentStream = _recentQuery.snapshots();
    _tabController = TabController(length: 2, vsync: this);
    _recentScrollController.addListener(_onRecentScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _recentScrollController
      ..removeListener(_onRecentScroll)
      ..dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onRecentScroll() {
    if (_recentScrollController.hasClients &&
        _recentScrollController.position.extentAfter < 240) {
      _loadMoreRecent();
    }
  }

  Future<void> _loadMoreRecent() async {
    if (_loadingMore || !_hasMore) return;
    final cursor = _additionalRecent.isNotEmpty
        ? _additionalRecent.last
        : _recentFirstPageLast;
    if (cursor == null) return;

    setState(() => _loadingMore = true);
    try {
      final page = await _recentQuery
          .startAfterDocument(cursor)
          .limit(20)
          .get();
      if (!mounted) return;
      setState(() {
        _additionalRecent = [..._additionalRecent, ...page.docs];
        _hasMore = page.docs.length == 20;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load more discussions: $error')),
      );
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _searchController.clear();
    });
  }

  Future<void> _startNewDiscussion() async {
    while (mounted) {
      final target = await Navigator.of(context, rootNavigator: true)
          .push<_DiscussionTarget>(
            MaterialPageRoute(
              builder: (_) => const _SelectDiscussionTargetScreen(),
            ),
          );
      if (target == null || !mounted) return;

      final result = await Navigator.of(context, rootNavigator: true)
          .push<_DiscussionComposerResult>(
            MaterialPageRoute(
              builder: (_) => _StartDiscussionScreen(target: target),
            ),
          );
      if (!mounted || result == null) return;
      if (result case _ChangeDiscussionTarget()) continue;

      if (result case _PostDiscussion(:final thread)) {
        try {
          await _saveDiscussion(thread);
          if (!mounted) return;
          _tabController.animateTo(1);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Discussion posted.')));
        } on FirebaseException catch (error) {
          if (!mounted) return;
          final message = error.code == 'permission-denied'
              ? 'Firestore blocked this account from posting. Check your Firestore rules.'
              : 'Could not post discussion (${error.code}): ${error.message ?? 'Please try again.'}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 6),
            ),
          );
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not post discussion: $error')),
          );
        }
        return;
      }
    }
  }

  Future<void> _saveDiscussion(Map<String, dynamic> draft) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'unauthenticated',
        message: 'Sign in to post a discussion.',
      );
    }

    var username = user.email?.split('@').first ?? 'listener';
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      username = profile.data()?['handle'] as String? ?? username;
    } on FirebaseException {
      // Profile reads can be unavailable for older accounts; posting can still
      // use the email-derived username as a fallback.
    }
    username = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (username.isEmpty) username = 'listener';

    final thread = <String, dynamic>{
      ...draft,
      'userId': user.uid,
      'username': username,
      'authorPhotoUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'replyCount': 0,
      'upvotes': 0,
    };
    await FirebaseFirestore.instance.collection('threads').add(thread);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF5F5F5),
      foregroundColor: _ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 20,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: animation.drive(
              Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero),
            ),
            child: child,
          ),
        ),
        child: _searching
            ? TextField(
                key: const ValueKey('forum-search-field'),
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(fontSize: 14, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Search discussions',
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: _muted),
                  prefixIcon: const Icon(Icons.search, color: _muted, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF2F2F2),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              )
            : Text(
                'Forums',
                key: const ValueKey('forum-title'),
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
      ),
      actions: [
        IconButton(
          tooltip: _searching ? 'Close search' : 'Search forums',
          onPressed: _toggleSearch,
          icon: Icon(_searching ? Icons.close : Icons.search, color: _ink),
        ),
        const SizedBox(width: 8),
      ],
      bottom: TabBar(
        controller: _tabController,
        dividerColor: const Color(0x1A3F3F3F),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: _teal, width: 3),
          insets: EdgeInsets.symmetric(horizontal: 20),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: _ink,
        unselectedLabelColor: _muted,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        tabs: const [
          Tab(text: 'TRENDING'),
          Tab(text: 'RECENT'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tabController,
      children: [_trendingTab(), _recentTab()],
    ),
    floatingActionButton: _searching
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 88),
            child: FloatingActionButton(
              onPressed: _startNewDiscussion,
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              tooltip: 'New discussion',
              child: const Icon(Icons.add),
            ),
          ),
  );

  Widget _trendingTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _trendingStream,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return _errorMessage('Could not load trending discussions.');
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator(color: _teal));
      final threads = _filterThreads(snapshot.data!.docs);
      return _threadList(
        threads,
        key: const PageStorageKey('trending-threads'),
      );
    },
  );

  Widget _recentTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _recentStream,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return _errorMessage('Could not load recent discussions.');
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator(color: _teal));

      final firstPage = snapshot.data!.docs;
      _recentFirstPageLast = firstPage.isEmpty ? null : firstPage.last;
      if (_additionalRecent.isEmpty) _hasMore = firstPage.length == 20;
      final ids = firstPage.map((thread) => thread.id).toSet();
      final allThreads = [
        ...firstPage,
        ..._additionalRecent.where((thread) => !ids.contains(thread.id)),
      ];
      final filtered = _filterThreads(allThreads);
      final localThreads = _filterLocalThreads(_localRecentThreads);

      return Column(
        children: [
          Expanded(
            child: _threadList(
              filtered,
              localThreads: localThreads,
              controller: _recentScrollController,
              key: const PageStorageKey('recent-threads'),
            ),
          ),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
              ),
            ),
        ],
      );
    },
  );

  List<Map<String, dynamic>> _filterLocalThreads(
    List<Map<String, dynamic>> threads,
  ) {
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return threads;
    return threads.where((thread) {
      final title = (thread['title'] as String? ?? '').toLowerCase();
      final artist = (thread['artist'] as String? ?? '').toLowerCase();
      final topicTitle = (thread['topicTitle'] as String? ?? '').toLowerCase();
      final preview = (thread['context'] as String? ?? '').toLowerCase();
      return title.contains(term) ||
          artist.contains(term) ||
          topicTitle.contains(term) ||
          preview.contains(term);
    }).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterThreads(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> threads,
  ) {
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return threads;
    return threads.where((thread) {
      final data = thread.data();
      final title = (data['title'] as String? ?? '').toLowerCase();
      final artist = (data['artist'] as String? ?? '').toLowerCase();
      return title.contains(term) || artist.contains(term);
    }).toList();
  }

  Widget _threadList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> threads, {
    List<Map<String, dynamic>> localThreads = const [],
    ScrollController? controller,
    Key? key,
  }) {
    if (threads.isEmpty && localThreads.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.isEmpty
              ? 'No discussions yet.'
              : 'No matching discussions.',
          style: GoogleFonts.inter(fontSize: 13, color: _muted),
        ),
      );
    }
    return Container(
      key: key,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView.separated(
        controller: controller,
        itemCount: localThreads.length + threads.length,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemBuilder: (context, index) {
          if (index < localThreads.length) {
            return _ThreadCard(
              thread: localThreads[index],
              onTap: () async {
                final shouldDelete = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => _TemporaryThreadPreviewScreen(
                      thread: localThreads[index],
                    ),
                  ),
                );
                if (shouldDelete == true && mounted) {
                  setState(
                    () => _localRecentThreads.remove(localThreads[index]),
                  );
                }
              },
            );
          }
          final thread = threads[index - localThreads.length];
          return _ThreadCard(
            thread: thread.data(),
            onTap: () => context.push('/thread/${thread.id}'),
          );
        },
        separatorBuilder: (_, _) => const Padding(
          padding: EdgeInsets.only(left: 76, right: 16),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
        ),
      ),
    );
  }

  Widget _errorMessage(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        style: GoogleFonts.inter(fontSize: 13, color: _muted),
      ),
    ),
  );
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.thread, required this.onTap});

  final Map<String, dynamic> thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = thread['title'] as String? ?? 'Untitled discussion';
    final artist = thread['artist'] as String? ?? '';
    final topicTitle = thread['topicTitle'] as String?;
    final coverUrl = thread['coverUrl'] as String? ?? '';
    final preview = (thread['context'] as String?) ?? _commentPreview(thread);
    final topicSubtitle = topicTitle == null
        ? artist
        : artist.isEmpty
        ? 'About $topicTitle'
        : 'About $topicTitle · $artist';
    final timestamp = _relativeTime(thread['createdAt']);
    final replies = _count(thread['replyCount']);
    final upvotes = _count(thread['upvotes']);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: coverUrl.isEmpty
                    ? const ColoredBox(color: _placeholder)
                    : CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            const ColoredBox(color: _placeholder),
                        errorWidget: (_, _, _) =>
                            const ColoredBox(color: _placeholder),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  Text(
                    topicSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: _muted),
                  ),
                  Text(
                    preview.isEmpty ? 'Start the conversation' : preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: _muted,
                    ),
                  ),
                  if (timestamp.isNotEmpty)
                    Text(
                      timestamp,
                      style: GoogleFonts.inter(fontSize: 10, color: _muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ThreadCount(icon: Icons.chat_bubble_outline, count: replies),
                const SizedBox(height: 8),
                _ThreadCount(icon: Icons.arrow_upward_rounded, count: upvotes),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadCount extends StatelessWidget {
  const _ThreadCount({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: _muted),
      const SizedBox(width: 4),
      Text('$count', style: GoogleFonts.inter(fontSize: 10, color: _muted)),
    ],
  );
}

String _commentPreview(Map<String, dynamic> data) {
  final direct = data['latestCommentPreview'] ?? data['commentPreview'];
  if (direct is String) return direct;
  final comment = data['latestComment'];
  if (comment is String) return comment;
  if (comment is Map) return comment['text'] as String? ?? '';
  return '';
}

int _count(Object? value) => value is num ? value.toInt() : 0;

String _relativeTime(Object? value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (date == null) return '';
  final elapsed = DateTime.now().difference(date);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  return '${date.month}/${date.day}/${date.year}';
}

class _DiscussionTarget {
  const _DiscussionTarget({
    required this.title,
    required this.artist,
    this.coverUrl = '',
    this.albumId,
    this.isArtist = false,
  });

  final String title;
  final String artist;
  final String coverUrl;
  final String? albumId;
  final bool isArtist;

  String get subtitle => isArtist ? 'Artist' : artist;
  String get promptSubject => isArtist ? 'this artist' : 'this album';
}

const _discussionMockTargets = [
  _DiscussionTarget(title: 'Detour', artist: 'Kim Petras'),
  _DiscussionTarget(title: 'Ctrl', artist: 'SZA'),
  _DiscussionTarget(title: 'GUTS', artist: 'Olivia Rodrigo'),
  _DiscussionTarget(title: 'Crash', artist: 'Charli xcx'),
  _DiscussionTarget(title: 'Kim Petras', artist: '', isArtist: true),
  _DiscussionTarget(title: 'SZA', artist: '', isArtist: true),
  _DiscussionTarget(title: 'Olivia Rodrigo', artist: '', isArtist: true),
];

class _SelectDiscussionTargetScreen extends StatefulWidget {
  const _SelectDiscussionTargetScreen();

  @override
  State<_SelectDiscussionTargetScreen> createState() =>
      _SelectDiscussionTargetScreenState();
}

class _SelectDiscussionTargetScreenState
    extends State<_SelectDiscussionTargetScreen> {
  static Future<List<_DiscussionTarget>>? _cachedTargetsFuture;

  final _searchController = TextEditingController();
  late final Future<List<_DiscussionTarget>> _targetsFuture;

  @override
  void initState() {
    super.initState();
    _targetsFuture = _cachedTargetsFuture ??= _loadTargets();
  }

  Future<List<_DiscussionTarget>> _loadTargets() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('albums')
          .get();
      final albums = <_DiscussionTarget>[];
      final artists = <String, _DiscussionTarget>{};
      for (final document in snapshot.docs) {
        final data = document.data();
        final title = data['title'] as String? ?? '';
        final artist = data['artist'] as String? ?? '';
        if (title.trim().isEmpty) continue;
        final coverUrl = data['coverUrl'] as String? ?? '';
        albums.add(
          _DiscussionTarget(
            title: title,
            artist: artist,
            coverUrl: coverUrl,
            albumId: document.id,
          ),
        );
        if (artist.trim().isNotEmpty) {
          artists.putIfAbsent(
            artist.toLowerCase(),
            () => _DiscussionTarget(
              title: artist,
              artist: '',
              coverUrl: coverUrl,
              isArtist: true,
            ),
          );
        }
      }
      albums.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      final artistTargets = artists.values.toList()
        ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      return [...albums, ...artistTargets];
    } catch (_) {
      return _discussionMockTargets;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Select Album or Artist',
          style: GoogleFonts.inter(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(fontSize: 14, color: _ink),
              decoration: InputDecoration(
                hintText: 'Search albums or artists',
                hintStyle: GoogleFonts.inter(fontSize: 14, color: _muted),
                prefixIcon: const Icon(Icons.search, color: _teal),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close, color: _muted),
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE1E1E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _teal, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_DiscussionTarget>>(
              future: _targetsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _teal),
                  );
                }
                final results = snapshot.data!.where((target) {
                  return target.title.toLowerCase().contains(query) ||
                      target.artist.toLowerCase().contains(query) ||
                      target.subtitle.toLowerCase().contains(query);
                }).toList();
                if (results.isEmpty) {
                  return Center(
                    child: Text(
                      'No results',
                      style: GoogleFonts.inter(fontSize: 14, color: _muted),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final target = results[index];
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).pop(target),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              _DiscussionCover(target: target, size: 52),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      target.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: _ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      target.subtitle,
                                      style: GoogleFonts.inter(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: _muted),
                            ],
                          ),
                        ),
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
}

class _StartDiscussionScreen extends StatefulWidget {
  const _StartDiscussionScreen({required this.target});

  final _DiscussionTarget target;

  @override
  State<_StartDiscussionScreen> createState() => _StartDiscussionScreenState();
}

class _StartDiscussionScreenState extends State<_StartDiscussionScreen> {
  final _titleController = TextEditingController();
  final _textController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _post() {
    final discussionTitle = _titleController.text.trim();
    final text = _textController.text.trim();
    if (discussionTitle.isEmpty || text.isEmpty) return;
    final target = widget.target;
    Navigator.of(context).pop(
      _PostDiscussion({
        'title': discussionTitle,
        'topicTitle': target.title,
        'artist': target.isArtist ? target.title : target.artist,
        'coverUrl': target.coverUrl,
        'albumId': target.albumId,
        'isArtist': target.isArtist,
        'context': text,
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF5F5F5),
      foregroundColor: _ink,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Start Discussion',
        style: GoogleFonts.inter(
          color: _ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const _ChangeDiscussionTarget()),
          child: Text(
            'Change',
            style: GoogleFonts.inter(color: _teal, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _DiscussionCover(target: widget.target, size: 54),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.target.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: _ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.target.subtitle,
                          style: GoogleFonts.inter(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Discussion title',
              style: GoogleFonts.inter(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              minLines: 1,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(fontSize: 14, color: _ink),
              decoration: InputDecoration(
                hintText: 'Give your discussion a title',
                hintStyle: GoogleFonts.inter(color: _muted),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE1E1E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _teal, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              "What's on your mind about ${widget.target.promptSubject}?",
              style: GoogleFonts.inter(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(fontSize: 14, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Add context to your discussion...',
                  hintStyle: GoogleFonts.inter(color: _muted),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE1E1E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _teal, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed:
                    _titleController.text.trim().isEmpty ||
                        _textController.text.trim().isEmpty
                    ? null
                    : _post,
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  disabledBackgroundColor: const Color(0xFFBDBDBD),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Post',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DiscussionCover extends StatelessWidget {
  const _DiscussionCover({required this.target, required this.size});

  final _DiscussionTarget target;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox.square(
      dimension: size,
      child: target.coverUrl.isEmpty
          ? const ColoredBox(
              color: _placeholder,
              child: Icon(Icons.album_outlined, color: _muted),
            )
          : CachedNetworkImage(
              imageUrl: target.coverUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) => const ColoredBox(color: _placeholder),
              errorWidget: (_, _, _) => const ColoredBox(color: _placeholder),
            ),
    ),
  );
}

sealed class _DiscussionComposerResult {
  const _DiscussionComposerResult();
}

class _ChangeDiscussionTarget extends _DiscussionComposerResult {
  const _ChangeDiscussionTarget();
}

class _PostDiscussion extends _DiscussionComposerResult {
  const _PostDiscussion(this.thread);

  final Map<String, dynamic> thread;
}

class _TemporaryThreadPreviewScreen extends StatefulWidget {
  const _TemporaryThreadPreviewScreen({required this.thread});

  final Map<String, dynamic> thread;

  @override
  State<_TemporaryThreadPreviewScreen> createState() =>
      _TemporaryThreadPreviewScreenState();
}

class _TemporaryThreadPreviewScreenState
    extends State<_TemporaryThreadPreviewScreen> {
  final _replyController = TextEditingController();
  final List<_PreviewComment> _localReplies = [];
  _PreviewComment? _replyingTo;
  _PreviewCommenter _currentUser = const _PreviewCommenter(
    username: 'listener',
  );

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    var commenter = _PreviewCommenter(
      username: user.email?.split('@').first ?? 'listener',
      photoUrl: user.photoURL,
    );
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final profile = snapshot.data();
      if (profile != null) {
        commenter = _PreviewCommenter(
          username: profile['handle'] as String? ?? commenter.username,
          photoUrl: user.photoURL,
          photoBase64: profile['photoBase64'] as String?,
        );
      }
    } catch (_) {
      // Use the signed-in account details if its profile document is unavailable.
    }
    if (mounted) setState(() => _currentUser = commenter);
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  void _addReply() {
    final reply = _replyController.text.trim();
    if (reply.isEmpty) return;
    setState(() {
      final comment = _PreviewComment(text: reply, commenter: _currentUser);
      if (_replyingTo == null) {
        _localReplies.add(comment);
      } else {
        _replyingTo!.replies.add(comment);
        _replyingTo!.showReplies = true;
      }
      _replyingTo = null;
      _replyController.clear();
    });
  }

  int get _replyCount => _localReplies.fold<int>(
    0,
    (total, comment) => total + 1 + _countReplies(comment),
  );

  int _countReplies(_PreviewComment comment) => comment.replies.fold<int>(
    0,
    (total, reply) => total + 1 + _countReplies(reply),
  );

  void _appendReplyCards(
    List<_PreviewComment> comments,
    int depth,
    List<Widget> cards,
  ) {
    for (final comment in comments) {
      cards.add(_commentCard(comment, depth: depth));
      if (comment.showReplies) {
        _appendReplyCards(comment.replies, depth + 1, cards);
      }
    }
  }

  void _showCommenterProfile(_PreviewCommenter commenter) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewAvatar(commenter: commenter, radius: 38),
            const SizedBox(height: 12),
            Text(
              _atHandle(commenter.username),
              style: GoogleFonts.inter(color: _muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentCard(_PreviewComment comment, {int depth = 0}) => Container(
    // Keep replies in a flat list with a capped indent, so deeply nested
    // replies do not keep shrinking the available text width.
    margin: EdgeInsets.only(bottom: 10, left: depth == 0 ? 0 : 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: depth == 0 ? null : Border.all(color: const Color(0xFFEAEAEA)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _showCommenterProfile(comment.commenter),
          borderRadius: BorderRadius.circular(22),
          child: Row(
            children: [
              _PreviewAvatar(commenter: comment.commenter, radius: 17),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _atHandle(comment.commenter.username),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          comment.text,
          style: GoogleFonts.inter(color: _ink, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: comment.liked ? 'Unlike comment' : 'Like comment',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    comment.liked = !comment.liked;
                    comment.likes += comment.liked ? 1 : -1;
                  }),
                  icon: Icon(
                    comment.liked ? Icons.favorite : Icons.favorite_border,
                    color: comment.liked ? _teal : _muted,
                    size: 18,
                  ),
                ),
                Text(
                  '${comment.likes}',
                  style: GoogleFonts.inter(color: _muted, fontSize: 12),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _replyingTo = comment;
                  _replyController.text = '';
                });
              },
              style: TextButton.styleFrom(
                foregroundColor: _teal,
                minimumSize: const Size(44, 40),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                'Reply',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (comment.replies.isNotEmpty)
              TextButton(
                onPressed: () =>
                    setState(() => comment.showReplies = !comment.showReplies),
                style: TextButton.styleFrom(
                  foregroundColor: _teal,
                  minimumSize: const Size(44, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  '${comment.showReplies ? 'Hide' : 'Show'} ${_countReplies(comment)} ${_countReplies(comment) == 1 ? 'reply' : 'replies'}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final topic = thread['topicTitle'] as String? ?? '';
    final artist = thread['artist'] as String? ?? '';
    final coverUrl = thread['coverUrl'] as String? ?? '';
    final title = thread['title'] as String? ?? 'Discussion';
    final postContext = thread['context'] as String? ?? '';
    final replyCards = <Widget>[];
    _appendReplyCards(_localReplies, 0, replyCards);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: coverUrl.isEmpty
                    ? const ColoredBox(
                        color: _placeholder,
                        child: Icon(Icons.album_outlined, color: _muted),
                      )
                    : CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            const ColoredBox(color: _placeholder),
                        errorWidget: (_, _, _) =>
                            const ColoredBox(color: _placeholder),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    topic,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () => _showCommenterProfile(_currentUser),
                      customBorder: const CircleBorder(),
                      child: _PreviewAvatar(
                        commenter: _currentUser,
                        radius: 20,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: InkWell(
                        onTap: () => _showCommenterProfile(_currentUser),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _atHandle(_currentUser.username),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            Text(
                              _formatPostTimestamp(thread['createdAt']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More discussion options',
                      onSelected: (value) async {
                        if (value != 'delete') return;
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(
                              'Delete temporary discussion?',
                              style: GoogleFonts.inter(
                                color: _ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            content: Text(
                              'This will remove the post from your local preview.',
                              style: GoogleFonts.inter(color: _muted),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.inter(color: _ink),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: Text(
                                  'Delete',
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFFBA011A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && context.mounted) {
                          Navigator.of(context).pop(true);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete temporary discussion'),
                        ),
                      ],
                      icon: const Icon(Icons.more_horiz, color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: _ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  postContext,
                  style: GoogleFonts.inter(
                    color: _ink,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: _muted,
                    ),
                    const SizedBox(width: 5),
                    Text('0', style: GoogleFonts.inter(color: _muted)),
                    const SizedBox(width: 18),
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 17,
                      color: _muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$_replyCount replies',
                      style: GoogleFonts.inter(color: _muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_replyCount == 0) ...[
            const SizedBox(height: 20),
            Text(
              'REPLIES',
              style: GoogleFonts.inter(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'No replies yet. Start the conversation.',
                style: GoogleFonts.inter(fontSize: 13, color: _muted),
              ),
            ),
          ] else ...[
            const SizedBox(height: 20),
            Text(
              'REPLIES',
              style: GoogleFonts.inter(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            ...replyCards,
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0x143F3F3F))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingTo case final parent?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7, left: 4, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Replying to ${_atHandle(parent.commenter.username)}',
                          style: GoogleFonts.inter(fontSize: 12, color: _muted),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel reply',
                        onPressed: () => setState(() => _replyingTo = null),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18, color: _muted),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _addReply(),
                      style: GoogleFonts.inter(fontSize: 13, color: _ink),
                      decoration: InputDecoration(
                        hintText: _replyingTo == null
                            ? 'Add a reply…'
                            : 'Reply to ${_atHandle(_replyingTo!.commenter.username)}…',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: _muted,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send reply',
                    onPressed: _replyController.text.trim().isEmpty
                        ? null
                        : _addReply,
                    color: _teal,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewCommenter {
  const _PreviewCommenter({
    required this.username,
    this.photoUrl,
    this.photoBase64,
  });

  final String username;
  final String? photoUrl;
  final String? photoBase64;
}

class _PreviewComment {
  _PreviewComment({required this.text, required this.commenter});

  final String text;
  final _PreviewCommenter commenter;
  final List<_PreviewComment> replies = [];
  int likes = 0;
  bool liked = false;
  bool showReplies = false;
}

class _PreviewAvatar extends StatelessWidget {
  const _PreviewAvatar({required this.commenter, required this.radius});

  final _PreviewCommenter commenter;
  final double radius;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    final encodedPhoto = commenter.photoBase64;
    if (encodedPhoto != null && encodedPhoto.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(encodedPhoto));
      } catch (_) {
        image = null;
      }
    }
    image ??= commenter.photoUrl == null
        ? null
        : NetworkImage(commenter.photoUrl!);
    return CircleAvatar(
      radius: radius,
      backgroundColor: _teal,
      backgroundImage: image,
      child: image == null
          ? Text(
              commenter.username.isEmpty
                  ? '?'
                  : commenter.username.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.9,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

String _atHandle(String username) =>
    username.startsWith('@') ? username : '@$username';

String _formatPostTimestamp(Object? value) {
  final date = switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    _ => null,
  };
  if (date == null) return 'time unavailable';
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final meridiem = date.hour < 12 ? 'AM' : 'PM';
  return '${months[date.month - 1]} ${date.day}, ${date.year} · $hour:$minute $meridiem';
}
