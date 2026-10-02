import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _ink = Color(0xFF3F3F3F);
const _muted = Color(0xFF858585);
const _teal = Color(0xFF0E8A8A);
const _placeholder = Color(0xFFE0E0E0);

class ThreadDetailScreen extends StatefulWidget {
  const ThreadDetailScreen({super.key, required this.threadId});

  final String threadId;

  @override
  State<ThreadDetailScreen> createState() => _ThreadDetailScreenState();
}

class _ThreadDetailScreenState extends State<ThreadDetailScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _votedIds = <String>{};
  bool _threadVoted = false;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _threadStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _commentsStream;
  String? _replyToCommentId;
  String? _replyToUsername;
  bool _posting = false;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get _threadRef =>
      _firestore.collection('threads').doc(widget.threadId);

  @override
  void initState() {
    super.initState();
    _threadStream = _threadRef.snapshots();
    _commentsStream = _firestore
        .collection('comments')
        .where('threadId', isEqualTo: widget.threadId)
        .snapshots();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController
      ..removeListener(_onTextChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _threadStream,
        builder: (context, threadSnapshot) {
          if (threadSnapshot.hasError) {
            return _messageScaffold('Could not load this discussion. ${threadSnapshot.error}');
          }
          if (!threadSnapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator(color: _teal)));
          }
          final thread = threadSnapshot.data!.data();
          if (thread == null) return _messageScaffold('This discussion could not be found.');

          return Scaffold(
            backgroundColor: const Color(0xFFF5F5F5),
            resizeToAvoidBottomInset: false,
            appBar: _threadAppBar(thread),
            body: Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _commentsStream,
                    builder: (context, commentsSnapshot) {
                if (commentsSnapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load comments. ${commentsSnapshot.error}',
                        style: GoogleFonts.inter(fontSize: 13, color: _muted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!commentsSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: _teal));
                }
                final comments = [...commentsSnapshot.data!.docs]..sort((a, b) {
                  final aTime = a.data()['createdAt'];
                  final bTime = b.data()['createdAt'];
                  if (aTime is! Timestamp) {
                    return bTime is! Timestamp ? 0 : 1;
                  }
                  if (bTime is! Timestamp) return -1;
                  return aTime.compareTo(bTime);
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: comments.isEmpty ? 3 : comments.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _originalPostCard(thread),
                      );
                    }
                    if (index == 1) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'REPLIES',
                          style: GoogleFonts.inter(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      );
                    }
                    if (comments.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'No replies yet. Start the conversation.',
                          style: GoogleFonts.inter(fontSize: 13, color: _muted),
                        ),
                      );
                    }
                    final comment = comments[index - 2];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CommentCard(
                        key: ValueKey(comment.id),
                        commentId: comment.id,
                        comment: comment.data(),
                        voted: _votedIds.contains(comment.id),
                        replyVoted: (replyIndex) => _votedIds.contains('${comment.id}:$replyIndex'),
                        onVote: () => _toggleCommentVote(comment.id),
                        onReplyVote: (replyIndex) => _toggleReplyVote(comment.id, replyIndex),
                        onReply: () => _beginReply(comment.id, comment.data()),
                      ),
                    );
                  },
                );
                    },
                  ),
                ),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: _commentComposer(),
                ),
              ],
            ),
          );
        },
      );

  Widget _originalPostCard(Map<String, dynamic> thread) {
    final username = thread['username'] as String? ?? 'listener';
    final upvotes = _number(thread['upvotes']) + (_threadVoted ? 1 : 0);
    final replyCount = _number(thread['replyCount']);
    final title = thread['title'] as String? ?? 'Discussion';
    final contextText = thread['context'] as String? ?? '';
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
              _UserAvatar(
                userId: thread['userId'] as String? ?? '',
                name: username,
                photoBase64: thread['authorPhotoBase64'] as String?,
                photoUrl: thread['authorPhotoUrl'] as String?,
                radius: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username.startsWith('@') ? username : '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    Text(
                      _timestamp(thread['createdAt']),
                      style: GoogleFonts.inter(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
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
            contextText,
            style: GoogleFonts.inter(
              color: _ink,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: _threadVoted ? 'Remove upvote' : 'Upvote discussion',
                onPressed: _toggleThreadVote,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  color: _threadVoted ? _teal : _muted,
                  size: 20,
                ),
              ),
              Text('$upvotes', style: GoogleFonts.inter(fontSize: 12, color: _muted)),
              const SizedBox(width: 18),
              const Icon(Icons.chat_bubble_outline, size: 17, color: _muted),
              const SizedBox(width: 6),
              Text(
                '$replyCount ${replyCount == 1 ? 'reply' : 'replies'}',
                style: GoogleFonts.inter(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleThreadVote() async {
    final increment = _threadVoted ? -1 : 1;
    setState(() => _threadVoted = !_threadVoted);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(_threadRef);
        if (!snapshot.exists) throw StateError('Discussion is no longer available.');
        final upvotes = _number(snapshot.data()?['upvotes']);
        transaction.update(_threadRef, {'upvotes': (upvotes + increment).clamp(0, 1 << 31)});
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _threadVoted = !_threadVoted);
      _showVoteError(error);
    }
  }

  AppBar _threadAppBar(Map<String, dynamic> thread) {
    final coverUrl = thread['coverUrl'] as String? ?? '';
    final topicTitle = thread['topicTitle'] as String? ?? 'Discussion';
    final subtitle = thread['isArtist'] == true
        ? 'Artist'
        : thread['artist'] as String? ?? '';
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 40,
              height: 40,
              child: coverUrl.isEmpty
                  ? const ColoredBox(color: _placeholder)
                  : CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const ColoredBox(color: _placeholder),
                      errorWidget: (_, _, _) => const ColoredBox(color: _placeholder),
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
                  topicTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
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
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _commentComposer() {
    final canPost = _textController.text.trim().isNotEmpty && !_posting;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0x143F3F3F))),
        ),
        child: Row(
          children: [
            _UserAvatar(
              userId: FirebaseAuth.instance.currentUser?.uid ?? '',
              name: FirebaseAuth.instance.currentUser?.email?.split('@').first ?? 'listener',
              photoUrl: FirebaseAuth.instance.currentUser?.photoURL,
              radius: 16,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.inter(fontSize: 13, color: _ink),
                decoration: InputDecoration(
                  hintText: _replyToUsername == null ? 'Add a comment…' : 'Reply to $_replyToUsername…',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: _muted),
                  filled: true,
                  fillColor: const Color(0xFFF2F2F2),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: canPost ? _post : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                disabledBackgroundColor: _teal.withValues(alpha: 0.45),
                disabledForegroundColor: Colors.white,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _posting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Post', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _post() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    final user = FirebaseAuth.instance.currentUser;
    var username = user?.email?.split('@').first ?? 'listener';
    if (user != null) {
      try {
        final profile = await _firestore.collection('users').doc(user.uid).get();
        username = profile.data()?['handle'] as String? ?? username;
      } catch (_) {
        // Keep posting with the email-based username if the lookup fails.
      }
    }
    try {
      if (_replyToCommentId case final parentId?) {
        final parentRef = _firestore.collection('comments').doc(parentId);
        await _firestore.runTransaction((transaction) async {
          final parent = await transaction.get(parentRef);
          if (!parent.exists) throw StateError('The comment you replied to no longer exists.');
          final replies = (parent.data()?['replies'] as List? ?? [])
              .whereType<Map>()
              .map((reply) => Map<String, dynamic>.from(reply))
              .toList();
          replies.add({
            'userId': user?.uid ?? 'guest',
            'username': username,
            'photoUrl': user?.photoURL,
            'text': text,
            'upvotes': 0,
            'createdAt': Timestamp.now(),
          });
          transaction.update(parentRef, {'replies': replies});
          transaction.update(_threadRef, {'replyCount': FieldValue.increment(1)});
        });
      } else {
        await _firestore.collection('comments').add({
          'threadId': widget.threadId,
          'userId': user?.uid ?? 'guest',
          'username': username,
          'photoUrl': user?.photoURL,
          'text': text,
          'upvotes': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'replies': <Map<String, dynamic>>[],
        });
        await _threadRef.update({'replyCount': FieldValue.increment(1)});
      }

      if (!mounted) return;
      _textController.clear();
      setState(() {
        _replyToCommentId = null;
        _replyToUsername = null;
        _posting = false;
      });
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post comment: $error')),
      );
    }
  }

  void _beginReply(String commentId, Map<String, dynamic> comment) {
    setState(() {
      _replyToCommentId = commentId;
      _replyToUsername = comment['username'] as String? ?? 'Listener';
    });
  }

  Future<void> _toggleCommentVote(String commentId) async {
    final voteKey = commentId;
    final increment = _votedIds.contains(voteKey) ? -1 : 1;
    setState(() {
      if (increment > 0) {
        _votedIds.add(voteKey);
      } else {
        _votedIds.remove(voteKey);
      }
    });
    try {
      final commentRef = _firestore.collection('comments').doc(commentId);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(commentRef);
        if (!snapshot.exists) throw StateError('Comment is no longer available.');
        transaction.update(commentRef, {
          'upvotes': _number(snapshot.data()?['upvotes']) + increment,
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (increment > 0) {
          _votedIds.remove(voteKey);
        } else {
          _votedIds.add(voteKey);
        }
      });
      _showVoteError(error);
    }
  }

  Future<void> _toggleReplyVote(String commentId, int replyIndex) async {
    final voteKey = '$commentId:$replyIndex';
    final increment = _votedIds.contains(voteKey) ? -1 : 1;
    setState(() {
      if (increment > 0) {
        _votedIds.add(voteKey);
      } else {
        _votedIds.remove(voteKey);
      }
    });
    final commentRef = _firestore.collection('comments').doc(commentId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(commentRef);
        final replies = (snapshot.data()?['replies'] as List? ?? [])
            .whereType<Map>()
            .map((reply) => Map<String, dynamic>.from(reply))
            .toList();
        if (replyIndex >= replies.length) throw StateError('Reply is no longer available.');
        final current = _number(replies[replyIndex]['upvotes']);
        replies[replyIndex]['upvotes'] = (current + increment).clamp(0, 1 << 31);
        transaction.update(commentRef, {'replies': replies});
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (increment > 0) {
          _votedIds.remove(voteKey);
        } else {
          _votedIds.add(voteKey);
        }
      });
      _showVoteError(error);
    }
  }

  void _showVoteError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not update vote: $error')),
    );
  }

  Widget _messageScaffold(String message) => Scaffold(
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      );
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    super.key,
    required this.commentId,
    required this.comment,
    required this.voted,
    required this.replyVoted,
    required this.onVote,
    required this.onReplyVote,
    required this.onReply,
  });

  final String commentId;
  final Map<String, dynamic> comment;
  final bool voted;
  final bool Function(int index) replyVoted;
  final VoidCallback onVote;
  final ValueChanged<int> onReplyVote;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final username = comment['username'] as String? ?? 'Listener';
    final text = comment['text'] as String? ?? '';
    final replies = (comment['replies'] as List? ?? []).whereType<Map>().toList();
    final upvotes = (_number(comment['upvotes'])) + (voted ? 1 : 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _UserAvatar(
                userId: comment['userId'] as String? ?? '',
                name: username,
                photoBase64: comment['photoBase64'] as String?,
                photoUrl: comment['photoUrl'] as String?,
                radius: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                    Text(_timestamp(comment['createdAt']), style: GoogleFonts.inter(fontSize: 11, color: _muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(text, style: GoogleFonts.inter(fontSize: 14, height: 1.5, color: _ink.withValues(alpha: 0.8))),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                onPressed: onVote,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  color: voted ? _teal : _muted,
                  size: 20,
                ),
              ),
              Text('$upvotes', style: GoogleFonts.inter(fontSize: 12, color: _muted)),
              const SizedBox(width: 10),
              TextButton(
                onPressed: onReply,
                style: TextButton.styleFrom(foregroundColor: _muted, padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text('Reply', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (replies.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 16, top: 4),
              padding: const EdgeInsets.only(left: 12),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Color(0x1A3F3F3F), width: 2)),
              ),
              child: ListView.separated(
                itemCount: replies.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final reply = Map<String, dynamic>.from(replies[index]);
                  return _ReplyRow(
                    reply: reply,
                    voted: replyVoted(index),
                    onVote: () => onReplyVote(index),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ReplyRow extends StatelessWidget {
  const _ReplyRow({required this.reply, required this.voted, required this.onVote});

  final Map<String, dynamic> reply;
  final bool voted;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    final username = reply['username'] as String? ?? 'Listener';
    final count = _number(reply['upvotes']) + (voted ? 1 : 0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UserAvatar(
          userId: reply['userId'] as String? ?? '',
          name: username,
          photoBase64: reply['photoBase64'] as String?,
          photoUrl: reply['photoUrl'] as String?,
          radius: 14,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _ink)),
                const SizedBox(height: 2),
                Text(reply['text'] as String? ?? '', style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: _muted)),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: onVote,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: Icon(Icons.arrow_upward_rounded, size: 15, color: voted ? _teal : _muted),
        ),
        Text('$count', style: GoogleFonts.inter(fontSize: 10, color: _muted)),
      ],
    );
  }
}

final Map<String, Future<Map<String, dynamic>?>> _avatarProfileCache = {};

Future<Map<String, dynamic>?> _avatarProfile(String userId) =>
    _avatarProfileCache.putIfAbsent(
      userId,
      () => FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get()
          .then((snapshot) => snapshot.data())
          .catchError((_) => null),
    );

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.userId,
    required this.name,
    required this.radius,
    this.photoBase64,
    this.photoUrl,
  });

  final String userId;
  final String name;
  final double radius;
  final String? photoBase64;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty || userId == 'guest') {
      return _avatarWithImage(photoBase64, photoUrl);
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: _avatarProfile(userId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) return _avatarWithImage(photoBase64, photoUrl);
        return _avatarWithImage(
          profile['photoBase64'] as String? ?? photoBase64,
          profile['photoUrl'] as String? ?? photoUrl,
        );
      },
    );
  }

  Widget _avatarWithImage(String? encoded, String? url) {
    ImageProvider? image;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(encoded));
      } catch (_) {
        image = null;
      }
    }
    if (image == null && url != null && url.isNotEmpty) {
      image = NetworkImage(url);
    }
    if (image == null) return _fallbackAvatar();
    return ClipOval(
      child: Image(
        image: image,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallbackAvatar(),
      ),
    );
  }

  Widget _fallbackAvatar() => CircleAvatar(
    radius: radius,
    backgroundColor: _ink,
    child: Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: radius * 0.72,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

int _number(Object? value) => value is num ? value.toInt() : 0;

String _timestamp(Object? value) {
  final date = value is Timestamp ? value.toDate() : value is DateTime ? value : null;
  if (date == null) return '';
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  return '${date.month}/${date.day}/${date.year}';
}
