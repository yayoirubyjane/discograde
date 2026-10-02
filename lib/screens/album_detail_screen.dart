import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/score_color.dart';

const _charcoal = Color(0xFF3F3F3F);
const _teal = Color(0xFF0E8A8A);
const _grey = Color(0xFF858585);
const _placeholder = Color(0xFFE0E0E0);
const _red = Color(0xFFBA011A);

class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen>
    with SingleTickerProviderStateMixin {
  int _reviewSort = 1; // 0 = popular, 1 = recent
  late final TabController _reviewTabController;
  late final ScrollController _scrollController;
  final ValueNotifier<double> _appBarTitleOpacity = ValueNotifier(0);
  final FocusNode _rateTracksFocus = FocusNode(debugLabel: 'Rate tracks');

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _reviewTabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: 1,
    );
    _scrollController = ScrollController()
      ..addListener(_updateAppBarTitleOpacity);
  }

  void _updateAppBarTitleOpacity() {
    const collapseDistance = 260.0 - kToolbarHeight;
    final opacity =
        ((_scrollController.offset - collapseDistance * 0.58) /
                (collapseDistance * 0.38))
            .clamp(0.0, 1.0)
            .toDouble();
    if ((_appBarTitleOpacity.value - opacity).abs() > 0.01) {
      _appBarTitleOpacity.value = opacity;
    }
  }

  @override
  void dispose() {
    _reviewTabController.dispose();
    _scrollController
      ..removeListener(_updateAppBarTitleOpacity)
      ..dispose();
    _appBarTitleOpacity.dispose();
    _rateTracksFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albumRef = _firestore.collection('albums').doc(widget.albumId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: albumRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorScaffold('Could not load this album. ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F5F5),
            body: Center(child: CircularProgressIndicator(color: _teal)),
          );
        }
        if (!snapshot.data!.exists || snapshot.data!.data() == null) {
          return _errorScaffold('This album could not be found.');
        }

        final album = snapshot.data!.data()!;
        final reviewsQuery = _firestore
            .collection('reviews')
            .where('albumId', isEqualTo: widget.albumId)
            .orderBy('createdAt', descending: true);

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              _albumAppBar(album),
              SliverToBoxAdapter(child: _albumOverview(album)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () => _openReviewSheet(album),
                      style: FilledButton.styleFrom(
                        backgroundColor: _charcoal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Write a Review',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _detailsCard(album)),
              SliverToBoxAdapter(child: _trackListCard(album)),
              SliverToBoxAdapter(child: _reviewTabs()),
              _reviewsSliver(reviewsQuery),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        );
      },
    );
  }

  Widget _errorScaffold(String message) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    appBar: AppBar(
      backgroundColor: _charcoal,
      foregroundColor: Colors.white,
      title: const Text('Album'),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    ),
  );

  Widget _albumAppBar(Map<String, dynamic> album) {
    final coverUrl = album['coverUrl'] as String? ?? '';
    final title = album['title'] as String? ?? 'Album';
    return SliverAppBar(
      pinned: true,
      expandedHeight: 260,
      backgroundColor: _charcoal,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      title: ValueListenableBuilder<double>(
        valueListenable: _appBarTitleOpacity,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            _cover(coverUrl),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x33000000),
                    Color(0x00000000),
                    Color(0x66000000),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _albumOverview(Map<String, dynamic> album) {
    final score = _toInt(album['communityScore']) ?? 0;
    final ratingCount = _toInt(album['ratingCount']) ?? 0;
    final releaseDate = _dateTime(album['releaseDate']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album['title'] as String? ?? 'Unknown album',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _charcoal,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  album['artist'] as String? ?? 'Unknown artist',
                  style: GoogleFonts.inter(fontSize: 14, color: _grey),
                ),
                if (releaseDate != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    '${releaseDate.year}',
                    style: GoogleFonts.inter(fontSize: 12, color: _grey),
                  ),
                ],
              ],
            ),
          ),
          Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scorePalette(score),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$score',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'community score',
                style: GoogleFonts.inter(fontSize: 9, color: _grey),
              ),
              const SizedBox(height: 2),
              Text(
                '$ratingCount ratings',
                style: GoogleFonts.inter(fontSize: 11, color: _grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(Map<String, dynamic> album) {
    final producers = _stringList(album['producers']);
    final writers = _stringList(album['writers']);
    final genres = _stringList(album['genres']);
    final vibes = _stringList(album['vibes']);
    final date = _dateTime(album['releaseDate']);
    final dateText = date == null ? '—' : _formatReleaseDate(date);

    return _WhiteCard(
      margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeading('Details & Credits'),
          const SizedBox(height: 12),
          _DetailRow(label: 'Release Date', value: dateText),
          _DetailRow(label: 'Format', value: album['format'] as String? ?? '—'),
          _DetailRow(label: 'Label', value: album['label'] as String? ?? '—'),
          _DetailRow(label: 'Producer(s)', value: _creditSummary(producers)),
          _DetailRow(label: 'Writer(s)', value: _creditSummary(writers)),
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            _chipGroup('Genres', genres, borderColor: _teal, textColor: _teal),
          ],
          if (vibes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _chipGroup(
              'Vibes / Tags',
              vibes,
              borderColor: const Color(0xFFBDBDBD),
              textColor: _grey,
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _showFullCredits(album),
              child: Text(
                'View full credits',
                style: GoogleFonts.inter(
                  color: _teal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackListCard(Map<String, dynamic> album) {
    final rawTracks = album['trackList'];
    final tracks = rawTracks is List
        ? rawTracks
              .whereType<Map>()
              .map((track) => Map<String, dynamic>.from(track))
              .toList()
        : <Map<String, dynamic>>[];
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ratingsStream = uid == null
        ? null
        : _firestore
              .collection('users')
              .doc(uid)
              .collection('trackRatings')
              .doc(widget.albumId)
              .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ratingsStream,
      builder: (context, snapshot) {
        final rawRatings = snapshot.data?.data()?['ratings'];
        final personalRatings = <String, int>{};
        if (rawRatings is Map) {
          for (final entry in rawRatings.entries) {
            final score = _toInt(entry.value);
            if (score != null && score >= 0 && score <= 100) {
              personalRatings[entry.key.toString()] = score;
            }
          }
        }

        return _WhiteCard(
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(child: _cardHeading('Track List')),
                    TextButton(
                      focusNode: _rateTracksFocus,
                      onPressed: tracks.isEmpty
                          ? null
                          : () => _openTrackRatings(tracks, personalRatings),
                      style: TextButton.styleFrom(
                        foregroundColor: _teal,
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        personalRatings.isEmpty
                            ? 'Rate tracks'
                            : 'Edit ratings',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (tracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'No track list available.',
                    style: GoogleFonts.inter(fontSize: 13, color: _grey),
                  ),
                )
              else
                ListView.separated(
                  itemCount: tracks.length,
                  shrinkWrap: true,
                  primary: false,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    thickness: 0.5,
                    color: Color(0xFFE7E7E7),
                    indent: 16,
                    endIndent: 16,
                  ),
                  itemBuilder: (context, index) => _TrackRow(
                    track: tracks[index],
                    index: index,
                    personalScore:
                        personalRatings[_trackRatingKey(tracks[index], index)],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openTrackRatings(
    List<Map<String, dynamic>> tracks,
    Map<String, int> currentRatings,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Log in to rate tracks.')));
      return;
    }
    final savedRatings = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => _TrackRatingsSheet(
        albumId: widget.albumId,
        userId: uid,
        tracks: tracks,
        currentRatings: currentRatings,
      ),
    );
    if (!mounted) return;
    _rateTracksFocus.requestFocus();
    if (savedRatings != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Track ratings saved.')));
    }
  }

  Widget _reviewTabs() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: TabBar(
      controller: _reviewTabController,
      onTap: (index) => setState(() => _reviewSort = index),
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: _teal, width: 3),
        insets: EdgeInsets.symmetric(horizontal: 14),
      ),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelColor: _charcoal,
      unselectedLabelColor: _grey,
      labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
      tabs: const [
        Tab(text: 'POPULAR'),
        Tab(text: 'RECENT'),
      ],
    ),
  );

  Widget _reviewsSliver(Query<Map<String, dynamic>> query) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Could not load reviews. ${snapshot.error}',
                  style: GoogleFonts.inter(color: _grey),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: _teal)),
              ),
            );
          }
          final reviews = snapshot.data!.docs.toList();
          if (_reviewSort == 0) {
            reviews.sort(
              (a, b) => (_toInt(b.data()['likes']) ?? 0).compareTo(
                _toInt(a.data()['likes']) ?? 0,
              ),
            );
          }
          if (reviews.isEmpty) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text(
                  'No reviews yet. Be the first to review this album.',
                  style: GoogleFonts.inter(fontSize: 13, color: _grey),
                ),
              ),
            );
          }
          return SliverList.separated(
            itemCount: reviews.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _ReviewCard(review: reviews[index].data()),
          );
        },
      );

  Future<void> _openReviewSheet(Map<String, dynamic> album) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ReviewComposer(
        onSubmit: (score, text) => _submitReview(album, score, text),
      ),
    );
  }

  Future<void> _submitReview(
    Map<String, dynamic> album,
    int score,
    String text,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    var username = user?.email?.split('@').first ?? 'listener';
    if (user != null) {
      try {
        final profile = await _firestore.collection('users').doc(user.uid).get();
        username = profile.data()?['handle'] as String? ?? username;
      } catch (_) {
        // Use the account email as a fallback if profile lookup is unavailable.
      }
    }
    final reviewRef = _firestore.collection('reviews').doc();
    final albumRef = _firestore.collection('albums').doc(widget.albumId);
    try {
      await _firestore.runTransaction((transaction) async {
        final albumSnapshot = await transaction.get(albumRef);
        if (!albumSnapshot.exists) throw StateError('Album no longer exists.');
        final data = albumSnapshot.data() ?? <String, dynamic>{};
        final oldCount = _toInt(data['ratingCount']) ?? 0;
        final oldScore = _toDouble(data['communityScore']) ?? 0;
        final newCount = oldCount + 1;
        final newScore = (((oldScore * oldCount) + score) / newCount).round();

        transaction.set(reviewRef, {
          'albumId': widget.albumId,
          'userId': user?.uid ?? 'guest',
          'username': username,
          'score': score,
          'text': text.trim(),
          'likes': 0,
          'comments': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(albumRef, {
          'communityScore': newScore,
          'ratingCount': newCount,
        });
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Review submitted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit review: $error')),
      );
      rethrow;
    }
  }

  void _showFullCredits(Map<String, dynamic> album) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardHeading('Full Credits'),
              const SizedBox(height: 16),
              _DetailRow(
                label: 'Producers',
                value: _stringList(album['producers']).join(', ').ifEmpty('—'),
              ),
              _DetailRow(
                label: 'Writers',
                value: _stringList(album['writers']).join(', ').ifEmpty('—'),
              ),
              _DetailRow(
                label: 'Label',
                value: album['label'] as String? ?? '—',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _creditSummary(List<String> names) {
    if (names.length <= 3) return names.join(', ').ifEmpty('—');
    return '${names.take(3).join(', ')}, and more';
  }

  Widget _chipGroup(
    String label,
    List<String> values, {
    required Color borderColor,
    required Color textColor,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: GoogleFonts.inter(fontSize: 12, color: _grey)),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in values)
            Chip(
              label: Text(value),
              side: BorderSide(color: borderColor),
              backgroundColor: Colors.white,
              labelStyle: GoogleFonts.inter(fontSize: 11, color: textColor),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    ],
  );
}

class _ReviewComposer extends StatefulWidget {
  const _ReviewComposer({required this.onSubmit});

  final Future<void> Function(int score, String text) onSubmit;

  @override
  State<_ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends State<_ReviewComposer> {
  final _textController = TextEditingController();
  double _score = 75;
  bool _saving = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write a few words about the album first.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSubmit(_score.round(), _textController.text);
    } catch (_) {
      // The parent shows the Firebase error in a SnackBar.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final selectedScore = _score.round();
    final selectedScoreColor = scorePalette(selectedScore);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Write a Review',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _charcoal,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Your score',
                style: GoogleFonts.inter(fontSize: 13, color: _grey),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: selectedScoreColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$selectedScore',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: selectedScoreColor,
              thumbColor: selectedScoreColor,
              overlayColor: selectedScoreColor.withValues(alpha: 0.14),
            ),
            child: Slider(
              value: _score,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (value) => setState(() => _score = value),
            ),
          ),
          TextField(
            controller: _textController,
            minLines: 4,
            maxLines: 7,
            maxLength: 2000,
            decoration: InputDecoration(
              hintText: 'What did you think of this album?',
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Submit Review',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: _grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 12, color: _charcoal),
          ),
        ),
      ],
    ),
  );
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.index,
    required this.personalScore,
  });
  final Map<String, dynamic> track;
  final int index;
  final int? personalScore;

  @override
  Widget build(BuildContext context) {
    final title = track['title'] as String? ?? 'Untitled track';
    final duration = track['duration']?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${_toInt(track['number']) ?? index + 1}',
              style: GoogleFonts.inter(fontSize: 12, color: _grey),
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 14, color: _charcoal),
            ),
          ),
          if (duration != null && duration.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              duration,
              style: GoogleFonts.inter(fontSize: 12, color: _grey),
            ),
          ],
          if (personalScore != null) ...[
            const SizedBox(width: 10),
            Semantics(
              label:
                  'Your personal rating for $title: $personalScore out of 100',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 32,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: scorePalette(personalScore!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$personalScore',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    'You',
                    style: GoogleFonts.inter(fontSize: 9, color: _grey),
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

String _trackRatingKey(Map<String, dynamic> track, int index) =>
    '${_toInt(track['number']) ?? index + 1}';

class _TrackRatingsSheet extends StatefulWidget {
  const _TrackRatingsSheet({
    required this.albumId,
    required this.userId,
    required this.tracks,
    required this.currentRatings,
  });
  final String albumId;
  final String userId;
  final List<Map<String, dynamic>> tracks;
  final Map<String, int> currentRatings;

  @override
  State<_TrackRatingsSheet> createState() => _TrackRatingsSheetState();
}

class _TrackRatingsSheetState extends State<_TrackRatingsSheet> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, String?> _errors = {};
  Map<String, String> _initialValues = {};
  bool _loading = true;
  bool _saving = false;
  bool _placedInitialFocus = false;
  String? _loadError;

  CollectionReference<Map<String, dynamic>> get _ratingsCollection =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('trackRatings');

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    try {
      final doc = await _ratingsCollection.doc(widget.albumId).get();
      final values = <String, int>{...widget.currentRatings};
      final raw = doc.data()?['ratings'];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final score = _toInt(entry.value);
          if (score != null && score >= 0 && score <= 100) {
            values[entry.key.toString()] = score;
          }
        }
      }
      for (var i = 0; i < widget.tracks.length; i++) {
        final track = widget.tracks[i];
        final key = _trackRatingKey(track, i);
        _controllers[key] = TextEditingController(
          text: values[key]?.toString() ?? '',
        );
        _focusNodes[key] = FocusNode(
          debugLabel: 'Score for ${track['title'] ?? 'track'}',
        )..addListener(() => _focusChanged(key));
        _errors[key] = null;
      }
      _initialValues = {
        for (final entry in _controllers.entries) entry.key: entry.value.text,
      };
      if (mounted) setState(() => _loading = false);
      _focusFirstUnrated();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load your saved ratings. Close this sheet and try again.';
        });
      }
    }
  }

  void _focusFirstUnrated() {
    if (_placedInitialFocus || !mounted || _loading || widget.tracks.isEmpty) {
      return;
    }
    _placedInitialFocus = true;
    var index = widget.tracks.indexWhere((track) {
      final i = widget.tracks.indexOf(track);
      return (_controllers[_trackRatingKey(track, i)]?.text ?? '').isEmpty;
    });
    if (index < 0) index = 0;
    final key = _trackRatingKey(widget.tracks[index], index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[key]?.requestFocus();
    });
  }

  void _focusChanged(String key) {
    if (_focusNodes[key]?.hasFocus == false) _validateKey(key);
  }

  String? _errorFor(String value) {
    if (value.isEmpty) return null;
    final score = int.tryParse(value);
    return score == null || score < 0 || score > 100
        ? 'Enter a whole number from 0 to 100.'
        : null;
  }

  bool _validateKey(String key) {
    _errors[key] = _errorFor(_controllers[key]?.text ?? '');
    if (mounted) setState(() {});
    return _errors[key] == null;
  }

  bool get _hasInvalid => _controllers.values.any(
    (controller) => _errorFor(controller.text) != null,
  );
  bool get _dirty => _controllers.entries.any(
    (entry) => entry.value.text != _initialValues[entry.key],
  );

  Future<void> _close() async {
    if (_saving) return;
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Discard changes?',
          style: GoogleFonts.inter(
            color: _charcoal,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Your track ratings have not been saved.',
          style: GoogleFonts.inter(color: _charcoal),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep editing', style: GoogleFonts.inter(color: _teal)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Discard', style: GoogleFonts.inter(color: _red)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    var valid = true;
    for (final key in _controllers.keys) {
      if (!_validateKey(key)) valid = false;
    }
    if (!valid) {
      for (final entry in _errors.entries) {
        if (entry.value != null) {
          _focusNodes[entry.key]?.requestFocus();
          break;
        }
      }
      return;
    }
    final ratings = <String, int>{};
    for (final entry in _controllers.entries) {
      if (entry.value.text.isNotEmpty) {
        ratings[entry.key] = int.parse(entry.value.text);
      }
    }
    setState(() => _saving = true);
    try {
      await _ratingsCollection.doc(widget.albumId).set({
        'userId': widget.userId,
        'albumId': widget.albumId,
        'ratings': ratings,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.of(context).pop(ratings);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save track ratings. Check your connection and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewInsets.bottom;
    final height = (availableHeight * 0.9).clamp(280.0, 760.0).toDouble();
    return PopScope<void>(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: height,
            child: Material(
              color: const Color(0xFFF5F5F5),
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFBDBDBD),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 12, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rate the tracks',
                                style: GoogleFonts.inter(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: _charcoal,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Enter a score from 0 to 100 for each track.',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: _grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close track ratings',
                          onPressed: _saving ? null : _close,
                          icon: const Icon(Icons.close),
                          color: _charcoal,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE3E3E3)),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(color: _teal),
                          )
                        : _loadError != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(color: _red),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: widget.tracks.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) =>
                                _trackInput(widget.tracks[index], index),
                          ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE3E3E3)),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      12 + media.padding.bottom,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed:
                            _loading ||
                                _loadError != null ||
                                _saving ||
                                _hasInvalid
                            ? null
                            : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: _teal,
                          disabledBackgroundColor: const Color(0xFFBDBDBD),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Save track ratings',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trackInput(Map<String, dynamic> track, int index) {
    final key = _trackRatingKey(track, index);
    final title = track['title'] as String? ?? 'Untitled track';
    final duration = track['duration']?.toString();
    final controller = _controllers[key]!;
    final parsed = int.tryParse(controller.text);
    final score = parsed != null && parsed >= 0 && parsed <= 100
        ? parsed
        : null;
    final error = _errors[key];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${_toInt(track['number']) ?? index + 1}',
              style: GoogleFonts.inter(fontSize: 13, color: _grey),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _charcoal,
                  ),
                ),
                if (duration != null && duration.isNotEmpty)
                  Text(
                    duration,
                    style: GoogleFonts.inter(fontSize: 11, color: _grey),
                  ),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        error,
                        style: GoogleFonts.inter(fontSize: 11, color: _red),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 66,
                      height: 48,
                      child: Semantics(
                        label: 'Score for $title',
                        child: TextField(
                          controller: controller,
                          focusNode: _focusNodes[key],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 3,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '0–100',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 11,
                              color: _grey,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: error == null
                                    ? const Color(0xFFD8D8D8)
                                    : _red,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _teal,
                                width: 2,
                              ),
                            ),
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _charcoal,
                          ),
                          onChanged: (_) {
                            _errors[key] = null;
                            setState(() {});
                          },
                          onSubmitted: (_) {
                            if (index + 1 < widget.tracks.length) {
                              _focusNodes[_trackRatingKey(
                                    widget.tracks[index + 1],
                                    index + 1,
                                  )]
                                  ?.requestFocus();
                            } else {
                              _focusNodes[key]?.unfocus();
                            }
                          },
                        ),
                      ),
                    ),
                    Text(
                      ' / 100',
                      style: GoogleFonts.inter(fontSize: 10, color: _grey),
                    ),
                  ],
                ),
                if (score != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 42,
                        minHeight: 24,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: scorePalette(score),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$score',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  const _ReviewCard({required this.review});

  final Map<String, dynamic> review;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _expanded = false;
  bool _liked = false;

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final text = review['text'] as String? ?? '';
    final isLong = text.length > 160;
    final shownText = !_expanded && isLong
        ? '${text.substring(0, 160)}…'
        : text;
    final score = _toInt(review['score']) ?? 0;
    final likes = (_toInt(review['likes']) ?? 0) + (_liked ? 1 : 0);
    final comments = _toInt(review['comments']) ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
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
              const CircleAvatar(
                radius: 18,
                backgroundColor: _charcoal,
                child: Icon(Icons.person, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  review['username'] as String? ?? 'Listener',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _charcoal,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: scorePalette(score),
                  borderRadius: BorderRadius.circular(16),
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
            shownText,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.45,
              color: _charcoal.withValues(alpha: 0.7),
            ),
          ),
          if (isLong)
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
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => setState(() => _liked = !_liked),
                icon: Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  size: 19,
                  color: _liked ? Colors.red : _grey,
                ),
              ),
              Text(
                '$likes',
                style: GoogleFonts.inter(fontSize: 12, color: _grey),
              ),
              const SizedBox(width: 18),
              const Icon(Icons.chat_bubble_outline, size: 17, color: _grey),
              const SizedBox(width: 6),
              Text(
                '$comments',
                style: GoogleFonts.inter(fontSize: 12, color: _grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _cover(String url) => url.isEmpty
    ? const ColoredBox(color: _placeholder)
    : CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => const ColoredBox(color: _placeholder),
        errorWidget: (_, _, _) => const ColoredBox(color: _placeholder),
      );

Widget _cardHeading(String text) => Text(
  text,
  style: GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: _charcoal,
  ),
);

List<String> _stringList(Object? value) => value is Iterable
    ? value.whereType<String>().where((item) => item.trim().isNotEmpty).toList()
    : const [];

DateTime? _dateTime(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _formatReleaseDate(DateTime date) {
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
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

int? _toInt(Object? value) => value is num ? value.round() : null;
double? _toDouble(Object? value) => value is num ? value.toDouble() : null;

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
