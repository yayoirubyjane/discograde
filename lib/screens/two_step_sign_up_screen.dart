import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';

const _page = Color(0xFFF5F5F5);
const _card = Colors.white;
const _ink = Color(0xFF3F3F3F);
const _teal = Color(0xFF0E8A8A);
const _navy = Color(0xFF0B4B8B);
const _red = Color(0xFFBA011A);
const _muted = Color(0xFF858585);
const _line = Color(0xFFE2E2E2);

const _genres = [
  'Pop',
  'Rock',
  'Hip-Hop',
  'R&B',
  'Electronic',
  'Jazz',
  'Classical',
  'Metal',
  'Country',
  'Indie',
  'Folk',
  'Latin',
];

class TwoStepSignUpScreen extends StatefulWidget {
  const TwoStepSignUpScreen({super.key, this.profileOnly = false});

  final bool profileOnly;

  @override
  State<TwoStepSignUpScreen> createState() => _TwoStepSignUpScreenState();
}

class _TwoStepSignUpScreenState extends State<TwoStepSignUpScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _username = TextEditingController();
  final _aboutMe = TextEditingController();
  final _picker = ImagePicker();

  int _step = 0;
  bool _confirmTouched = false;
  bool _emailTouched = false;
  bool _usernameTouched = false;
  bool _busy = false;
  Uint8List? _avatarBytes;
  final Set<String> _selectedGenres = {};

  @override
  void initState() {
    super.initState();
    if (widget.profileOnly) {
      final user = FirebaseAuth.instance.currentUser;
      _step = 1;
      _email.text = user?.email ?? '';
      _username.text = AuthService.suggestUsername(
        user?.displayName ?? user?.email?.split('@').first ?? '',
      );
    }
    _email.addListener(_refresh);
    _password.addListener(_refresh);
    _confirm.addListener(_refresh);
    _username.addListener(_refresh);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _username.dispose();
    _aboutMe.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _validEmail => RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  ).hasMatch(_email.text.trim());

  bool get _passwordValid => _password.text.length >= 6;
  bool get _passwordsMatch =>
      _confirm.text.isNotEmpty && _confirm.text == _password.text;
  bool get _canContinue => _validEmail && _passwordValid && _passwordsMatch;
  bool get _usernameValid =>
      RegExp(r'^[a-z0-9_]{3,}$').hasMatch(_username.text);

  String? get _confirmError {
    if (!_confirmTouched) return null;
    if (_confirm.text.isEmpty) return 'Confirm your password';
    if (_confirm.text != _password.text) return 'Passwords do not match';
    return null;
  }

  String? get _usernameError {
    if (!_usernameTouched) return null;
    if (_username.text.isEmpty) return 'Username is required';
    if (_username.text.length < 3) return 'Use at least 3 characters';
    if (!_usernameValid) {
      return 'Use lowercase letters, numbers, or underscores';
    }
    return null;
  }

  String? get _emailError {
    if (!_emailTouched) return null;
    if (_email.text.trim().isEmpty) return 'Email is required';
    if (!_validEmail) return 'Enter a valid email address';
    return null;
  }

  void _continue() {
    // The steps share state in this screen. A refresh resets to step one, so
    // there is no profile route that can be opened without its email/password.
    if (!_canContinue) return;
    FocusScope.of(context).unfocus();
    _email.text = _email.text.trim();
    setState(() {
      _step = 1;
    });
  }

  void _editUsername(String value) {
    final normalized = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_]'),
      '',
    );
    if (normalized == value) return;
    _username.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  Future<void> _choosePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // Keep the encoded avatar comfortably below Firestore's 1 MiB document
      // ceiling while retaining a useful preview size.
      if (bytes.length > 600 * 1024) {
        _toast('That photo is too large. Choose a smaller image.');
        return;
      }
      if (mounted) setState(() => _avatarBytes = bytes);
    } catch (_) {
      _toast('Could not open that photo. Please try another image.');
    }
  }

  Future<void> _createAccount() async {
    if (!_usernameValid || _busy) return;
    setState(() => _busy = true);
    try {
      if (widget.profileOnly) {
        await AuthService.completeGoogleProfile(
          username: _username.text,
          favoriteGenres: _selectedGenres.toList(),
          aboutMe: _aboutMe.text.trim(),
          photoBase64: _avatarBytes == null
              ? null
              : base64Encode(_avatarBytes!),
        );
      } else {
        await AuthService.createAccount(
          email: _email.text.trim(),
          password: _password.text,
          username: _username.text,
          favoriteGenres: _selectedGenres.toList(),
          aboutMe: _aboutMe.text.trim(),
          photoBase64: _avatarBytes == null
              ? null
              : base64Encode(_avatarBytes!),
        );
      }
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        _toast(
          'An account already uses this email. Log in with Google or your existing sign-in method.',
        );
        if (mounted) context.go('/login');
        return;
      }
      _toast(switch (error.code) {
        'weak-password' => 'Choose a stronger password.',
        'invalid-email' => 'That email address is not valid.',
        _ => error.message ?? 'Could not create the account.',
      });
    } catch (error) {
      _toast('Could not save your profile: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Email sign-up keeps both steps in this screen; Google onboarding opens
    // directly at the same profile step with the authenticated email filled in.
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step == 1 && !widget.profileOnly)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _step = 0),
                        icon: const Icon(Icons.arrow_back, size: 19),
                        label: const Text('Back'),
                        style: TextButton.styleFrom(
                          foregroundColor: _teal,
                          minimumSize: const Size(44, 44),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                  Center(
                    child: SizedBox(
                      height: 112,
                      child: Image.asset(
                        'assets/assets/AQUINO CCE106 LOGO CROPPED.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Text(
                          'DISCOGRADE',
                          style: GoogleFonts.inter(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: 2.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _stepIndicator(),
                  const SizedBox(height: 20),
                  _step == 0 ? _credentialsCard() : _profileCard(),
                  const SizedBox(height: 18),
                  if (_step == 0)
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: _bodyStyle(),
                          ),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            style: TextButton.styleFrom(
                              foregroundColor: _teal,
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            child: Text(
                              'Log in',
                              style: GoogleFonts.inter(
                                color: _teal,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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

  Widget _stepIndicator() => Row(
    children: [
      _stepDot(0, 'Credentials'),
      Expanded(child: Container(height: 1, color: _line)),
      _stepDot(1, 'Profile'),
    ],
  );

  Widget _stepDot(int step, String label) {
    final active = _step == step;
    final complete = _step > step;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active || complete ? _teal : _card,
            shape: BoxShape.circle,
            border: Border.all(color: active || complete ? _teal : _line),
          ),
          child: Center(
            child: complete
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '${step + 1}',
                    style: GoogleFonts.inter(
                      color: active ? Colors.white : _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            color: active ? _ink : _muted,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        if (step == 0) const SizedBox(width: 14),
      ],
    );
  }

  Widget _credentialsCard() => _formCard(
    children: [
      _title('Create your account', 'Start with your email and password.'),
      const SizedBox(height: 22),
      _label('EMAIL'),
      const SizedBox(height: 6),
      _textField(
        controller: _email,
        hint: 'you@example.com',
        semanticLabel: 'Email',
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        onChanged: (_) => _emailTouched = true,
        error: _emailError,
      ),
      const SizedBox(height: 16),
      _label('PASSWORD'),
      const SizedBox(height: 6),
      _textField(
        controller: _password,
        hint: 'Create a password',
        semanticLabel: 'Password',
        obscureText: !_visiblePassword,
        textInputAction: TextInputAction.next,
        suffix: IconButton(
          tooltip: _visiblePassword ? 'Hide password' : 'Show password',
          onPressed: () => setState(() => _visiblePassword = !_visiblePassword),
          icon: Icon(
            _visiblePassword ? Icons.visibility_off : Icons.visibility,
            color: _muted,
          ),
        ),
      ),
      const SizedBox(height: 16),
      _label('CONFIRM PASSWORD'),
      const SizedBox(height: 6),
      _textField(
        controller: _confirm,
        hint: 'Enter your password again',
        semanticLabel: 'Confirm password',
        obscureText: !_visibleConfirm,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() => _confirmTouched = true),
        onTap: () => setState(() => _confirmTouched = true),
        suffix: IconButton(
          tooltip: _visibleConfirm ? 'Hide password' : 'Show password',
          onPressed: () => setState(() => _visibleConfirm = !_visibleConfirm),
          icon: Icon(
            _visibleConfirm ? Icons.visibility_off : Icons.visibility,
            color: _muted,
          ),
        ),
        error: _confirmError,
      ),
      const SizedBox(height: 16),
      _label('ABOUT ME  ·  OPTIONAL'),
      const SizedBox(height: 6),
      _textField(
        controller: _aboutMe,
        hint: 'Tell people a little about yourself',
        semanticLabel: 'About Me',
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        minLines: 2,
        maxLines: 3,
        maxLength: 200,
      ),
      const SizedBox(height: 22),
      _primaryButton(
        label: 'Continue',
        enabled: _canContinue,
        onPressed: _continue,
      ),
    ],
  );

  bool _visiblePassword = false;
  bool _visibleConfirm = false;

  Widget _profileCard() => _formCard(
    children: [
      _title(
        widget.profileOnly ? 'Complete your profile' : 'Set up your profile',
        widget.profileOnly
            ? 'Choose a username and add your profile details to continue.'
            : 'You can change these details later.',
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: _page,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: _teal, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _email.text,
                style: GoogleFonts.inter(fontSize: 13, color: _ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 17),
      _label('USERNAME'),
      const SizedBox(height: 6),
      _textField(
        controller: _username,
        hint: 'yourname',
        semanticLabel: 'Username',
        textInputAction: TextInputAction.done,
        prefix: Text(
          '@',
          style: GoogleFonts.inter(color: _teal, fontWeight: FontWeight.w700),
        ),
        onChanged: (value) {
          _usernameTouched = true;
          _editUsername(value);
        },
        onTap: () => setState(() => _usernameTouched = true),
        error: _usernameError,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          '3+ characters · lowercase letters, numbers, and _',
          style: GoogleFonts.inter(fontSize: 11, color: _muted),
        ),
      ),
      const SizedBox(height: 19),
      if (widget.profileOnly) ...[
        _label('ABOUT ME  ·  OPTIONAL'),
        const SizedBox(height: 6),
        _textField(
          controller: _aboutMe,
          hint: 'Tell people a little about yourself',
          semanticLabel: 'About Me',
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          minLines: 2,
          maxLines: 3,
          maxLength: 200,
        ),
      ],
      const SizedBox(height: 19),
      _label('PROFILE PHOTO  ·  OPTIONAL'),
      const SizedBox(height: 10),
      Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: _navy,
            foregroundImage: _avatarBytes == null
                ? null
                : MemoryImage(_avatarBytes!),
            child: _avatarBytes == null
                ? (_username.text.trim().isEmpty
                      ? const Icon(
                          Icons.person_outline,
                          color: Colors.white,
                          size: 30,
                        )
                      : Text(
                          _username.text.trim().substring(0, 1).toUpperCase(),
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                          ),
                        ))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _choosePhoto,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(
                _avatarBytes == null ? 'Choose a photo' : 'Change photo',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                minimumSize: const Size(44, 46),
                side: const BorderSide(color: _teal),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_avatarBytes != null) ...[
            const SizedBox(width: 7),
            IconButton(
              tooltip: 'Remove photo',
              onPressed: () => setState(() => _avatarBytes = null),
              icon: const Icon(Icons.close, color: _red),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ],
      ),
      const SizedBox(height: 19),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _label('FAVORITE GENRES  ·  OPTIONAL')),
          Text(
            '${_selectedGenres.length}/5',
            style: GoogleFonts.inter(fontSize: 11, color: _muted),
          ),
        ],
      ),
      const SizedBox(height: 9),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _genres.map((genre) {
          final selected = _selectedGenres.contains(genre);
          return Semantics(
            button: true,
            selected: selected,
            label: '$genre genre',
            child: FilterChip(
              label: Text(genre),
              selected: selected,
              showCheckmark: false,
              onSelected: (value) {
                if (value && _selectedGenres.length >= 5) {
                  _toast('Choose up to 5 favorite genres.');
                  return;
                }
                setState(() {
                  if (value) {
                    _selectedGenres.add(genre);
                  } else {
                    _selectedGenres.remove(genre);
                  }
                });
              },
              labelStyle: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _ink,
              ),
              backgroundColor: _page,
              selectedColor: _teal,
              side: BorderSide(color: selected ? _teal : _ink, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 24),
      _primaryButton(
        label: _busy
            ? (widget.profileOnly ? 'Saving profile…' : 'Creating account…')
            : (widget.profileOnly ? 'Save and continue' : 'Create account'),
        enabled: _usernameValid && !_busy,
        onPressed: _createAccount,
        busy: _busy,
      ),
    ],
  );

  Widget _formCard({required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line, width: 0.8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _title(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: _ink,
        ),
      ),
      const SizedBox(height: 5),
      Text(subtitle, style: _bodyStyle()),
    ],
  );

  Widget _label(String text) => Text(
    text,
    style: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.45,
      color: _ink,
    ),
  );

  TextStyle _bodyStyle() =>
      GoogleFonts.inter(fontSize: 13, color: _muted, height: 1.45);

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    String? semanticLabel,
    Iterable<String>? autofillHints,
    bool obscureText = false,
    int? minLines,
    int? maxLines,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.none,
    Widget? suffix,
    Widget? prefix,
    String? error,
    VoidCallback? onTap,
    ValueChanged<String>? onChanged,
  }) => Semantics(
    label: semanticLabel,
    textField: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          obscureText: obscureText,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLength,
          textCapitalization: textCapitalization,
          onTap: onTap,
          onChanged: onChanged,
          style: GoogleFonts.inter(fontSize: 14, color: _ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 13,
              color: _muted.withValues(alpha: 0.65),
            ),
            prefix: prefix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: prefix,
                  ),
            suffixIcon: suffix,
            filled: true,
            fillColor: _page,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            errorText: error,
            errorStyle: GoogleFonts.inter(fontSize: 11, color: _red),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: error == null ? _line : _red),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error == null ? _teal : _red,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _red),
            ),
          ),
        ),
        if (error != null)
          Semantics(liveRegion: true, child: const SizedBox.shrink()),
      ],
    ),
  );

  Widget _primaryButton({
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
    bool busy = false,
  }) => SizedBox(
    height: 50,
    child: FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: _teal,
        disabledBackgroundColor: const Color(0xFFC5D5D5),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: busy
          ? const SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
    ),
  );
}
