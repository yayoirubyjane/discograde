import 'package:flutter/material.dart';

Color scorePalette(int score) {
  if (score >= 90) return const Color(0xFF2F9E58);
  if (score >= 75) return const Color(0xFFF0A533);
  if (score >= 60) return const Color(0xFFD5531F);
  return const Color(0xFFBA011A);
}
