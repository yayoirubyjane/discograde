import 'package:discograde/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  testWidgets('splash displays the Discograde logo', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('DISCO'), findsOneWidget);
    expect(find.text('GRADE'), findsOneWidget);
    expect(find.text('RATE  ·  REVIEW  ·  DISCUSS'), findsOneWidget);
  });
}
