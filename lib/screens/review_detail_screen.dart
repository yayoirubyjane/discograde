import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'profile_screen.dart';
import '../utils/score_color.dart';

class ReviewDetailScreen extends StatefulWidget {
  const ReviewDetailScreen({
    super.key,
    required this.reviewId,
    this.openComposer = false,
  });

  final String reviewId;
  final bool openComposer;

  @override
  State<ReviewDetailScreen> createState() => _ReviewDetailScreenState();
}

class _ReviewDetailScreenState extends State<ReviewDetailScreen> {
  static const _teal = Color(0xFF0E8A8A);
  static const _ink = Color(0xFF3F3F3F);
  final _commentController = TextEditingController();
  late Future<DocumentSnapshot<Map<String, dynamic>>> _reviewFuture;
  late final CollectionReference<Map<String, dynamic>> _commentsCollection;
  late Future<QuerySnapshot<Map<String, dynamic>>> _commentsFuture;
  bool _posting = false;
  late bool _composerVisible = widget.openComposer;

  void _openProfile(String? userId) {
    if (userId == null || userId.isEmpty) return;
    context.push(profileRouteLocation(userId));
  }

  @override
  void initState() {
    super.initState();
    _reviewFuture = _loadReview();
    _commentsCollection = FirebaseFirestore.instance
        .collection('reviews')
        .doc(widget.reviewId)
        .collection('comments');
    _commentsFuture = _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _postComment(Map<String, dynamic> review) async {
    final user = FirebaseAuth.instance.currentUser;
    final text = _commentController.text.trim();
    if (user == null || text.isEmpty || _posting) return;
    setState(() => _posting = true);
    final firestore = FirebaseFirestore.instance;
    final reviewRef = firestore.collection('reviews').doc(widget.reviewId);
    try {
      var username = user.email?.split('@').first ?? 'Listener';
      try {
        final profile = await firestore.collection('users').doc(user.uid).get();
        username = profile.data()?['handle'] as String? ?? username;
      } catch (_) {}
      final batch = firestore.batch();
      batch.set(reviewRef.collection('comments').doc(), {
        'userId': user.uid,
        'username': username,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(reviewRef, {'comments': FieldValue.increment(1)});
      await batch.commit();

      final ownerId = review['userId'] as String?;
      if (ownerId != null && ownerId.isNotEmpty && ownerId != user.uid) {
        try {
          await firestore
              .collection('users')
              .doc(ownerId)
              .collection('notifications')
              .add({
                'type': 'comment',
                'actorId': user.uid,
                'actorName': username,
                'reviewId': widget.reviewId,
                'albumId': review['albumId'],
                'albumTitle': review['albumTitle'] ?? 'your review',
                'commentText': text,
                'read': false,
                'createdAt': FieldValue.serverTimestamp(),
              });
        } catch (_) {}
      }
      _commentController.clear();
      if (mounted) setState(() => _commentsFuture = _loadComments());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post comment: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadReview() =>
      FirebaseFirestore.instance
          .collection('reviews')
          .doc(widget.reviewId)
          .get()
          .timeout(const Duration(seconds: 15));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    appBar: AppBar(
      title: const Text('Review details'),
      backgroundColor: const Color(0xFFF5F5F5),
      foregroundColor: _ink,
      surfaceTintColor: Colors.transparent,
      actions: [_ownerActions()],
    ),
    body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _reviewFuture,
      builder: (context, reviewSnapshot) {
        if (reviewSnapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load this review: ${reviewSnapshot.error}',
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _reviewFuture = _loadReview()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!reviewSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _teal));
        }
        if (!reviewSnapshot.data!.exists) {
          return const Center(
            child: Text('This review is no longer available.'),
          );
        }
        final review = reviewSnapshot.data!.data()!;
        return FutureBuilder<
          (List<(Map<String, dynamic>, int?)>, Map<String, dynamic>)
        >(
          future: _rankedTracks(review),
          builder: (context, tracksSnapshot) => ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        InkWell(
                          onTap: () =>
                              _openProfile(review['userId'] as String?),
                          customBorder: const CircleBorder(),
                          child: _avatar(review['userId'] as String?),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () =>
                                    _openProfile(review['userId'] as String?),
                                child: Text(
                                  review['username'] as String? ?? 'Listener',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                _dateLabel(review['createdAt']),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        _scoreBadge(_toInt(review['score']) ?? 0),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: Color(0xFFE6E6E6)),
                    ),
                    Text(
                      review['text'] as String? ?? '',
                      style: GoogleFonts.inter(fontSize: 15, height: 1.5),
                    ),
                  ],
                ),
              ),
              _liveLikesCard(review),
              if (tracksSnapshot.hasData) ...[
                if (tracksSnapshot.data!.$1.isNotEmpty) ...[
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Track Ranking',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (
                          var i = 0;
                          i < tracksSnapshot.data!.$1.length;
                          i++
                        ) ...[
                          if (i > 0)
                            const Divider(height: 1, color: Color(0xFFE7E7E7)),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${i + 1}.',
                                    style: GoogleFonts.inter(
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    tracksSnapshot.data!.$1[i].$1['title']
                                            as String? ??
                                        'Untitled track',
                                  ),
                                ),
                                _scoreBadge(
                                  tracksSnapshot.data!.$1[i].$2,
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  ),
                ],
              ],
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Comments',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    if (_composerVisible) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 500,
                              decoration: const InputDecoration(
                                hintText: 'Write a comment…',
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Post comment',
                            onPressed: _posting
                                ? null
                                : () => _postComment(review),
                            icon: _posting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded, color: _teal),
                          ),
                        ],
                      ),
                    ] else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _composerVisible = true),
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.add_comment_outlined),
                          label: const Text('Write a comment'),
                        ),
                      ),
                    FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      future: _commentsFuture,
                      builder: (context, commentsSnapshot) {
                        if (commentsSnapshot.hasError) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Could not load comments: ${commentsSnapshot.error}',
                              ),
                              TextButton.icon(
                                onPressed: () => setState(
                                  () => _commentsFuture = _loadComments(),
                                ),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          );
                        }
                        if (!commentsSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(color: _teal),
                          );
                        }
                        final comments = [...commentsSnapshot.data!.docs]
                          ..sort((a, b) {
                            final aTime = a.data()['createdAt'];
                            final bTime = b.data()['createdAt'];
                            if (aTime is! Timestamp || bTime is! Timestamp)
                              return 0;
                            return bTime.compareTo(aTime);
                          });
                        if (comments.isEmpty)
                          return const Text('No comments yet.');
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var index = 0;
                              index < comments.length;
                              index++
                            ) ...[
                              if (index > 0)
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFE7E7E7),
                                ),
                              Builder(
                                builder: (context) {
                                  final data = comments[index].data();
                                  final stamp = data['createdAt'];
                                  final date = stamp is Timestamp
                                      ? stamp.toDate().toLocal()
                                      : null;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        InkWell(
                                          onTap: () => _openProfile(
                                            data['userId'] as String?,
                                          ),
                                          customBorder: const CircleBorder(),
                                          child: _avatar(
                                            data['userId'] as String?,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              InkWell(
                                                onTap: () => _openProfile(
                                                  data['userId'] as String?,
                                                ),
                                                child: Text(
                                                  data['username'] as String? ??
                                                      'Listener',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: _ink,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                data['text'] as String? ?? '',
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  height: 1.4,
                                                  color: _ink,
                                                ),
                                              ),
                                              if (date != null) ...[
                                                const SizedBox(height: 3),
                                                Text(
                                                  '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _ownerActions() =>
      FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _reviewFuture,
        builder: (context, snapshot) {
          final review = snapshot.data?.data();
          final userId = FirebaseAuth.instance.currentUser?.uid;
          if (review == null || review['userId'] != userId) {
            return const SizedBox.shrink();
          }
          return PopupMenuButton<String>(
            tooltip: 'Review options',
            onSelected: (value) =>
                value == 'edit' ? _editReview(review) : _deleteReview(review),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit review')),
              PopupMenuItem(value: 'delete', child: Text('Delete review')),
            ],
          );
        },
      );

  Future<void> _editReview(Map<String, dynamic> review) async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _ReviewEditDialog(
        initialText: review['text'] as String? ?? '',
        initialScore: (_toInt(review['score']) ?? 0).clamp(0, 100).toInt(),
      ),
    );
    if (result == null) return;
    final firestore = FirebaseFirestore.instance;
    final reviewRef = firestore.collection('reviews').doc(widget.reviewId);
    final albumId = review['albumId'] as String? ?? '';
    try {
      await firestore.runTransaction((transaction) async {
        final reviewSnapshot = await transaction.get(reviewRef);
        if (!reviewSnapshot.exists ||
            reviewSnapshot.data()?['userId'] !=
                FirebaseAuth.instance.currentUser?.uid) {
          return;
        }
        final albumRef = albumId.isEmpty
            ? null
            : firestore.collection('albums').doc(albumId);
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
          final count = _toInt(data['ratingCount']) ?? 0;
          final average = _toInt(data['communityScore']) ?? 0;
          if (count > 0) {
            final updatedAverage =
                ((average * count -
                            (_toInt(reviewSnapshot.data()?['score']) ?? 0) +
                            result.$1) /
                        count)
                    .round();
            transaction.update(albumRef, {'communityScore': updatedAverage});
          }
        }
      });
      if (mounted) {
        setState(() {
          _reviewFuture = _loadReview();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not edit review: $error')),
        );
      }
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
    final firestore = FirebaseFirestore.instance;
    final reviewRef = firestore.collection('reviews').doc(widget.reviewId);
    final albumId = review['albumId'] as String? ?? '';
    try {
      await firestore.runTransaction((transaction) async {
        final reviewSnapshot = await transaction.get(reviewRef);
        if (!reviewSnapshot.exists ||
            reviewSnapshot.data()?['userId'] !=
                FirebaseAuth.instance.currentUser?.uid) {
          return;
        }
        final albumRef = albumId.isEmpty
            ? null
            : firestore.collection('albums').doc(albumId);
        final albumSnapshot = albumRef == null
            ? null
            : await transaction.get(albumRef);
        if (albumRef != null && albumSnapshot!.exists) {
          final data = albumSnapshot.data() ?? <String, dynamic>{};
          final count = _toInt(data['ratingCount']) ?? 0;
          final average = _toInt(data['communityScore']) ?? 0;
          final newCount = (count - 1).clamp(0, count);
          final newAverage = newCount == 0
              ? 0
              : ((average * count -
                            (_toInt(reviewSnapshot.data()?['score']) ?? 0)) /
                        newCount)
                    .round();
          transaction.update(albumRef, {
            'ratingCount': newCount,
            'communityScore': newAverage,
          });
        }
        transaction.delete(reviewRef);
      });
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete review: $error')),
        );
      }
    }
  }

  Widget _card(
    Widget child, {
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(20, 16, 20, 0),
  }) => Container(
    margin: margin,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _liveLikesCard(Map<String, dynamic> review) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('reviews')
            .doc(widget.reviewId)
            .snapshots(),
        builder: (context, snapshot) {
          final liveReview = snapshot.data?.data() ?? review;
          final likedBy = (liveReview['likedBy'] as List? ?? [])
              .whereType<String>()
              .toList();
          final storedLikeCount = _toInt(liveReview['likes']) ?? 0;
          final likeCount = storedLikeCount > likedBy.length
              ? storedLikeCount
              : likedBy.length;
          return _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.favorite,
                      color: Color(0xFFBA011A),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Likes ($likeCount)',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                if (likedBy.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      likeCount == 0
                          ? 'No likes yet.'
                          : 'Liker details are unavailable for older likes.',
                      style: GoogleFonts.inter(color: Colors.grey[600]),
                    ),
                  )
                else ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: likedBy.map(_likedUserChip).toList(),
                  ),
                ],
              ],
            ),
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          );
        },
      );

  Future<QuerySnapshot<Map<String, dynamic>>> _loadComments() =>
      _commentsCollection.get().timeout(const Duration(seconds: 15));

  Future<(List<(Map<String, dynamic>, int?)>, Map<String, dynamic>)>
  _rankedTracks(Map<String, dynamic> review) async {
    final albumId = review['albumId'] as String?;
    if (albumId == null || albumId.isEmpty) {
      return (<(Map<String, dynamic>, int?)>[], <String, dynamic>{});
    }
    final firestore = FirebaseFirestore.instance;
    try {
      final album = await firestore.collection('albums').doc(albumId).get();
      final rawTracks = album.data()?['trackList'];
      if (rawTracks is! List) {
        return (
          <(Map<String, dynamic>, int?)>[],
          album.data() ?? <String, dynamic>{},
        );
      }
      final tracks = rawTracks
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final ratings = review['trackRatings'] is Map
          ? Map<String, dynamic>.from(review['trackRatings'] as Map)
          : <String, dynamic>{};
      if (ratings.isEmpty) {
        final ownerId = review['userId'] as String?;
        if (ownerId != null && ownerId.isNotEmpty && ownerId != 'guest') {
          final saved = await firestore
              .collection('users')
              .doc(ownerId)
              .collection('trackRatings')
              .doc(albumId)
              .get();
          final values = saved.data()?['ratings'];
          if (values is Map) ratings.addAll(Map<String, dynamic>.from(values));
        }
      }
      final ranked = <(Map<String, dynamic>, int?)>[];
      for (var index = 0; index < tracks.length; index++) {
        final track = tracks[index];
        final key = '${_toInt(track['number']) ?? index + 1}';
        final value = _toInt(ratings[key]);
        ranked.add((track, value));
      }
      ranked.sort((a, b) {
        if (a.$2 == null && b.$2 == null) return 0;
        if (a.$2 == null) return 1;
        if (b.$2 == null) return -1;
        return b.$2!.compareTo(a.$2!);
      });
      return (ranked, album.data() ?? <String, dynamic>{});
    } catch (_) {
      return (<(Map<String, dynamic>, int?)>[], <String, dynamic>{});
    }
  }

  Widget _avatar(String? userId) {
    if (userId == null || userId.isEmpty) return _fallbackAvatar();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final encoded = profile?['photoBase64'] as String?;
        final url = profile?['photoUrl'] as String?;
        ImageProvider? image;
        if (encoded != null && encoded.isNotEmpty) {
          try {
            image = MemoryImage(base64Decode(encoded));
          } catch (_) {}
        }
        image ??= url == null || url.isEmpty ? null : NetworkImage(url);
        if (image == null) return _fallbackAvatar();
        return CircleAvatar(radius: 18, backgroundImage: image);
      },
    );
  }

  Widget _likedUserChip(String userId) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .snapshots(),
        builder: (context, snapshot) {
          final profile = snapshot.data?.data() ?? <String, dynamic>{};
          final name =
              profile['handle'] as String? ??
              profile['displayName'] as String? ??
              'Listener';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatar(userId),
                const SizedBox(width: 6),
                Text(name, style: GoogleFonts.inter(fontSize: 12, color: _ink)),
              ],
            ),
          );
        },
      );

  Widget _fallbackAvatar() => const CircleAvatar(
    radius: 18,
    backgroundColor: _ink,
    child: Icon(Icons.person, color: Colors.white, size: 19),
  );

  Widget _scoreBadge(int? score, {bool compact = false}) => Container(
    constraints: BoxConstraints(minWidth: compact ? 38 : 40),
    alignment: Alignment.center,
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 8 : 10,
      vertical: compact ? 6 : 5,
    ),
    decoration: BoxDecoration(
      color: score == null ? const Color(0xFFF0F0F0) : scorePalette(score),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      score?.toString() ?? 'N/A',
      style: GoogleFonts.inter(
        fontSize: compact ? 11 : 12,
        fontWeight: FontWeight.w700,
        color: score == null ? Colors.grey[600] : Colors.white,
      ),
    ),
  );

  String _dateLabel(Object? value) {
    if (value is! Timestamp) return 'Date unavailable';
    final date = value.toDate().toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  int? _toInt(Object? value) => value is num ? value.round() : null;
}

class _ReviewEditDialog extends StatefulWidget {
  const _ReviewEditDialog({
    required this.initialText,
    required this.initialScore,
  });

  final String initialText;
  final int initialScore;

  @override
  State<_ReviewEditDialog> createState() => _ReviewEditDialogState();
}

class _ReviewEditDialogState extends State<_ReviewEditDialog> {
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
                activeColor: const Color(0xFF0E8A8A),
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
