import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth_service.dart';

const _loginInk = Color(0xFF3F3F3F);
const _loginTeal = Color(0xFF0E8A8A);
const _loginMuted = Color(0xFF858585);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await _runAuth(
      () => AuthService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      ),
    );
  }

  Future<void> _googleLogin() async => _runAuth(() async {
    await AuthService.signInWithGoogle();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    final needsProfile = await AuthService.needsProfileSetup(user.uid);
    if (mounted) context.go(needsProfile ? '/complete-profile' : '/home');
  });

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      _message('Enter your email address first.');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AuthService.sendPasswordReset(email);
      _message('If an account uses that email, a reset link has been sent.');
    } on FirebaseAuthException catch (error) {
      _message(_authError(error));
    } catch (_) {
      _message('Could not send the reset email. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      // The router handles the destination after sign-in and profile setup.
    } on FirebaseAuthException catch (error) {
      _message(_authError(error));
    } on GoogleSignInException catch (error) {
      final description = error.description;
      if (error.code == GoogleSignInExceptionCode.canceled &&
          (description == null || description.isEmpty)) {
        _message(
          'Google sign-in was canceled. If you selected an account, rebuild the app after updating google-services.json.',
        );
      } else {
        _message(
          'Google sign-in failed (${error.code.name})${description == null ? '' : ': $description'}',
        );
      }
    } on FirebaseException catch (error) {
      _message(
        'Firebase error (${error.code}): ${error.message ?? 'Please try again.'}',
      );
    } catch (error) {
      _message('Sign-in failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authError(FirebaseAuthException error) => switch (error.code) {
    'invalid-email' => 'That email address is not valid.',
    'user-disabled' => 'This account has been disabled.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'Email or password is incorrect.',
    'network-request-failed' => 'Check your internet connection and try again.',
    'account-exists-with-different-credential' =>
      'An account already exists with a different sign-in method.',
    _ => error.message ?? 'Sign-in failed. Please try again.',
  };

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          height: 168,
                          child: Image.asset(
                            'assets/assets/AQUINO CCE106 LOGO CROPPED.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Center(
                              child: Text(
                                'DISCOGRADE',
                                style: GoogleFonts.inter(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                  color: _loginInk,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Welcome',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: _loginInk,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _fieldLabel('EMAIL'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: _loginInk,
                        ),
                        decoration: _inputDecoration(
                          hintText: 'you@example.com',
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return 'Enter your email';
                          if (!email.contains('@')) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel('PASSWORD'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_passwordVisible,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _login(),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: _loginInk,
                        ),
                        decoration: _inputDecoration(hintText: '••••••••')
                            .copyWith(
                              suffixIcon: IconButton(
                                tooltip: _passwordVisible
                                    ? 'Hide password'
                                    : 'Show password',
                                onPressed: () => setState(
                                  () => _passwordVisible = !_passwordVisible,
                                ),
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: _loginMuted,
                                ),
                              ),
                            ),
                        validator: (value) => (value?.isEmpty ?? true)
                            ? 'Enter your password'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          style: TextButton.styleFrom(
                            foregroundColor: _loginTeal,
                          ),
                          child: Text(
                            'Forgot password?',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _busy ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: _loginInk,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Log In',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          const Expanded(
                            child: Divider(color: Color(0xFFD8D8D8)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              'or',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _loginMuted,
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(color: Color(0xFFD8D8D8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _googleLogin,
                          icon: Image.asset(
                            'assets/assets/g-logo.png',
                            width: 20,
                            height: 20,
                            fit: BoxFit.contain,
                          ),
                          label: Text(
                            'Continue with Google',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _loginInk,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFD4D4D4)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account?",
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _loginMuted,
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => context.push('/signup'),
                            style: TextButton.styleFrom(
                              foregroundColor: _loginTeal,
                            ),
                            child: Text(
                              'Sign Up',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _fieldLabel(String label) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: _loginMuted,
      ),
    ),
  );

  InputDecoration _inputDecoration({
    required String hintText,
  }) => InputDecoration(
    hintText: hintText,
    hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFC1C1C1)),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD4D4D4)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD4D4D4)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _loginTeal, width: 1.6),
    ),
  );
}
