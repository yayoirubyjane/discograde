import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

const _teal = Color(0xFF0E8A8A);
const _ink = Color(0xFF3F3F3F);
const _muted = Color(0xFF808080);

class AiDiscoveryScreen extends StatefulWidget {
  const AiDiscoveryScreen({super.key});

  @override
  State<AiDiscoveryScreen> createState() => _AiDiscoveryScreenState();
}

class _AiDiscoveryScreenState extends State<AiDiscoveryScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[
    const _ChatMessage(
      fromAssistant: true,
      text: 'Tell me what you feel like listening to, or name an album you love. I’ll find a few picks from Discograde’s catalog.',
    ),
  ];
  final Map<String, Map<String, dynamic>> _albumsById = {};
  ChatSession? _chat;
  bool _loadingCatalog = true;
  bool _sending = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final snapshots = await Future.wait([
        FirebaseFirestore.instance.collection('albums').limit(100).get(),
        if (FirebaseAuth.instance.currentUser != null)
          FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .get(),
        if (FirebaseAuth.instance.currentUser != null)
          FirebaseFirestore.instance
              .collection('reviews')
              .where(
                'userId',
                isEqualTo: FirebaseAuth.instance.currentUser!.uid,
              )
              .orderBy('createdAt', descending: true)
              .limit(12)
              .get(),
      ]);
      final albumDocs = snapshots.first as QuerySnapshot<Map<String, dynamic>>;
      final albums = <Map<String, dynamic>>[];
      for (final doc in albumDocs.docs) {
        final data = doc.data();
        final compact = <String, dynamic>{
          'id': doc.id,
          'title': data['title'] ?? 'Unknown album',
          'artist': data['artist'] ?? 'Unknown artist',
          if (data['genres'] is List) 'genres': data['genres'],
          if (data['format'] != null) 'format': data['format'],
          if (data['releaseDate'] != null)
            'releaseDate': _dateLabel(data['releaseDate']),
          if (data['trackList'] is List)
            'trackCount': (data['trackList'] as List).length,
          if (data['communityScore'] != null)
            'communityScore': data['communityScore'],
          if (data['ratingCount'] != null) 'ratingCount': data['ratingCount'],
        };
        albums.add(compact);
        _albumsById[doc.id] = data;
      }
      if (albums.isEmpty) {
        throw StateError('There are no albums in the catalog yet.');
      }

      final user = FirebaseAuth.instance.currentUser;
      var snapshotIndex = 1;
      Map<String, dynamic> profile = {};
      List<Map<String, dynamic>> reviews = [];
      if (user != null) {
        profile =
            (snapshots[snapshotIndex++]
                    as DocumentSnapshot<Map<String, dynamic>>)
                .data() ??
            {};
        final reviewSnapshot =
            snapshots[snapshotIndex] as QuerySnapshot<Map<String, dynamic>>;
        reviews = reviewSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'albumId': data['albumId'],
            'score': data['score'],
            if ((data['text'] as String?)?.trim().isNotEmpty == true)
              'review': (data['text'] as String).trim().substring(
                0,
                (data['text'] as String).trim().length.clamp(0, 240).toInt(),
              ),
          };
        }).toList();
      }

      final model = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-3.8-flash',
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.7,
        ),
        systemInstruction: Content.text('''
You are Discograde's album discovery assistant. Help users find albums from the supplied Discograde catalog only. Never invent an album or claim catalog details that are absent. Personalize with the listener profile and their review scores when provided. Ask one short follow-up if the request is too vague. Keep the response friendly, concise, and focused on music discovery.
Always return valid JSON with exactly this shape: {"message":"short helpful reply","recommendations":[{"albumId":"catalog id","reason":"one sentence explaining the match"}]}. Use zero recommendations for follow-up questions; otherwise return up to three distinct album IDs that appear in the catalog.
Listener profile: ${jsonEncode({'favoriteGenres': profile['favoriteGenres'] ?? [], 'recentReviews': reviews})}
Available Discograde catalog (only source of recommendations): ${jsonEncode(albums)}
'''),
      );

      if (!mounted) return;
      setState(() {
        _chat = model.startChat();
        _loadingCatalog = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loadingCatalog = false;
      });
    }
  }

  static String _dateLabel(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String().split('T').first;
    }
    if (value is DateTime) return value.toIso8601String().split('T').first;
    return value.toString();
  }

  Future<void> _send([String? suggestion]) async {
    final prompt = (suggestion ?? _input.text).trim();
    if (prompt.isEmpty || _sending || _chat == null) return;
    _input.clear();
    setState(() {
      _sending = true;
      _messages.add(_ChatMessage(fromAssistant: false, text: prompt));
    });
    _scrollToBottom();
    try {
      final response = await _chat!.sendMessage(Content.text(prompt));
      final decoded = jsonDecode(response.text ?? '{}') as Map<String, dynamic>;
      final recommendations = (decoded['recommendations'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => _albumsById.containsKey(item['albumId']))
          .take(3)
          .toList();
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            fromAssistant: true,
            text:
                decoded['message'] as String? ??
                'Here are a few albums to explore.',
            recommendations: recommendations,
          ),
        );
      });
    } catch (error) {
      debugPrint('AI discovery request failed: $error');
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            fromAssistant: true,
            text: kDebugMode
                ? 'AI request failed: $error'
                : 'I couldn’t get a recommendation just now. Please try again.',
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: const Color(0xFFF5F5F5),
      title: Text(
        'AI DISCOVERY',
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
    ),
    body: SafeArea(
      child: _loadingCatalog
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _loadError != null
          ? _errorContent()
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const _TypingIndicator();
                      }
                      final message = _messages[index];
                      return _MessageBubble(
                        message: message,
                        albums: _albumsById,
                      );
                    },
                  ),
                ),
                if (_messages.length == 1) _suggestions(),
                _composer(),
              ],
            ),
    ),
  );

  Widget _errorContent() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_music_outlined, size: 42, color: _teal),
          const SizedBox(height: 14),
          Text(
            'Could not load album recommendations.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 8),
          Text(
            _loadError!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _loadingCatalog = true;
                _loadError = null;
              });
              _loadCatalog();
            },
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );

  Widget _suggestions() => SizedBox(
    height: 44,
    child: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      children: [
        _SuggestionChip(
          label: 'Something mellow',
          onTap: () => _send('Recommend something mellow and introspective.'),
        ),
        _SuggestionChip(
          label: 'Like my favorites',
          onTap: () => _send(
            'Recommend albums that fit my favorite genres and ratings.',
          ),
        ),
        _SuggestionChip(
          label: 'Hidden gems',
          onTap: () => _send('Find an underrated album from the catalog.'),
        ),
      ],
    ),
  );

  Widget _composer() => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFE8E8E8))),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            enabled: !_sending && _chat != null,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'What would you like to hear?',
              hintStyle: GoogleFonts.inter(color: _muted, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        IconButton.filled(
          onPressed: _sending ? null : () => _send(),
          style: IconButton.styleFrom(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.arrow_upward_rounded),
          tooltip: 'Send',
        ),
      ],
    ),
  );
}

class _ChatMessage {
  const _ChatMessage({
    required this.fromAssistant,
    required this.text,
    this.recommendations = const [],
  });
  final bool fromAssistant;
  final String text;
  final List<Map<String, dynamic>> recommendations;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.albums});
  final _ChatMessage message;
  final Map<String, Map<String, dynamic>> albums;

  @override
  Widget build(BuildContext context) => Align(
    alignment: message.fromAssistant
        ? Alignment.centerLeft
        : Alignment.centerRight,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .88,
      ),
      child: Column(
        crossAxisAlignment: message.fromAssistant
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: message.fromAssistant ? Colors.white : _teal,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.text,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                color: message.fromAssistant ? _ink : Colors.white,
              ),
            ),
          ),
          for (final recommendation in message.recommendations)
            if (albums[recommendation['albumId']] case final album?)
              _RecommendedAlbumCard(
                id: recommendation['albumId'] as String,
                data: album,
                reason: recommendation['reason'] as String? ?? '',
              ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

class _RecommendedAlbumCard extends StatelessWidget {
  const _RecommendedAlbumCard({
    required this.id,
    required this.data,
    required this.reason,
  });
  final String id;
  final Map<String, dynamic> data;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'Unknown album';
    final artist = data['artist'] as String? ?? 'Unknown artist';
    final cover = data['coverUrl'] as String? ?? '';
    return InkWell(
      onTap: () => context.push('/album/${Uri.encodeComponent(id)}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: MediaQuery.sizeOf(context).width * .82,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEAEAEA)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: cover.isEmpty
                  ? const SizedBox(
                      width: 58,
                      height: 58,
                      child: ColoredBox(
                        color: Color(0xFFE5E5E5),
                        child: Icon(Icons.album_outlined, color: _muted),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: cover,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox(
                        width: 58,
                        height: 58,
                        child: ColoredBox(
                          color: Color(0xFFE5E5E5),
                          child: Icon(Icons.album_outlined, color: _muted),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(color: _muted, fontSize: 12),
                  ),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _ink,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _muted),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          color: _teal,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: onTap,
      side: const BorderSide(color: Color(0xFFB8DEDE)),
      backgroundColor: const Color(0xFFEFF8F8),
    ),
  );
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const SizedBox(
        width: 28,
        height: 14,
        child: LinearProgressIndicator(
          color: _teal,
          backgroundColor: Color(0xFFE4F2F2),
        ),
      ),
    ),
  );
}
