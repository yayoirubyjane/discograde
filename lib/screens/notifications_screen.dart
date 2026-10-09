import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

const _teal = Color(0xFF0E8A8A);
const _ink = Color(0xFF3F3F3F);
const _muted = Color(0xFF858585);

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('Notifications', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFFF5F5F5),
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
      ),
      body: uid == null
          ? const Center(child: Text('Sign in to see notifications.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid)
                  .collection('notifications').orderBy('createdAt', descending: true).limit(100).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Could not load notifications. ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: _teal));
                final items = snapshot.data!.docs;
                if (items.isEmpty) return Center(child: Text('You’re all caught up.', style: GoogleFonts.inter(color: _muted)));
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = items[index];
                    final data = doc.data();
                    final type = data['type'] as String? ?? '';
                    final kind = type == 'like'
                        ? 'liked your review'
                        : type == 'follow'
                        ? 'started following you'
                        : 'commented on your review';
                    final actor = data['actorName'] as String? ?? 'Someone';
                    final detail = type == 'follow'
                        ? null
                        : type == 'comment'
                        ? (data['commentText'] as String? ?? data['albumTitle'] as String? ?? 'your review')
                        : (data['albumTitle'] as String? ?? 'your review');
                    final read = data['read'] == true;
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        onTap: () async {
                          try {
                            await doc.reference.update({'read': true});
                          } catch (_) {}
                          if (!context.mounted) return;
                          final actorId = data['actorId'] as String?;
                          if (type == 'follow' &&
                              actorId != null &&
                              actorId.isNotEmpty) {
                            context.push(
                              '/user/${Uri.encodeComponent(actorId)}'
                              '?visit=${Uri.encodeComponent(doc.id)}',
                            );
                            return;
                          }
                          final reviewId = data['reviewId'] as String?;
                          if (reviewId != null && reviewId.isNotEmpty) {
                            context.push('/review/$reviewId');
                            return;
                          }
                          final albumId = data['albumId'] as String?;
                          if (albumId != null && albumId.isNotEmpty) {
                            context.push('/album/$albumId');
                          }
                        },
                        leading: type == 'follow'
                            ? _FollowerAvatar(
                                userId: data['actorId'] as String? ?? '',
                                name: actor,
                              )
                            : CircleAvatar(
                                backgroundColor: const Color(0xFFE8F4F3),
                                child: Icon(
                                  type == 'like'
                                      ? Icons.favorite
                                      : Icons.chat_bubble_outline,
                                  color: _teal,
                                  size: 20,
                                ),
                              ),
                        title: Text('$actor $kind', style: GoogleFonts.inter(fontWeight: read ? FontWeight.w400 : FontWeight.w700, color: _ink, fontSize: 14)),
                        subtitle: detail == null
                            ? null
                            : Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: _muted, fontSize: 12)),
                        trailing: read ? null : const CircleAvatar(radius: 4, backgroundColor: _teal),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

final _followerProfiles = <String, Future<Map<String, dynamic>?>>{};

class _FollowerAvatar extends StatelessWidget {
  const _FollowerAvatar({required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return _avatar(null);
    final profile = _followerProfiles.putIfAbsent(userId, () async {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        return snapshot.data();
      } catch (_) {
        return null;
      }
    });
    return FutureBuilder<Map<String, dynamic>?>(
      future: profile,
      builder: (context, snapshot) => _avatar(snapshot.data),
    );
  }

  Widget _avatar(Map<String, dynamic>? profile) {
    ImageProvider? image;
    final encoded = profile?['photoBase64'] as String?;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(encoded));
      } catch (_) {}
    }
    final photoUrl = profile?['photoUrl'] as String?;
    if (image == null && photoUrl != null && photoUrl.isNotEmpty) {
      image = NetworkImage(photoUrl);
    }

    final visibleName = name.replaceFirst('@', '').trim();
    final initial = visibleName.isEmpty ? '?' : visibleName[0].toUpperCase();
    return CircleAvatar(
      backgroundColor: const Color(0xFFE8F4F3),
      foregroundImage: image,
      child: image == null
          ? Text(
              initial,
              style: GoogleFonts.inter(
                color: _teal,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}
