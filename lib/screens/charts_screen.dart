import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/score_color.dart';

const _ink = Color(0xFF3F3F3F);
const _muted = Color(0xFF858585);
const _placeholder = Color(0xFFE0E0E0);
const _teal = Color(0xFF0E8A8A);

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  bool _show2026 = true;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final albums = _firestore.collection('albums');
    final allTimeQuery = albums.orderBy('communityScore', descending: true).limit(10);
    final bestOf2026Query = albums
        .where(
          'releaseDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(2026)),
        )
        .where(
          'releaseDate',
          isLessThan: Timestamp.fromDate(DateTime(2027)),
        );
    final songsQuery = _firestore.collection('songs').orderBy('score', descending: true).limit(10);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Charts',
                  style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _ink),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(child: _SectionTitle("USERS' BEST ALBUMS")),
                    _YearToggle(
                      show2026: _show2026,
                      onChanged: (show2026) => setState(() => _show2026 = show2026),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AlbumsChartCard(
                  query: _show2026 ? bestOf2026Query : allTimeQuery,
                  yearFiltered: _show2026,
                ),
                const SizedBox(height: 28),
                const _SectionTitle("USERS' BEST SONGS OF 2026"),
                const SizedBox(height: 12),
                _SongsChartCard(query: songsQuery),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YearToggle extends StatelessWidget {
  const _YearToggle({required this.show2026, required this.onChanged});

  final bool show2026;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE3E3E3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToggleButton(label: '2026', active: show2026, onPressed: () => onChanged(true)),
            _ToggleButton(label: 'All time', active: !show2026, onPressed: () => onChanged(false)),
          ],
        ),
      );
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.label, required this.active, required this.onPressed});

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: active ? _ink : Colors.transparent,
          foregroundColor: active ? Colors.white : _muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: _ink),
      );
}

class _AlbumsChartCard extends StatelessWidget {
  const _AlbumsChartCard({required this.query, required this.yearFiltered});

  final Query<Map<String, dynamic>> query;
  final bool yearFiltered;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _ChartMessage('Could not load album charts. ${snapshot.error}');
          if (!snapshot.hasData) return const _ChartLoading();

          final docs = snapshot.data!.docs.toList();
          if (yearFiltered) {
            // Firestore cannot filter the year portion of a Timestamp. Fetch the
            // year's range, then apply the requested global score ranking here.
            docs.sort((a, b) => (_score(b.data()['communityScore']))
                .compareTo(_score(a.data()['communityScore'])));
            if (docs.length > 10) docs.removeRange(10, docs.length);
          }
          if (docs.isEmpty) return const _ChartMessage('No albums to show yet.');

          return _ChartRowsCard(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              return _ChartRow(
                rank: index + 1,
                onTap: () => context.push('/album/${Uri.encodeComponent(doc.id)}'),
                title: data['title'] as String? ?? 'Unknown album',
                artist: data['artist'] as String? ?? 'Unknown artist',
                coverUrl: data['coverUrl'] as String? ?? '',
                score: _score(data['communityScore']),
                movement: data['movement'],
                previousRank: _number(data['previousRank']),
              );
            },
          );
        },
      );
}

class _SongsChartCard extends StatelessWidget {
  const _SongsChartCard({required this.query});

  final Query<Map<String, dynamic>> query;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _ChartMessage('Could not load song charts. ${snapshot.error}');
          if (!snapshot.hasData) return const _ChartLoading();
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const _ChartMessage('No songs to show yet.');

          return _ChartRowsCard(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              return _ChartRow(
                rank: index + 1,
                onTap: data['albumId'] is String
                    ? () => context.push('/album/${Uri.encodeComponent(data['albumId'] as String)}')
                    : null,
                title: data['title'] as String? ?? 'Unknown song',
                artist: data['artist'] as String? ?? 'Unknown artist',
                coverUrl: data['coverUrl'] as String? ?? data['albumCoverUrl'] as String? ?? '',
                score: _score(data['score']),
                movement: data['movement'],
                previousRank: _number(data['previousRank']),
              );
            },
          );
        },
      );
}

class _ChartRowsCard extends StatelessWidget {
  const _ChartRowsCard({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: ListView.separated(
          itemCount: itemCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: itemBuilder,
          separatorBuilder: (_, _) => const Padding(
            padding: EdgeInsets.only(left: 88, right: 12),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          ),
        ),
      );
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({
    required this.rank,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.score,
    this.onTap,
    this.movement,
    this.previousRank,
  });

  final int rank;
  final String title;
  final String artist;
  final String coverUrl;
  final int score;
  final VoidCallback? onTap;
  final Object? movement;
  final int? previousRank;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$rank', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _muted)),
                  const SizedBox(height: 3),
                  _MovementIndicator(movement: movement, previousRank: previousRank, currentRank: rank),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Cover(url: coverUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: scorePalette(score), borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Text(
                '$score',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ],
          ),
        ),
      );
}

class _MovementIndicator extends StatelessWidget {
  const _MovementIndicator({this.movement, this.previousRank, required this.currentRank});

  final Object? movement;
  final int? previousRank;
  final int currentRank;

  @override
  Widget build(BuildContext context) {
    final value = movement?.toString().toLowerCase();
    if (value == 'new') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(4)),
        child: Text('NEW', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white)),
      );
    }

    int? difference;
    if (previousRank != null) {
      difference = previousRank! - currentRank;
    } else if (movement is num) {
      difference = (movement as num).toInt();
    } else if (value == 'up' || value == 'rise') {
      difference = 1;
    } else if (value == 'down' || value == 'fall') {
      difference = -1;
    }
    if (difference == null || difference == 0) {
      return Text('—', style: GoogleFonts.inter(fontSize: 10, color: _muted));
    }
    if (difference > 0) {
      return Text('▲', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.green.shade600));
    }
    return Text('▼', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.red.shade600));
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 48,
          height: 48,
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

class _ChartLoading extends StatelessWidget {
  const _ChartLoading();

  @override
  Widget build(BuildContext context) => Container(
        height: 100,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: CircularProgressIndicator(color: _teal)),
      );
}

class _ChartMessage extends StatelessWidget {
  const _ChartMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Text(message, style: GoogleFonts.inter(fontSize: 13, color: _muted)),
      );
}

int _score(Object? value) => value is num ? value.round() : 0;
int? _number(Object? value) => value is num ? value.toInt() : null;
