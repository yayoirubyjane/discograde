import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../utils/score_color.dart';

const _ink = Color(0xFF3F3F3F);
const _muted = Color(0xFF858585);
const _teal = Color(0xFF0E8A8A);
const _placeholder = Color(0xFFE0E0E0);
const _red = Color(0xFFBA011A);
const _navy = Color(0xFF0B4B8B);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final String? _uid;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>? _reviewsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>? _listsStream;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid case final uid?) {
      _userStream = _firestore.collection('users').doc(uid).snapshots();
      _reviewsStream = _firestore
          .collection('reviews')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots();
      _listsStream = _firestore
          .collection('lists')
          .where('userId', isEqualTo: uid)
          .orderBy('updatedAt', descending: true)
          .snapshots();
    } else {
      _userStream = null;
      _reviewsStream = null;
      _listsStream = null;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) return _signedOutView();
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
        final user = snapshot.data!.data() ?? <String, dynamic>{};
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(child: _profileHeader(user)),
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
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [_reviewsTab(), _listsTab()],
            ),
          ),
        );
      },
    );
  }

  Widget _profileHeader(Map<String, dynamic> user) {
    final handle = _handle(
      user['handle'] as String? ?? _legacyUsername(user['displayName']),
    );
    final ratings = _number(user['ratingCount']);
    final reviews = _number(user['reviewCount']);
    final lists = _number(user['listCount']);
    final avatarBytes = _decodeAvatar(user['photoBase64']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 18),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Log out',
              onPressed: _logOut,
              icon: const Icon(Icons.logout_rounded, color: _teal),
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
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () => _openEditProfile(user),
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _ink),
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
          ),
        ],
      ),
    );
  }

  Widget _reviewsTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _reviewsStream,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return _tabError('Could not load reviews. ${snapshot.error}');
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator(color: _teal));
      final reviews = snapshot.data!.docs;
      if (reviews.isEmpty) return _emptyMessage('No reviews yet.');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: reviews.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ProfileReviewCard(review: reviews[index].data()),
        ),
      );
    },
  );

  Widget _listsTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _listsStream,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return _tabError('Could not load lists. ${snapshot.error}');
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator(color: _teal));
      final lists = snapshot.data!.docs;
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: lists.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
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
          final doc = lists[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProfileListCard(list: doc.data()),
          );
        },
      );
    },
  );

  Future<void> _openEditProfile(Map<String, dynamic> user) async {
    final handleController = TextEditingController(
      text: user['handle'] as String? ?? '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
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
            _formField(handleController, 'Username'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final handle = handleController.text.trim().replaceFirst(
                    RegExp(r'^@'),
                    '',
                  );
                  if (!RegExp(r'^[a-z0-9_]{3,}$').hasMatch(handle)) {
                    _showSnack('Use at least 3 lowercase letters, numbers, or underscores.');
                    return;
                  }
                  try {
                    await _firestore.collection('users').doc(_uid!).set({
                      'handle': handle,
                    }, SetOptions(merge: true));
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  } catch (error) {
                    _showSnack('Could not update profile: $error');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  'Save',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    handleController.dispose();
  }

  Future<void> _openCreateList() async {
    final titleController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
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
            _formField(titleController, 'List title'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final title = titleController.text.trim();
                  if (title.isEmpty) {
                    _showSnack('Enter a title for your list.');
                    return;
                  }
                  try {
                    await _firestore.collection('lists').add({
                      'userId': _uid,
                      'title': title,
                      'albumIds': <String>[],
                      'coverUrls': <String>[],
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  } catch (error) {
                    _showSnack('Could not create list: $error');
                  }
                },
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
    titleController.dispose();
  }

  Widget _formField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        style: GoogleFonts.inter(fontSize: 14, color: _ink),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 13, color: _muted),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
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
  const _ProfileReviewCard({required this.review});

  final Map<String, dynamic> review;

  @override
  State<_ProfileReviewCard> createState() => _ProfileReviewCardState();
}

class _ProfileReviewCardState extends State<_ProfileReviewCard> {
  bool _expanded = false;
  bool _liked = false;

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
        final likes = _number(review['likes']) + (_liked ? 1 : 0);
        final comments = _number(review['comments']);
        return Container(
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
                          style: GoogleFonts.inter(fontSize: 12, color: _muted),
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
                ],
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
                  IconButton(
                    onPressed: () => setState(() => _liked = !_liked),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: Icon(
                      _liked ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: _liked ? _red : _muted,
                    ),
                  ),
                  Text(
                    '$likes',
                    style: GoogleFonts.inter(fontSize: 11, color: _muted),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: _muted,
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
        );
      },
    );
  }
}

class _ProfileListCard extends StatelessWidget {
  const _ProfileListCard({required this.list});

  final Map<String, dynamic> list;

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
    return Container(
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
              const Icon(Icons.chevron_right_rounded, color: Color(0x40858585)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${albumIds.length} albums · $updatedText',
            style: GoogleFonts.inter(fontSize: 12, color: _muted),
          ),
          if (coverUrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 44,
              width: 44 + ((coverUrls.length - 1) * 34),
              child: Stack(
                children: [
                  for (var index = 0; index < coverUrls.length; index++)
                    Positioned(
                      left: index * 34,
                      child: Container(
                        width: 44,
                        height: 44,
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.rectangle,
                        ),
                        child: _Cover(
                          url: coverUrls[index],
                          size: 40,
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
    );
  }
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
  final username = (value as String? ?? 'listener')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');
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
