import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/score_color.dart';

const _ink = Color(0xFF3F3F3F);
const _muted = Color(0xFF858585);
const _teal = Color(0xFF0E8A8A);

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  bool _show2026 = true;

  @override
  Widget build(BuildContext context) {
    final albums = FirebaseFirestore.instance.collection('albums');
    final allTimeQuery = albums
        .orderBy('communityScore', descending: true)
        .limit(10);
    final bestOf2026Query = albums
        .where(
          'releaseDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(2026)),
        )
        .where(
          'releaseDate',
          isLessThan: Timestamp.fromDate(DateTime(2027)),
        );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 112),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Charts',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "USERS' BEST ALBUMS",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                          color: _ink,
                        ),
                      ),
                    ),
                    _YearToggle(
                      show2026: _show2026,
                      onChanged: (value) => setState(() => _show2026 = value),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AlbumsChartCard(
                  query: _show2026 ? bestOf2026Query : allTimeQuery,
                  yearFiltered: _show2026,
                ),
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
        _ToggleButton(
          label: '2026',
          active: show2026,
          onPressed: () => onChanged(true),
        ),
        _ToggleButton(
          label: 'All time',
          active: !show2026,
          onPressed: () => onChanged(false),
        ),
      ],
    ),
  );
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.active,
    required this.onPressed,
  });

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
    child: Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _AlbumsChartCard extends StatelessWidget {
  const _AlbumsChartCard({required this.query, required this.yearFiltered});

  final Query<Map<String, dynamic>> query;
  final bool yearFiltered;

  @override
  Widget build(BuildContext context) => StreamBuilder<
    QuerySnapshot<Map<String, dynamic>>
  >(
    stream: query.snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _ChartMessage('Could not load album charts.');
      }
      if (!snapshot.hasData) return const _ChartLoading();

      final docs = snapshot.data!.docs.toList();
      if (yearFiltered) {
        docs.sort(
          (a, b) => _score(
            b.data()['communityScore'],
          ).compareTo(_score(a.data()['communityScore'])),
        );
        if (docs.length > 10) docs.removeRange(10, docs.length);
      }

      if (docs.isEmpty) {
        return _ChartMessage(
          yearFiltered
              ? 'No albums with ratings from 2026 yet.'
              : 'No album ratings yet.',
        );
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            for (var index = 0; index < docs.length; index++) ...[
              if (index > 0)
                const Divider(height: 1, color: Color(0xFFE8E8E8)),
              _ChartRow(rank: index + 1, album: docs[index]),
            ],
          ],
        ),
      );
    },
  );
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.rank, required this.album});

  final int rank;
  final QueryDocumentSnapshot<Map<String, dynamic>> album;

  @override
  Widget build(BuildContext context) {
    final data = album.data();
    final score = _score(data['communityScore']);
    final coverUrl = data['coverUrl'] as String? ?? '';
    final title = data['title'] as String? ?? 'Unknown album';
    final artist = data['artist'] as String? ?? 'Unknown artist';

    return InkWell(
      onTap: () => context.push('/album/${Uri.encodeComponent(album.id)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank.',
                style: GoogleFonts.inter(fontSize: 13, color: _muted),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: coverUrl.isEmpty
                    ? const ColoredBox(
                        color: Color(0xFFE8E8E8),
                        child: Icon(Icons.album_outlined, color: _muted),
                      )
                    : CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const ColoredBox(
                          color: Color(0xFFE8E8E8),
                          child: Icon(Icons.album_outlined, color: _muted),
                        ),
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
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (score > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: scorePalette(score),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$score',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(child: CircularProgressIndicator(color: _teal)),
  );
}

class _ChartMessage extends StatelessWidget {
  const _ChartMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      message,
      style: GoogleFonts.inter(fontSize: 13, color: _muted),
    ),
  );
}

int _score(Object? value) => value is num ? value.round() : 0;
