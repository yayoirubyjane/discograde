import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AiDiscoveryService {
  AiDiscoveryService._();

  static final AiDiscoveryService instance = AiDiscoveryService._();
  static const _workerUrl = String.fromEnvironment('CLOUDFLARE_WORKER_URL');

  Future<Map<String, dynamic>> sendMessage({
    required String prompt,
    required List<Map<String, dynamic>> catalog,
    required Map<String, dynamic> profile,
    required List<Map<String, String>> history,
  }) async {
    if (_workerUrl.isEmpty) {
      throw StateError(
        'Cloudflare AI is not configured. Run the app with '
        '--dart-define=CLOUDFLARE_WORKER_URL=https://your-worker.workers.dev.',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in to use album discovery.');
    }

    final idToken = await user.getIdToken();
    final appCheckToken = await FirebaseAppCheck.instance.getToken();
    if (idToken == null || appCheckToken == null) {
      throw StateError(
        'Could not verify this app with Firebase. Restart the app and try again.',
      );
    }

    final response = await http
        .post(
          Uri.parse(_workerUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
            'X-Firebase-AppCheck': appCheckToken,
          },
          body: jsonEncode({
            'prompt': prompt,
            'catalog': catalog,
            'profile': profile,
            'history': history,
          }),
        )
        .timeout(const Duration(seconds: 45));

    final decoded = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded?['error'] as String?;
      throw StateError(
        message ?? 'Cloudflare AI returned HTTP ${response.statusCode}.',
      );
    }
    if (decoded == null) {
      throw const FormatException('Cloudflare AI returned an invalid response.');
    }
    return decoded;
  }

  Map<String, dynamic>? _decodeObject(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } on FormatException catch (error) {
      if (kDebugMode) debugPrint('Invalid Cloudflare AI response: $error');
      return null;
    }
  }
}
