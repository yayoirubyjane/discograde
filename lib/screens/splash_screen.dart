import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _splashRed = Color(0xFFC90022);
const _splashBlue = Color(0xFF0756A5);

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: DiscogradeSplashLogo(),
            ),
          ),
        ),
      );
}

class DiscogradeSplashLogo extends StatelessWidget {
  const DiscogradeSplashLogo({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final availableHeightWidth = constraints.maxHeight * 1.12;
          final width = math
              .min(constraints.maxWidth, availableHeightWidth)
              .clamp(220.0, 720.0)
              .toDouble();
          final wordSize = width * 0.205;
          final deckHeight = width * 0.43;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'RATE  ·  REVIEW  ·  DISCUSS',
                style: GoogleFonts.inter(
                  color: const Color(0xFF444649),
                  fontSize: width * 0.034,
                  fontWeight: FontWeight.w500,
                  letterSpacing: width * 0.006,
                ),
              ),
              SizedBox(height: width * 0.025),
              SizedBox(
                width: width,
                height: wordSize * 2 + deckHeight * 0.68,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _WordmarkLine(text: 'DISCO', color: _splashRed, size: wordSize),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _WordmarkLine(text: 'GRADE', color: _splashBlue, size: wordSize),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: wordSize * 0.75,
                      height: deckHeight,
                      child: CustomPaint(painter: _TurntablePainter()),
                    ),
                  ],
                ),
              ),
              SizedBox(height: width * 0.055),
              Text(
                'YOUR ALBUMS.  YOUR SCORE.  YOUR PEOPLE.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: const Color(0xFF444649),
                  fontSize: width * 0.032,
                  fontWeight: FontWeight.w500,
                  letterSpacing: width * 0.003,
                ),
              ),
            ],
          );
        },
      );
}

class _WordmarkLine extends StatelessWidget {
  const _WordmarkLine({required this.text, required this.color, required this.size});

  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: GoogleFonts.inter(
            color: color,
            fontSize: size,
            fontWeight: FontWeight.w900,
            height: 0.92,
            letterSpacing: -size * 0.035,
          ),
        ),
      );
}

class _TurntablePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final deck = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height * 0.11),
    );
    canvas.drawRRect(deck, Paint()..color = const Color(0xFF3A3B3D));
    canvas.drawRRect(
      deck,
      Paint()
        ..color = const Color(0xFF85888A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.018,
    );

    final center = Offset(size.width * 0.405, size.height * 0.49);
    final radius = size.height * 0.43;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFE6E6E6));
    canvas.drawCircle(center, radius * 0.96, Paint()..color = const Color(0xFF383A3C));
    for (var i = 1; i <= 10; i++) {
      canvas.drawCircle(
        center,
        radius * (0.29 + i * 0.061),
        Paint()
          ..color = i.isEven ? const Color(0xFF8B8D8E) : const Color(0xFF5F6264)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * 0.006,
      );
    }
    canvas.drawCircle(center, radius * 0.24, Paint()..color = const Color(0xFFE8E8E8));
    canvas.drawCircle(center, radius * 0.065, Paint()..color = const Color(0xFF606366));
    canvas.drawCircle(center, radius * 0.025, Paint()..color = const Color(0xFFEBEBEB));

    final pivot = Offset(size.width * 0.82, size.height * 0.22);
    final armEnd = Offset(size.width * 0.64, size.height * 0.72);
    final armPaint = Paint()
      ..color = const Color(0xFFE8E8E8)
      ..strokeWidth = size.height * 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pivot, armEnd, armPaint);
    canvas.drawCircle(pivot, size.height * 0.095, Paint()..color = const Color(0xFFC7C9CA));
    canvas.drawCircle(pivot, size.height * 0.045, Paint()..color = const Color(0xFF4A4C4E));
    canvas.drawCircle(armEnd, size.height * 0.045, Paint()..color = const Color(0xFFEBEBEB));

    final controls = Paint()..color = const Color(0xFFBFC1C2);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(size.width * (0.78 + i * 0.07), size.height * 0.79),
        size.height * 0.045,
        controls,
      );
    }
    final slot = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.75, size.height * 0.9, size.width * 0.2, size.height * 0.025),
      Radius.circular(size.height * 0.02),
    );
    canvas.drawRRect(slot, Paint()..color = const Color(0xFFD4D5D6));
  }

  @override
  bool shouldRepaint(covariant _TurntablePainter oldDelegate) => false;
}
