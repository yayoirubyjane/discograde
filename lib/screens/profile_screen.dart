import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import 'review_detail_screen.dart';
import '../utils/score_color.dart';

var _profileVisitSequence = 0;

String _nextProfileVisit() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_profileVisitSequence++}';

String profileRouteLocation(String userId) =>
    '/user/${Uri.encodeComponent(userId)}?visit=${_nextProfileVisit()}';

String profileConnectionsRouteLocation(String userId, String relationship) =>
    '/user/${Uri.encodeComponent(userId)}/$relationship?visit=${_nextProfileVisit()}';

const _ink = Color(0xFF3F3F3F);
const _muted = Color(0xFF858585);
const _teal = Color(0xFF0E8A8A);
const _placeholder = Color(0xFFE0E0E0);
const _red = Color(0xFFBA011A);
const _navy = Color(0xFF0B4B8B);
const _profileGenreOptions = [
  'Pop',
  'Rock',
  'Hip-Hop',
  'R&B',
  'Electronic',
  'Jazz',
  'Classical',
  'Metal',
  'Country',
  'Indie',
  'Folk',
  'Latin',
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.userId});

  final String? userId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final String? _uid;
  late final String? _profileUid;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>? _reviewsStream;
  late final Query<Map<String, dynamic>>? _reviewsQuery;
  late final Query<Map<String, dynamic>>? _listsQuery;
  late final Query<Map<String, dynamic>>? _forumPostsQuery;
  late Future<QuerySnapshot<Map<String, dynamic>>>? _reviewsFuture;
  late Future<QuerySnapshot<Map<String, dynamic>>>? _listsFuture;
  late Future<QuerySnapshot<Map<String, dynamic>>>? _forumPostsFuture;
  int _lastTabIndex = 0;
  bool _followBusy = false;

  bool get _isOwnProfile => _uid != null && _uid == _profileUid;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _profileUid = widget.userId ?? _uid;
    if (_profileUid case final uid?) {
      _userStream = _firestore.collection('users').doc(uid).snapshots();
      _reviewsQuery = _firestore
          .collection('reviews')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true);
      _reviewsStream = _reviewsQuery!.snapshots();
      _reviewsFuture = _loadReviews();
      _listsQuery = _firestore
          .collection('lists')
          .where('userId', isEqualTo: uid)
          .orderBy('updatedAt', descending: true);
      _listsFuture = _loadLists();
      _forumPostsQuery = _firestore
          .collection('threads')
          .where('userId', isEqualTo: uid);
      _forumPostsFuture = _loadForumPosts();
    } else {
      _userStream = null;
      _reviewsStream = null;
      _reviewsQuery = null;
      _listsQuery = null;
      _forumPostsQuery = null;
      _reviewsFuture = null;
      _listsFuture = null;
      _forumPostsFuture = null;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.index == _lastTabIndex) return;
    _lastTabIndex = _tabController.index;
    if (_lastTabIndex == 0 && mounted && _reviewsQuery != null) {
      setState(() {
        _reviewsFuture = _loadReviews();
      });
    }
    if (_lastTabIndex == 2 && mounted && _forumPostsQuery != null) {
      setState(() {
        _forumPostsFuture = _loadForumPosts();
      });
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadReviews() =>
      _reviewsQuery!.get().timeout(const Duration(seconds: 15));

  @override
  Widget build(BuildContext context) {
    if (_profileUid == null) return _signedOutView();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return _errorView('Could not load your profile. ${snapshot.error}');
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: _teal)),
          );
        }
        if (!snapshot.data!.exists)
          return _errorView('This profile is unavailable.');
        final user = snapshot.data!.data() ?? <String, dynamic>{};
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _reviewsStream,
                  builder: (context, reviewSnapshot) =>
                      FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        future: _listsFuture,
                        builder: (context, listSnapshot) => _profileHeader(
                          user,
                          ratingsCount: reviewSnapshot.hasData
                              ? reviewSnapshot.data!.docs.length
                              : null,
                          reviewsCount: reviewSnapshot.hasData
                              ? reviewSnapshot.data!.docs.length
                              : null,
                          listsCount: listSnapshot.hasData
                              ? listSnapshot.data!.docs.length
                              : null,
                        ),
                      ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedTabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    indicator: const UnderlineTabIndicator(
                      borderSide: BorderSide(color: _teal, width: 3),
                      insets: EdgeInsets.symmetric(horizontal: 24),
                    ),
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: const Color(0xFFE6E6E6),
                    labelColor: _ink,
                    unselectedLabelColor: _muted,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    tabs: const [
                      Tab(text: 'REVIEWS'),
                      Tab(text: 'LISTS'),
                      Tab(text: 'FORUMS'),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [_reviewsTab(), _listsTab(), _forumPostsTab()],
            ),
          ),
        );
      },
    );
  }

  Widget _profileHeader(
    Map<String, dynamic> user, {
    int? ratingsCount,
    int? reviewsCount,
    int? listsCount,
  }) {
    final handle = _handle(
      user['handle'] as String? ?? _legacyUsername(user['displayName']),
    );
    final ratings = ratingsCount ?? _number(user['ratingCount']);
    final reviews = reviewsCount ?? _number(user['reviewCount']);
    final lists = listsCount ?? _number(user['listCount']);
    final aboutMe = (user['aboutMe'] as String? ?? '').trim();
    final favoriteGenres = user['favoriteGenres'] is List
        ? (user['favoriteGenres'] as List)
              .whereType<String>()
              .map((genre) => genre.trim())
              .where((genre) => genre.isNotEmpty)
              .toList()
        : <String>[];
    final avatarBytes = _decodeAvatar(user['photoBase64']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 18),
      child: Column(
        children: [
          Align(
            alignment: _isOwnProfile
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: IconButton(
              tooltip: _isOwnProfile ? 'Log out' : 'Back',
              onPressed: _isOwnProfile ? _logOut : () => context.pop(),
              icon: Icon(
                _isOwnProfile ? Icons.logout_rounded : Icons.arrow_back,
                color: _teal,
              ),
            ),
          ),
          CircleAvatar(
            radius: 40,
            backgroundColor: _navy,
            foregroundImage: avatarBytes == null
                ? null
                : MemoryImage(avatarBytes),
            child: avatarBytes == null
                ? Text(
                    _initials(handle.replaceFirst('@', '')),
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          Text(
            handle,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          _relationshipStats(),
          if (aboutMe.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                aboutMe,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: _muted),
              ),
            ),
          ],
            if (favoriteGenres.isNotEmpty) ...[
              SizedBox(height: aboutMe.isEmpty ? 8 : 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final genre in favoriteGenres)
                          Chip(
                            label: Text(genre),
                            side: BorderSide(color: _muted),
                            backgroundColor: Colors.white,
                            labelStyle: GoogleFonts.inter(
                              fontSize: 11,
                              color: _muted,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _StatCell(value: ratings, label: 'RATINGS'),
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0xFFEAEAEA),
                  ),
                  Expanded(
                    child: _StatCell(value: reviews, label: 'REVIEWS'),
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0xFFEAEAEA),
                  ),
                  Expanded(
                    child: _StatCell(value: lists, label: 'LISTS'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_isOwnProfile)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: () => _openEditProfile(user),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: Color(0xFFB8B8B8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Edit Profile',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            _followButton(),
        ],
      ),
    );
  }

  Widget _relationshipStats() {
    final uid = _profileUid;
    if (uid == null) return const SizedBox.shrink();
    final userRef = _firestore.collection('users').doc(uid);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _relationshipCount(userRef.collection('followers'), 'Followers'),
        const SizedBox(width: 20),
        _relationshipCount(userRef.collection('following'), 'Following'),
      ],
    );
  }

  Widget _relationshipCount(
    CollectionReference<Map<String, dynamic>> relationship,
    String label,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: relationship.snapshots(),
    builder: (context, snapshot) {
      final count = snapshot.data?.docs.length ?? 0;
      return InkWell(
        onTap: () => _openPeople(relationship.id),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.inter(fontSize: 12),
              children: [
                TextSpan(
                  text: '${_compactCount(count)} ',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: label,
                  style: const TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _followButton() {
    final currentId = _uid;
    final profileId = _profileUid;
    if (currentId == null || profileId == null || currentId == profileId) {
      return const SizedBox.shrink();
    }
    final followingRef = _firestore
        .collection('users')
        .doc(currentId)
        .collection('following')
        .doc(profileId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: followingRef.snapshots(),
      builder: (context, snapshot) {
        final following = snapshot.data?.exists ?? false;
        return SizedBox(
          width: double.infinity,
          height: 46,
          child: following
              ? OutlinedButton.icon(
                  onPressed: _followBusy ? null : _toggleFollow,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Following'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal,
                    side: const BorderSide(color: _teal),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                )
              : FilledButton.icon(
                  onPressed: _followBusy ? null : _toggleFollow,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Follow'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<void> _toggleFollow() async {
    final currentId = _uid;
    final profileId = _profileUid;
    if (currentId == null || profileId == null || currentId == profileId)
      return;
    setState(() => _followBusy = true);
    try {
      await _toggleFollowRelationship(currentId, profileId);
    } catch (error) {
      _showSnack('Could not update follow status: $error');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  void _openPeople(String relationship) {
    final uid = _profileUid;
    if (uid == null) return;
    context.push(profileConnectionsRouteLocation(uid, relationship));
  }

  Widget _reviewsTab() => FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
    future: _reviewsFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load reviews. ${snapshot.error}',
                  style: GoogleFonts.inter(color: _muted),
                  textAlign: TextAlign.center,
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _reviewsFuture = _loadReviews()),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator(color: _teal));
      final reviews = snapshot.data!.docs;
      if (reviews.isEmpty) return _emptyMessage('No reviews yet.');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: reviews.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ProfileReviewCard(
            reviewId: reviews[index].id,
            review: reviews[index].data(),
            onChanged: () {
              if (mounted) {
                setState(() {
                  _reviewsFuture = _loadReviews();
                });
              }
            },
          ),
        ),
      );
    },
  );

  Widget _listsTab() => FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
    future: _listsFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load lists. ${snapshot.error}',
                  style: GoogleFonts.inter(color: _muted),
                  textAlign: TextAlign.center,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _listsFuture = _loadLists();
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator(color: _teal));
      final lists = snapshot.data!.docs;
      if (lists.isEmpty && !_isOwnProfile)
        return _emptyMessage('No lists yet.');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: lists.length + (_isOwnProfile ? 1 : 0),
        itemBuilder: (context, index) {
          if (_isOwnProfile && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _openCreateList,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(
                    'New List',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            );
          }
          final doc = lists[index - (_isOwnProfile ? 1 : 0)];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ProfileListCard(
              listId: doc.id,
              list: doc.data(),
              showOptions: _isOwnProfile,
              onChanged: () {
                if (mounted) {
                  setState(() {
                    _listsFuture = _loadLists();
                  });
                }
              },
              onTap: () async {
                await Navigator.of(context, rootNavigator: true).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => _ListDetailScreen(
                      listId: doc.id,
                      initialData: doc.data(),
                    ),
                  ),
                );
                if (mounted) {
                  setState(() {
                    _listsFuture = _loadLists();
                  });
                }
              },
            ),
          );
        },
      );
    },
  );

  Future<void> _openEditProfile(Map<String, dynamic> user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditProfileSheet(
        initialHandle: user['handle'] as String? ?? '',
        initialAboutMe: user['aboutMe'] as String? ?? '',
        initialFavoriteGenres: user['favoriteGenres'] is List
            ? (user['favoriteGenres'] as List).whereType<String>().toList()
            : const <String>[],
        initialAvatarBytes: _decodeAvatar(user['photoBase64']),
        onSave:
            (handle, aboutMe, favoriteGenres, avatarBytes, photoChanged) async {
          final update = <String, dynamic>{
            'handle': handle,
            'aboutMe': aboutMe,
            'favoriteGenres': favoriteGenres,
          };
          if (photoChanged) {
            update['photoBase64'] = avatarBytes == null
                ? FieldValue.delete()
                : base64Encode(avatarBytes);
          }
          try {
            await _firestore
                .collection('users')
                .doc(_uid!)
                .set(update, SetOptions(merge: true));
            return true;
          } catch (error) {
            _showSnack('Could not update profile: $error');
            return false;
          }
        },
      ),
    );
  }

  Future<void> _openCreateList() async {
    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CreateListSheet(),
    );
    if (title == null || title.isEmpty) return;
    try {
      await _firestore.collection('lists').add({
        'userId': _uid,
        'title': title,
        'albumIds': <String>[],
        'coverUrls': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      _showSnack('Could not create list: $error');
      return;
    }
    if (mounted && _listsQuery != null) {
      setState(() {
        _listsFuture = _loadLists();
      });
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadLists() =>
      _listsQuery!.get().timeout(const Duration(seconds: 15));

  Future<QuerySnapshot<Map<String, dynamic>>> _loadForumPosts() =>
      _forumPostsQuery!.get().timeout(const Duration(seconds: 15));

  Widget _forumPostsTab() => FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
    future: _forumPostsFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load forum posts. ${snapshot.error}',
                  style: GoogleFonts.inter(color: _muted),
                  textAlign: TextAlign.center,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _forumPostsFuture = _loadForumPosts();
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator(color: _teal));
      }
      final posts = [...snapshot.data!.docs]
        ..sort((a, b) {
          final aTime = a.data()['createdAt'];
          final bTime = b.data()['createdAt'];
          if (aTime is! Timestamp) return bTime is! Timestamp ? 0 : 1;
          if (bTime is! Timestamp) return -1;
          return bTime.compareTo(aTime);
        });
      if (posts.isEmpty) return _emptyMessage('No forum posts yet.');
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: posts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final post = posts[index];
          return _ProfileForumCard(
            post: post.data(),
            onTap: () async {
              await context.push('/thread/${post.id}');
              if (mounted) {
                setState(() {
                  _forumPostsFuture = _loadForumPosts();
                });
              }
            },
          );
        },
      );
    },
  );

  Widget _signedOutView() => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sign in to view your profile.',
              style: GoogleFonts.inter(fontSize: 15, color: _ink),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Log In'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: _teal),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _logOut() async {
    try {
      await AuthService.signOut();
    } catch (error) {
      _showSnack('Could not log out: $error');
    }
  }

  Widget _errorView(String message) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    body: Center(
      child: Padding(padding: const EdgeInsets.all(24), child: Text(message)),
    ),
  );

  Widget _tabError(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, style: GoogleFonts.inter(color: _muted)),
    ),
  );

  Widget _emptyMessage(String message) => Center(
    child: Text(message, style: GoogleFonts.inter(fontSize: 13, color: _muted)),
  );

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedTabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(color: Colors.white, child: tabBar);

  @override
  bool shouldRebuild(covariant _PinnedTabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        '$value',
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: _ink,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _muted,
        ),
      ),
    ],
  );
}

class _ProfileReviewCard extends StatefulWidget {
  const _ProfileReviewCard({
    required this.reviewId,
    required this.review,
    required this.onChanged,
  });

  final String reviewId;
  final Map<String, dynamic> review;
  final VoidCallback onChanged;

  @override
  State<_ProfileReviewCard> createState() => _ProfileReviewCardState();
}

class _ProfileReviewCardState extends State<_ProfileReviewCard> {
  bool _expanded = false;

  Future<void> _openReview({bool openComposer = false}) =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReviewDetailScreen(
            reviewId: widget.reviewId,
            openComposer: openComposer,
          ),
        ),
      );

  Future<void> _toggleLike(bool currentlyLiked) async {
    final actor = FirebaseAuth.instance.currentUser;
    if (actor == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Log in to like reviews.')));
      return;
    }

    final nextLiked = !currentlyLiked;
    final reviewRef = FirebaseFirestore.instance
        .collection('reviews')
        .doc(widget.reviewId);
    try {
      var addedLike = false;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final reviewSnapshot = await transaction.get(reviewRef);
        if (!reviewSnapshot.exists) {
          throw StateError('This review is no longer available.');
        }
        final review = reviewSnapshot.data() ?? <String, dynamic>{};
        final likedBy = (review['likedBy'] as List? ?? [])
            .whereType<String>()
            .toSet();
        final wasLiked = likedBy.contains(actor.uid);
        if (wasLiked == nextLiked) return;

        final count = _number(review['likes']);
        transaction.update(reviewRef, {
          'likes': (count + (nextLiked ? 1 : -1)).clamp(0, 1 << 31),
          'likedBy': nextLiked
              ? FieldValue.arrayUnion([actor.uid])
              : FieldValue.arrayRemove([actor.uid]),
        });
        addedLike = nextLiked;
      });

      if (addedLike) {
        try {
          await _notifyReviewOwnerLike(actor);
        } catch (_) {}
      }
      widget.onChanged();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update like: $error')),
        );
      }
    }
  }

  Future<void> _notifyReviewOwnerLike(User actor) async {
    final ownerId = widget.review['userId'] as String?;
    if (ownerId == null || ownerId.isEmpty || ownerId == actor.uid) return;

    var actorName = actor.email?.split('@').first ?? 'Listener';
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(actor.uid)
          .get();
      actorName = profile.data()?['handle'] as String? ?? actorName;
    } catch (_) {}
    await FirebaseFirestore.instance
        .collection('users')
        .doc(ownerId)
        .collection('notifications')
        .add({
          'type': 'like',
          'actorId': actor.uid,
          'actorName': actorName,
          'reviewId': widget.reviewId,
          'albumId': widget.review['albumId'],
          'albumTitle': widget.review['albumTitle'] ?? 'your review',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final albumId = review['albumId'] as String? ?? '';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: albumId.isEmpty
          ? null
          : FirebaseFirestore.instance
                .collection('albums')
                .doc(albumId)
                .snapshots(),
      builder: (context, snapshot) {
        final album = snapshot.data?.data() ?? <String, dynamic>{};
        final coverUrl =
            (review['coverUrl'] as String?) ??
            (album['coverUrl'] as String?) ??
            '';
        final title =
            (review['albumTitle'] as String?) ??
            (album['title'] as String?) ??
            'Album';
        final artist =
            (review['albumArtist'] as String?) ??
            (album['artist'] as String?) ??
            '';
        final text = review['text'] as String? ?? '';
        final long = text.length > 160;
        final score = _number(review['score']);
        final comments = _number(review['comments']);
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: _openReview,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: albumId.isEmpty
                        ? null
                        : () => context.push('/album/$albumId'),
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        _Cover(url: coverUrl, size: 48, radius: 10),
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
                                artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: scorePalette(score),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$score',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (review['userId'] ==
                            FirebaseAuth.instance.currentUser?.uid)
                          PopupMenuButton<String>(
                            tooltip: 'Review options',
                            onSelected: (value) => value == 'edit'
                                ? _editReview(review)
                                : _deleteReview(review),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit review'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete review'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    !_expanded && long ? '${text.substring(0, 160)}…' : text,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: _ink.withValues(alpha: 0.7),
                    ),
                  ),
                  if (long)
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _expanded ? 'read less' : 'read more',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _teal,
                          ),
                        ),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: Color(0xFFE6E6E6)),
                  ),
                  Row(
                    children: [
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('reviews')
                            .doc(widget.reviewId)
                            .snapshots(),
                        builder: (context, likeSnapshot) {
                          final liveReview =
                              likeSnapshot.data?.data() ?? review;
                          final likedBy = liveReview['likedBy'];
                          final liked =
                              FirebaseAuth.instance.currentUser?.uid != null &&
                              likedBy is List &&
                              likedBy.contains(
                                FirebaseAuth.instance.currentUser!.uid,
                              );
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: liked
                                    ? 'Unlike review'
                                    : 'Like review',
                                onPressed: () => _toggleLike(liked),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 30,
                                  minHeight: 30,
                                ),
                                icon: Icon(
                                  liked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 18,
                                  color: liked ? _red : _muted,
                                ),
                              ),
                              Text(
                                '${_number(liveReview['likes'])}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: _muted,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Open review and comments',
                        onPressed: () => _openReview(openComposer: true),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                        icon: const Icon(
                          Icons.chat_bubble_outline,
                          size: 16,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$comments',
                        style: GoogleFonts.inter(fontSize: 11, color: _muted),
                      ),
                      const Spacer(),
                      Text(
                        _formatMonth(review['createdAt']),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: _ink.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editReview(Map<String, dynamic> review) async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _EditReviewDialog(
        initialText: review['text'] as String? ?? '',
        initialScore: _number(review['score']).clamp(0, 100).toInt(),
      ),
    );
    if (result == null) return;
    final db = FirebaseFirestore.instance;
    final reviewRef = db.collection('reviews').doc(widget.reviewId);
    final albumId = review['albumId'] as String? ?? '';
    try {
      await db.runTransaction((transaction) async {
        final currentReview = await transaction.get(reviewRef);
        if (!currentReview.exists ||
            currentReview.data()?['userId'] !=
                FirebaseAuth.instance.currentUser?.uid)
          return;
        final albumRef = albumId.isEmpty
            ? null
            : db.collection('albums').doc(albumId);
        final albumSnapshot = albumRef == null
            ? null
            : await transaction.get(albumRef);
        transaction.update(reviewRef, {
          'text': result.$2,
          'score': result.$1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (albumRef != null && albumSnapshot!.exists) {
          final data = albumSnapshot.data() ?? <String, dynamic>{};
          final count = _number(data['ratingCount']);
          final average = _number(data['communityScore']);
          if (count > 0) {
            final updatedAverage =
                (((average * count) -
                            _number(currentReview.data()?['score']) +
                            result.$1) /
                        count)
                    .round();
            transaction.update(albumRef, {'communityScore': updatedAverage});
          }
        }
      });
      widget.onChanged();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not edit review: $error')),
        );
    }
  }

  Future<void> _deleteReview(Map<String, dynamic> review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete review?'),
        content: const Text('This will permanently remove your review.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = FirebaseFirestore.instance;
    final reviewRef = db.collection('reviews').doc(widget.reviewId);
    final albumId = review['albumId'] as String? ?? '';
    try {
      await db.runTransaction((transaction) async {
        final reviewSnapshot = await transaction.get(reviewRef);
        if (!reviewSnapshot.exists ||
            reviewSnapshot.data()?['userId'] !=
                FirebaseAuth.instance.currentUser?.uid)
          return;
        final albumRef = albumId.isEmpty
            ? null
            : db.collection('albums').doc(albumId);
        final albumSnapshot = albumRef == null
            ? null
            : await transaction.get(albumRef);
        if (albumRef != null && albumSnapshot!.exists) {
          final data = albumSnapshot.data() ?? <String, dynamic>{};
          final count = _number(data['ratingCount']);
          final average = _number(data['communityScore']);
          final newCount = (count - 1).clamp(0, count);
          final newAverage = newCount == 0
              ? 0
              : (((average * count) -
                            _number(reviewSnapshot.data()?['score'])) /
                        newCount)
                    .round();
          transaction.update(albumRef, {
            'ratingCount': newCount,
            'communityScore': newAverage,
          });
        }
        transaction.delete(reviewRef);
      });
      widget.onChanged();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete review: $error')),
        );
    }
  }
}

class UserConnectionsScreen extends StatelessWidget {
  const UserConnectionsScreen({
    super.key,
    required this.userId,
    required this.relationship,
  });

  final String userId;
  final String relationship;

  String get _title => relationship == 'followers' ? 'Followers' : 'Following';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF5F5F5),
      foregroundColor: _ink,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        tooltip: 'Back to profile',
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(
        _title,
        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection(relationship)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load ${_title.toLowerCase()}.',
              style: GoogleFonts.inter(color: _muted),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _teal));
        }
        final people = snapshot.data!.docs;
        if (people.isEmpty) {
          return Center(
            child: Text(
              'No ${_title.toLowerCase()} yet.',
              style: GoogleFonts.inter(color: _muted),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: people.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) =>
              _PersonTile(userId: people[index].id),
        );
      },
    ),
  );
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.userId});

  final String userId;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots(),
    builder: (context, snapshot) {
      final profile = snapshot.data?.data() ?? <String, dynamic>{};
      final handle = _handle(
        profile['handle'] as String? ?? _legacyUsername(profile['displayName']),
      );
      final displayName = (profile['displayName'] as String? ?? '').trim();
      final avatar = _decodeAvatar(profile['photoBase64']);
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          onTap: () => context.push(profileRouteLocation(userId)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: CircleAvatar(
            backgroundColor: _navy,
            foregroundImage: avatar == null ? null : MemoryImage(avatar),
            child: avatar == null
                ? Text(
                    _initials(handle.replaceFirst('@', '')),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          title: Text(
            displayName.isEmpty ? handle.replaceFirst('@', '') : displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          subtitle: Text(
            handle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 12, color: _muted),
          ),
          trailing: _PersonFollowButton(userId: userId),
        ),
      );
    },
  );
}

class _PersonFollowButton extends StatefulWidget {
  const _PersonFollowButton({required this.userId});

  final String userId;

  @override
  State<_PersonFollowButton> createState() => _PersonFollowButtonState();
}

class _PersonFollowButtonState extends State<_PersonFollowButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final currentId = FirebaseAuth.instance.currentUser?.uid;
    if (currentId == null || currentId == widget.userId) {
      return const SizedBox.shrink();
    }
    final followingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentId)
        .collection('following')
        .doc(widget.userId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: followingRef.snapshots(),
      builder: (context, snapshot) {
        final following = snapshot.data?.exists ?? false;
        return SizedBox(
          width: 94,
          height: 34,
          child: following
              ? OutlinedButton(
                  onPressed: _busy ? null : () => _toggle(currentId),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal,
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: _teal),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Following'),
                )
              : FilledButton(
                  onPressed: _busy ? null : () => _toggle(currentId),
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Follow'),
                ),
        );
      },
    );
  }

  Future<void> _toggle(String currentId) async {
    setState(() => _busy = true);
    try {
      await _toggleFollowRelationship(currentId, widget.userId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update follow status: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialHandle,
    required this.initialAboutMe,
    required this.initialFavoriteGenres,
    required this.initialAvatarBytes,
    required this.onSave,
  });

  final String initialHandle;
  final String initialAboutMe;
  final List<String> initialFavoriteGenres;
  final Uint8List? initialAvatarBytes;
  final Future<bool> Function(
    String handle,
    String aboutMe,
    List<String> favoriteGenres,
    Uint8List? avatarBytes,
    bool photoChanged,
  )
  onSave;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _handleController;
  late final TextEditingController _aboutController;
  late final Set<String> _selectedGenres;
  final _picker = ImagePicker();
  late Uint8List? _avatarBytes = widget.initialAvatarBytes;
  var _photoChanged = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _handleController = TextEditingController(text: widget.initialHandle);
    _aboutController = TextEditingController(text: widget.initialAboutMe);
    _selectedGenres = widget.initialFavoriteGenres
        .where(_profileGenreOptions.contains)
        .take(5)
        .toSet();
  }

  @override
  void dispose() {
    _handleController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 600 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That photo is too large. Choose a smaller image.'),
          ),
        );
        return;
      }
      setState(() {
        _avatarBytes = bytes;
        _photoChanged = true;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not select photo: $error')));
    }
  }

  Future<void> _save() async {
    final handle = _handleController.text.trim().replaceFirst(
      RegExp(r'^@'),
      '',
    );
    if (!RegExp(r'^[a-z0-9_]{3,}$').hasMatch(handle)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use at least 3 lowercase letters, numbers, or underscores.',
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final saved = await widget.onSave(
      handle,
      _aboutController.text.trim(),
      _profileGenreOptions.where(_selectedGenres.contains).toList(),
      _avatarBytes,
      _photoChanged,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      24,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Edit Profile',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: _navy,
              foregroundImage: _avatarBytes == null
                  ? null
                  : MemoryImage(_avatarBytes!),
              child: _avatarBytes == null
                  ? Text(
                      _initials(
                        _handle(_handleController.text).replaceFirst('@', ''),
                      ),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            OutlinedButton.icon(
              onPressed: _saving ? null : _choosePhoto,
              icon: const Icon(Icons.photo_outlined),
              label: const Text('Change photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: BorderSide(color: _ink.withValues(alpha: 0.16)),
              ),
            ),
            if (_avatarBytes != null)
              IconButton(
                tooltip: 'Remove photo',
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _avatarBytes = null;
                        _photoChanged = true;
                      }),
                icon: const Icon(Icons.delete_outline),
                color: _muted,
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _handleController,
          enabled: !_saving,
          style: GoogleFonts.inter(fontSize: 14, color: _ink),
          decoration: InputDecoration(
            labelText: 'Username',
            labelStyle: GoogleFonts.inter(fontSize: 13, color: _muted),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _aboutController,
          enabled: !_saving,
          maxLines: 3,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          style: GoogleFonts.inter(fontSize: 14, color: _ink),
          decoration: InputDecoration(
            labelText: 'About Me',
            hintText: 'Tell people a little about yourself',
            labelStyle: GoogleFonts.inter(fontSize: 13, color: _muted),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            alignLabelWithHint: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                'Favorite Genres',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${_selectedGenres.length}/5',
              style: GoogleFonts.inter(fontSize: 11, color: _muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _profileGenreOptions.map((genre) {
            final selected = _selectedGenres.contains(genre);
            return FilterChip(
              label: Text(genre),
              selected: selected,
              showCheckmark: false,
              onSelected: _saving
                  ? null
                  : (value) {
                      if (value && _selectedGenres.length >= 5) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Choose up to 5 favorite genres.'),
                          ),
                        );
                        return;
                      }
                      setState(() {
                        if (value) {
                          _selectedGenres.add(genre);
                        } else {
                          _selectedGenres.remove(genre);
                        }
                      });
                    },
              labelStyle: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _ink,
              ),
              backgroundColor: const Color(0xFFF5F5F5),
              selectedColor: _teal,
              side: BorderSide(color: selected ? _teal : _ink, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
            ),
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Save',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    ),
  );
}

class _CreateListSheet extends StatefulWidget {
  const _CreateListSheet();

  @override
  State<_CreateListSheet> createState() => _CreateListSheetState();
}

class _CreateListSheetState extends State<_CreateListSheet> {
  final _titleController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a title for your list.');
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
    padding: EdgeInsets.fromLTRB(
      20,
      24,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create a List',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'List title',
              errorText: _error,
              labelStyle: GoogleFonts.inter(fontSize: 13, color: _muted),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Create',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfileForumCard extends StatelessWidget {
  const _ProfileForumCard({required this.post, required this.onTap});

  final Map<String, dynamic> post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = post['title'] as String? ?? 'Untitled discussion';
    final topic = post['topicTitle'] as String? ?? 'Discussion';
    final artist = post['artist'] as String? ?? '';
    final subtitle = artist.isEmpty ? topic : '$topic · $artist';
    final body = post['context'] as String? ?? '';
    final cover = post['coverUrl'] as String? ?? '';
    final replies = _number(post['replyCount']);
    final upvotes = _number(post['upvotes']);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Cover(url: cover, size: 48, radius: 10),
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
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0x40858585),
                  ),
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.4,
                    color: _ink.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Color(0xFFE6E6E6)),
              ),
              Row(
                children: [
                  Icon(Icons.chat_bubble_outline, size: 15, color: _muted),
                  const SizedBox(width: 5),
                  Text(
                    '$replies',
                    style: GoogleFonts.inter(fontSize: 11, color: _muted),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.arrow_upward_rounded, size: 15, color: _muted),
                  const SizedBox(width: 5),
                  Text(
                    '$upvotes',
                    style: GoogleFonts.inter(fontSize: 11, color: _muted),
                  ),
                  const Spacer(),
                  Text(
                    _formatMonth(post['createdAt']),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: _ink.withValues(alpha: 0.3),
                    ),
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

class _EditReviewDialog extends StatefulWidget {
  const _EditReviewDialog({
    required this.initialText,
    required this.initialScore,
  });

  final String initialText;
  final int initialScore;

  @override
  State<_EditReviewDialog> createState() => _EditReviewDialogState();
}

class _EditReviewDialogState extends State<_EditReviewDialog> {
  late final TextEditingController _textController;
  late int _score;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _score = widget.initialScore;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit review'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _textController,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Review'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Score'),
            Expanded(
              child: Slider(
                value: _score.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: _teal,
                label: '$_score',
                onChanged: (value) => setState(() => _score = value.round()),
              ),
            ),
            Text('$_score'),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () =>
            Navigator.pop(context, (_score, _textController.text.trim())),
        child: const Text('Save'),
      ),
    ],
  );
}

class _ProfileListCard extends StatelessWidget {
  const _ProfileListCard({
    required this.listId,
    required this.list,
    required this.onTap,
    required this.onChanged,
    required this.showOptions,
  });

  final String listId;
  final Map<String, dynamic> list;
  final VoidCallback onTap;
  final VoidCallback onChanged;
  final bool showOptions;

  @override
  Widget build(BuildContext context) {
    final title = list['title'] as String? ?? 'Untitled list';
    final albumIds = list['albumIds'] is List
        ? list['albumIds'] as List
        : const [];
    final coverUrls = list['coverUrls'] is List
        ? (list['coverUrls'] as List).whereType<String>().take(4).toList()
        : <String>[];
    final updated = _dateTime(list['updatedAt']);
    final updatedText = updated == null
        ? 'Updated recently'
        : 'Updated ${_formatMonth(updated)}';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
                  if (showOptions)
                    PopupMenuButton<String>(
                      tooltip: 'List options',
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      onSelected: (value) =>
                          value == 'edit' ? _rename(context) : _delete(context),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Rename list'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete list'),
                        ),
                      ],
                    ),
                ],
              ),
              Text(
                '${albumIds.length} albums · $updatedText',
                style: GoogleFonts.inter(fontSize: 12, color: _muted),
              ),
              if (coverUrls.isNotEmpty) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: 40,
                  width: 40 + ((coverUrls.length - 1) * 30),
                  child: Stack(
                    children: [
                      for (var index = 0; index < coverUrls.length; index++)
                        Positioned(
                          left: index * 30,
                          child: Container(
                            width: 40,
                            height: 40,
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.rectangle,
                            ),
                            child: _Cover(
                              url: coverUrls[index],
                              size: 36,
                              radius: 8,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(
      text: list['title'] as String? ?? '',
    );
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename list'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'List name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await FirebaseFirestore.instance.collection('lists').doc(listId).update({
      'title': title,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    onChanged();
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete list?'),
        content: const Text('This will permanently remove this list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance.collection('lists').doc(listId).delete();
      onChanged();
    }
  }
}

class _ListDetailScreen extends StatelessWidget {
  const _ListDetailScreen({required this.listId, required this.initialData});

  final String listId;
  final Map<String, dynamic> initialData;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('lists')
        .doc(listId)
        .snapshots(),
    builder: (context, snapshot) {
      final data = snapshot.data?.data() ?? initialData;
      final ids = (data['albumIds'] as List? ?? [])
          .whereType<String>()
          .toList();
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: Text(data['title'] as String? ?? 'Untitled list'),
          backgroundColor: const Color(0xFFF5F5F5),
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: 'Add album',
              onPressed: () => _openAlbumPicker(context, listId, ids),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: snapshot.hasError
            ? Center(child: Text('Could not load this list. ${snapshot.error}'))
            : ids.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.library_music_outlined,
                        size: 42,
                        color: _muted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'This list is empty',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Albums you add to this list will appear here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13, color: _muted),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _openAlbumPicker(context, listId, ids),
                        icon: const Icon(Icons.add),
                        label: const Text('Add an album'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
                future: Future.wait(
                  ids.map(
                    (id) => FirebaseFirestore.instance
                        .collection('albums')
                        .doc(id)
                        .get(),
                  ),
                ),
                builder: (context, albumsSnapshot) {
                  if (albumsSnapshot.hasError)
                    return const Center(
                      child: Text('Could not load albums in this list.'),
                    );
                  if (!albumsSnapshot.hasData)
                    return const Center(
                      child: CircularProgressIndicator(color: _teal),
                    );
                  final albums = albumsSnapshot.data!
                      .where((album) => album.exists)
                      .toList();
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: albums.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final album = albums[index].data() ?? <String, dynamic>{};
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onTap: () =>
                              context.push('/album/${albums[index].id}'),
                          leading: _Cover(
                            url: album['coverUrl'] as String? ?? '',
                            size: 48,
                            radius: 8,
                          ),
                          title: Text(
                            album['title'] as String? ?? 'Untitled album',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          subtitle: Text(
                            album['artist'] as String? ?? '',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _muted,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: _muted,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      );
    },
  );
}

Future<void> _openAlbumPicker(
  BuildContext context,
  String listId,
  List<String> existingIds,
) async {
  final albums =
      await showModalBottomSheet<
        List<QueryDocumentSnapshot<Map<String, dynamic>>>
      >(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AddAlbumPickerSheet(existingIds: existingIds),
      );
  if (albums == null || albums.isEmpty) return;
  final listRef = FirebaseFirestore.instance.collection('lists').doc(listId);
  try {
    final addedCount = await FirebaseFirestore.instance.runTransaction<int>((
      transaction,
    ) async {
      final snapshot = await transaction.get(listRef);
      if (!snapshot.exists) throw StateError('This list no longer exists.');
      final data = snapshot.data() ?? <String, dynamic>{};
      final ids = (data['albumIds'] as List? ?? [])
          .whereType<String>()
          .toList();
      final covers = (data['coverUrls'] as List? ?? [])
          .whereType<String>()
          .toList();
      var addedCount = 0;
      for (final album in albums) {
        if (ids.contains(album.id)) continue;
        ids.add(album.id);
        covers.add(album.data()['coverUrl'] as String? ?? '');
        addedCount++;
      }
      if (addedCount == 0) return 0;
      transaction.update(listRef, {
        'albumIds': ids,
        'coverUrls': covers,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return addedCount;
    });
    if (context.mounted && addedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added $addedCount ${addedCount == 1 ? 'album' : 'albums'} to your list.',
          ),
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not add album: $error')));
    }
  }
}

class _AddAlbumPickerSheet extends StatefulWidget {
  const _AddAlbumPickerSheet({required this.existingIds});

  final List<String> existingIds;

  @override
  State<_AddAlbumPickerSheet> createState() => _AddAlbumPickerSheetState();
}

class _AddAlbumPickerSheetState extends State<_AddAlbumPickerSheet> {
  final _searchController = TextEditingController();
  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
  _selectedAlbums = {};
  late final Future<QuerySnapshot<Map<String, dynamic>>> _albumsFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _albumsFuture = FirebaseFirestore.instance.collection('albums').get();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.8,
    maxChildSize: 0.95,
    builder: (context, scrollController) => Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add albums',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search albums or artists',
                    prefixIcon: const Icon(Icons.search_rounded, color: _teal),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: _albumsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return const Center(child: Text('Could not load albums.'));
                if (!snapshot.hasData)
                  return const Center(
                    child: CircularProgressIndicator(color: _teal),
                  );
                final albums = snapshot.data!.docs.where((album) {
                  final data = album.data();
                  final title = (data['title'] as String? ?? '').toLowerCase();
                  final artist = (data['artist'] as String? ?? '')
                      .toLowerCase();
                  return title.contains(_query) || artist.contains(_query);
                }).toList();
                if (albums.isEmpty)
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No albums available.'
                          : 'No matching albums.',
                      style: GoogleFonts.inter(color: _muted),
                    ),
                  );
                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: albums.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    final data = album.data();
                    final alreadyAdded = widget.existingIds.contains(album.id);
                    final selected = _selectedAlbums.containsKey(album.id);
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: _Cover(
                          url: data['coverUrl'] as String? ?? '',
                          size: 48,
                          radius: 8,
                        ),
                        title: Text(
                          data['title'] as String? ?? 'Untitled album',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        subtitle: Text(
                          data['artist'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, color: _muted),
                        ),
                        trailing: Icon(
                          alreadyAdded
                              ? Icons.check_circle
                              : selected
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                          color: alreadyAdded || selected ? _teal : _muted,
                        ),
                        onTap: alreadyAdded
                            ? null
                            : () => setState(() {
                                if (selected) {
                                  _selectedAlbums.remove(album.id);
                                } else {
                                  _selectedAlbums[album.id] = album;
                                }
                              }),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _selectedAlbums.isEmpty
                      ? null
                      : () =>
                            Navigator.of(context)
                                .pop(_selectedAlbums.values.toList()),
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Add ${_selectedAlbums.length} albums'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.size, required this.radius});

  final String url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: size,
      height: size,
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

int _number(Object? value) => value is num ? value.toInt() : 0;

String _compactCount(int count) {
  if (count < 1000) return '$count';
  final thousands = count / 1000;
  if (count < 1000000) {
    final value = thousands >= 100
        ? thousands.toStringAsFixed(0)
        : thousands.toStringAsFixed(1);
    return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}K';
  }
  final millions = count / 1000000;
  final value = millions >= 100
      ? millions.toStringAsFixed(0)
      : millions.toStringAsFixed(1);
  return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}M';
}

Future<void> _toggleFollowRelationship(String followerId, String targetId) async {
  final firestore = FirebaseFirestore.instance;
  final followerProfile = await firestore
      .collection('users')
      .doc(followerId)
      .get();
  final profileData = followerProfile.data() ?? <String, dynamic>{};
  final followingRef = firestore
      .collection('users')
      .doc(followerId)
      .collection('following')
      .doc(targetId);
  final followerRef = firestore
      .collection('users')
      .doc(targetId)
      .collection('followers')
      .doc(followerId);
  final notificationRef = firestore
      .collection('users')
      .doc(targetId)
      .collection('notifications')
      .doc();
  await firestore.runTransaction((transaction) async {
    final existing = await transaction.get(followingRef);
    if (existing.exists) {
      transaction.delete(followingRef);
      transaction.delete(followerRef);
      return;
    }
    final data = {
      'userId': followerId,
      'createdAt': FieldValue.serverTimestamp(),
    };
    transaction.set(followingRef, data);
    transaction.set(followerRef, data);
    transaction.set(notificationRef, {
      'type': 'follow',
      'actorId': followerId,
      'actorName':
          profileData['handle'] as String? ??
          profileData['displayName'] as String? ??
          'Someone',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  });
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  return parts
      .take(2)
      .map((part) => part.characters.first.toUpperCase())
      .join();
}

String _handle(String handle) => handle.startsWith('@') ? handle : '@$handle';

String _legacyUsername(Object? value) {
  final username = (value as String? ?? 'listener').toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9_]'),
    '',
  );
  return username.length >= 3 ? username : 'listener';
}

DateTime? _dateTime(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

Uint8List? _decodeAvatar(Object? value) {
  if (value is! String || value.isEmpty) return null;
  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}

String _formatMonth(Object? value) {
  final date = _dateTime(value);
  if (date == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.year}';
}
