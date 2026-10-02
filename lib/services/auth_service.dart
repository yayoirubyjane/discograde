import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_service.dart';

class AuthService {
  AuthService._();

  static Future<void>? _googleInitialization;
  static final Map<String, bool> _profileSetupCache = {};
  static bool _googleSignInInProgress = false;
  static bool get googleSignInInProgress => _googleSignInInProgress;

  static Future<void> signInWithEmail(String email, String password) async {
    await FirebaseService.auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<UserCredential> createAccount({
    required String username,
    required String email,
    required String password,
    List<String> favoriteGenres = const [],
    String? photoBase64,
  }) async {
    final credential = await FirebaseService.auth
        .createUserWithEmailAndPassword(email: email, password: password);
    final normalizedUsername = username.trim().toLowerCase();
    await credential.user?.updateDisplayName(normalizedUsername);
    await _ensureUserDocument(
      credential.user,
      displayName: normalizedUsername,
      username: normalizedUsername,
      favoriteGenres: favoriteGenres,
      photoBase64: photoBase64,
      profileSetupComplete: true,
    );
    if (credential.user != null) {
      _profileSetupCache[credential.user!.uid] = false;
    }
    return credential;
  }

  static Future<void> sendPasswordReset(String email) =>
      FirebaseService.auth.sendPasswordResetEmail(email: email);

  static Future<void> signInWithGoogle() async {
    _googleSignInInProgress = true;
    try {
      UserCredential result;
      if (kIsWeb) {
        result = await FirebaseService.auth.signInWithPopup(
          GoogleAuthProvider(),
        );
      } else {
        _googleInitialization ??= GoogleSignIn.instance.initialize();
        await _googleInitialization;
        final googleUser = await GoogleSignIn.instance.authenticate();
        final idToken = googleUser.authentication.idToken;
        if (idToken == null) {
          throw FirebaseAuthException(
            code: 'google-id-token-missing',
            message: 'Google did not return an ID token. Check your Android OAuth setup.',
          );
        }
        final credential = GoogleAuthProvider.credential(idToken: idToken);
        result = await FirebaseService.auth.signInWithCredential(credential);
      }

      final needsProfileSetup = result.additionalUserInfo?.isNewUser ?? false;
      await _ensureUserDocument(
        result.user,
        profileSetupComplete: !needsProfileSetup,
      );
      if (result.user != null) {
        if (needsProfileSetup) {
          _profileSetupCache[result.user!.uid] = true;
        } else {
          _profileSetupCache.remove(result.user!.uid);
        }
      }
    } finally {
      _googleSignInInProgress = false;
    }
  }

  static Future<bool> needsProfileSetup(String uid) async {
    final isGoogleAccount =
        FirebaseService.auth.currentUser?.providerData.any(
          (provider) => provider.providerId == 'google.com',
        ) ??
        false;
    final cached = _profileSetupCache[uid];
    if (cached == true || (cached == false && !isGoogleAccount)) {
      return cached!;
    }
    final snapshot = await FirebaseService.firestore
        .collection('users')
        .doc(uid)
        .get();
    final profileData = snapshot.data();
    // Google profiles must pass this setup at least once. The version marker
    // also catches profiles created by earlier builds that used a generated
    // handle but did not show the profile step.
    final setupVersion = profileData?['profileSetupVersion'];
    final hasCompletedGoogleSetup = setupVersion is num && setupVersion >= 1;
    final needed =
        profileData?['profileSetupComplete'] == false ||
        (isGoogleAccount && !hasCompletedGoogleSetup);
    _profileSetupCache[uid] = needed;
    return needed;
  }

  static Future<void> completeGoogleProfile({
    required String username,
    required List<String> favoriteGenres,
    String? photoBase64,
  }) async {
    final user = FirebaseService.auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Sign in again to finish setting up your profile.',
      );
    }
    final normalizedUsername = username.trim().toLowerCase();
    await user.updateDisplayName(normalizedUsername);
    final fields = <String, dynamic>{
      'displayName': normalizedUsername,
      'handle': normalizedUsername,
      'email': user.email,
      'favoriteGenres': favoriteGenres,
      'profileSetupComplete': true,
      'profileSetupVersion': 1,
    };
    if (photoBase64 != null) fields['photoBase64'] = photoBase64;
    await FirebaseService.firestore
        .collection('users')
        .doc(user.uid)
        .set(fields, SetOptions(merge: true));
    _profileSetupCache[user.uid] = false;
  }

  static Future<void> signOut() async {
    await FirebaseService.auth.signOut();
    if (!kIsWeb) {
      _googleInitialization ??= GoogleSignIn.instance.initialize();
      await _googleInitialization;
      await GoogleSignIn.instance.signOut();
    }
  }

  static Future<void> _ensureUserDocument(
    User? user, {
    String? displayName,
    String? username,
    List<String> favoriteGenres = const [],
    String? photoBase64,
    bool profileSetupComplete = true,
  }) async {
    if (user == null) return;
    final ref = FirebaseService.firestore.collection('users').doc(user.uid);
    final existing = await ref.get();
    if (existing.exists) return;

    final name = (displayName ?? user.displayName ?? '').trim();
    final handle = username ?? _usernameFrom(name);
    final fields = <String, dynamic>{
      // Keep the legacy field aligned with the username for older clients.
      'displayName': handle,
      'handle': handle,
      'email': user.email,
      'favoriteGenres': favoriteGenres,
      'ratingCount': 0,
      'reviewCount': 0,
      'listCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'profileSetupComplete': profileSetupComplete,
    };
    if (photoBase64 != null) fields['photoBase64'] = photoBase64;
    await ref.set({...fields});
  }

  static String _usernameFrom(String name) {
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return normalized.length >= 3 ? normalized : 'listener';
  }

  static String suggestUsername(String name) => _usernameFrom(name);
}
