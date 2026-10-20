import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/mock_data.dart';
import '../routes.dart';
import '../services/auth.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../widgets/shell.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _otp = false;
  bool _busy = false;
  String? _phoneError, _otpError;
  final _phone = TextEditingController();
  final _codes = List.generate(4, (_) => TextEditingController());
  final _nodes = List.generate(4, (_) => FocusNode());
  int _resend = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Live sign-in finishes outside this screen (Google in the browser, or an
    // email link) — move on as soon as the session arrives.
    AuraStore.i.addListener(_onStore);
  }

  void _onStore() {
    if (!mounted || !AuraStore.i.live) return;
    if (AuraStore.i.authed && !AuraStore.i.guest && AuthService.i.signedIn) {
      AuraStore.i.removeListener(_onStore);
      _go();
    }
  }

  @override
  void dispose() {
    AuraStore.i.removeListener(_onStore);
    _timer?.cancel();
    _phone.dispose();
    for (final c in _codes) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _go() => Navigator.of(context).pushNamedAndRemoveUntil(Routes.main, (_) => false);

  void _startTimer() {
    _resend = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resend = (_resend - 1).clamp(0, 30));
      if (_resend == 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^03\d{9}$').hasMatch(digits)) {
      setState(() => _phoneError = 'Enter a valid Pakistani mobile number, e.g. 0300 1234567');
      return;
    }
    setState(() {
      _phoneError = null;
      _busy = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _otp = true;
    });
    _startTimer();
    toast(context, 'Code sent by SMS (demo code: 1234)');
    _nodes[0].requestFocus();
  }

  Future<void> _verify() async {
    final code = _codes.map((c) => c.text).join();
    if (code != '1234') {
      setState(() => _otpError = 'That code is not right. For this demo, use 1234.');
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    AuraStore.i.signIn(name: AuraStore.i.profile.name, phone: _phone.text.replaceAll(RegExp(r'\D'), ''));
    toast(context, 'Welcome to Aura by HS ✨');
    _go();
  }

  Future<void> _google() async {
    if (AuraStore.i.live) {
      setState(() => _busy = true);
      try {
        await AuthService.i.google();
      } catch (e) {
        if (mounted) toast(context, 'Google sign-in could not start. Please try again.', error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final account = await showAuraSheet<(String, String)>(context, builder: (ctx) => const _GoogleChooser());
    if (account == null || !mounted) return;
    AuraStore.i.signIn(name: account.$1, email: account.$2);
    toast(context, 'Welcome, ${account.$1.split(' ').first} ✨');
    _go();
  }

  @override
  Widget build(BuildContext context) {
    return PhoneFrame(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SingleChildScrollView(
          child: Column(children: [
            SizedBox(
              height: 330,
              child: Stack(fit: StackFit.expand, children: [
                const AuraImage('$img/bride-hero.jpg', alignment: Alignment(0, -0.5)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x664A0E12), Color(0x00000000), AppColors.background],
                      stops: [0, 0.5, 1],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Logo(size: 46),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Aura by HS', style: AppText.display(size: 19, color: Colors.white)),
                        Text('BRIDAL · SALON · PHOTOGRAPHY', style: AppText.eyebrow(size: 9, color: AppColors.goldLight)),
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _otp ? _otpForm() : _startForm(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _startForm() => Column(key: const ValueKey('start'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Welcome', style: AppText.display(size: 30, color: AppColors.maroon)),
        const SizedBox(height: 4),
        Text('Sign in to book, pay and chat with your salon.', style: AppText.sans(size: 14, color: AppColors.mutedForeground)),
        // In demo mode the Google sheet and the SMS code are simulated, so say
        // so plainly — a convincing fake sign-in should never be mistaken for
        // the real thing.
        if (!AuraStore.i.live) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.science_outlined, size: 17, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Demo mode', style: AppText.sans(size: 13, weight: FontWeight.w700, color: AppColors.maroon)),
                  const SizedBox(height: 2),
                  Text(
                    'Sign-in is simulated and everything runs on sample data on this phone. '
                    'No real booking, payment or message is involved.',
                    style: AppText.sans(size: 12, color: AppColors.mutedForeground),
                  ),
                ]),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 22),
        Pressable(
          onTap: _google,
          child: Container(
            height: 54,
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.border), boxShadow: AppShadows.soft),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _GoogleG(),
              const SizedBox(width: 12),
              Text('Continue with Google', style: AppText.sans(size: 15, weight: FontWeight.w600)),
            ]),
          ),
        ),
        if (AuraStore.i.live) const _EmailSignIn() else ...[
        const SizedBox(height: 20),
        Row(children: [
          const Expanded(child: Divider()),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('or use your mobile', style: AppText.sans(size: 12, color: AppColors.mutedForeground))),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: 18),
        Text('Mobile number', style: AppText.sans(size: 13, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
          style: AppText.sans(size: 15),
          decoration: InputDecoration(
            hintText: '0300 1234567',
            errorText: _phoneError,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.phone_iphone_rounded, size: 19, color: AppColors.mutedForeground),
                const SizedBox(width: 6),
                Text('+92', style: AppText.sans(size: 14, weight: FontWeight.w600, color: AppColors.mutedForeground)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Btn(label: _busy ? 'Sending code…' : 'Send code', loading: _busy, onTap: _sendCode),
        ],
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () {
              AuraStore.i.continueAsGuest();
              _go();
            },
            child: Text('Browse as guest', style: AppText.sans(size: 14, weight: FontWeight.w600, color: AppColors.mutedForeground, decoration: TextDecoration.underline)),
          ),
        ),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.verified_user_outlined, size: 15, color: AppColors.gold),
          const SizedBox(width: 8),
          Expanded(child: Text('By continuing you agree to Aura by HS’s Terms and Privacy Policy. We never share your number.', style: AppText.sans(size: 11.5, color: AppColors.mutedForeground, height: 1.4))),
        ]),
      ]);

  Widget _otpForm() => Column(key: const ValueKey('otp'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Enter the code', style: AppText.display(size: 28, color: AppColors.maroon)),
        const SizedBox(height: 4),
        Text('Sent by SMS to ${_phone.text}', style: AppText.sans(size: 14, color: AppColors.mutedForeground)),
        const SizedBox(height: 22),
        Row(children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _codes[i],
                focusNode: _nodes[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: AppText.display(size: 26),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.symmetric(vertical: 18)),
                onChanged: (v) {
                  setState(() => _otpError = null);
                  if (v.isNotEmpty && i < 3) _nodes[i + 1].requestFocus();
                  if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
                  if (_codes.every((c) => c.text.isNotEmpty)) _verify();
                },
              ),
            ),
          ],
        ]),
        if (_otpError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_otpError!, style: AppText.sans(size: 12, color: AppColors.destructive))),
        const SizedBox(height: 18),
        Btn(label: _busy ? 'Verifying…' : 'Verify & continue', loading: _busy, onTap: _verify),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton(onPressed: () => setState(() => _otp = false), child: Text('Change number', style: AppText.sans(color: AppColors.mutedForeground))),
          TextButton(
            onPressed: _resend > 0
                ? null
                : () {
                    _startTimer();
                    toast(context, 'New code sent (demo code: 1234)');
                  },
            child: Text(_resend > 0 ? 'Resend in ${_resend}s' : 'Resend code', style: AppText.sans(weight: FontWeight.w600, color: _resend > 0 ? AppColors.mutedForeground : AppColors.maroon)),
          ),
        ]),
      ]);
}

class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => SizedBox(width: 22, height: 22, child: CustomPaint(painter: _GPainter()));
}

/// The four-colour Google "G", drawn so no image asset is needed.
class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s - stroke, s - stroke);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, -0.25, -1.35, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, -1.6, -1.45, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, 3.05, -0.95, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 2.1, -1.35, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, 0.75, -1.0, false, p(const Color(0xFF4285F4)));
    final bar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(Rect.fromLTWH(s * 0.5, s * 0.42, s * 0.5 - stroke / 4, stroke), bar);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Google-style account chooser. In the live app this is Google's own sheet
/// (Supabase OAuth); the flow and the information shown are the same.
class _GoogleChooser extends StatefulWidget {
  const _GoogleChooser();
  @override
  State<_GoogleChooser> createState() => _GoogleChooserState();
}

class _GoogleChooserState extends State<_GoogleChooser> {
  final _email = TextEditingController();
  String? _busy;
  static const _accounts = [('Ayesha Rizwan', 'ayesha.rizwan@gmail.com'), ('Mahnoor Khan', 'mahnoor.k@gmail.com')];

  Future<void> _pick((String, String) a) async {
    setState(() => _busy = a.$2);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (mounted) Navigator.pop(context, a);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const _GoogleG(),
        const SizedBox(width: 10),
        Text('Sign in with Google', style: AppText.sans(size: 15, weight: FontWeight.w500, color: const Color(0xFF3C4043))),
      ]),
      const SizedBox(height: 16),
      Text('Choose an account', style: AppText.sans(size: 20, color: const Color(0xFF202124))),
      const SizedBox(height: 2),
      RichText(
        text: TextSpan(style: AppText.sans(size: 13, color: const Color(0xFF5F6368)), children: [
          const TextSpan(text: 'to continue to '),
          TextSpan(text: 'Aura by HS', style: AppText.sans(size: 13, weight: FontWeight.w600, color: AppColors.maroon)),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFDADCE0))),
        child: Column(children: [
          for (final a in _accounts) ...[
            ListTile(
              onTap: _busy == null ? () => _pick(a) : null,
              leading: CircleAvatar(backgroundColor: AppColors.maroon, child: Text(a.$1[0], style: AppText.sans(weight: FontWeight.w600, color: Colors.white))),
              title: Text(a.$1, style: AppText.sans(size: 14, weight: FontWeight.w500, color: const Color(0xFF202124))),
              subtitle: Text(a.$2, style: AppText.sans(size: 12.5, color: const Color(0xFF5F6368))),
              trailing: _busy == a.$2 ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4285F4))) : null,
            ),
            if (a != _accounts.last) const Divider(height: 1, color: Color(0xFFEDEDED)),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'Use another account'),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A73E8), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
          onPressed: () {
            final e = _email.text.trim();
            if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(e)) {
              toast(context, 'Enter a valid email address', error: true);
              return;
            }
            final name = e.split('@').first.replaceAll(RegExp(r'[._]'), ' ').split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
            _pick((name, e));
          },
          child: const Text('Next'),
        ),
      ]),
      const SizedBox(height: 14),
      Text('To continue, Google will share your name, email address and profile picture with Aura by HS.', style: AppText.sans(size: 11.5, color: const Color(0xFF5F6368), height: 1.4)),
    ]);
  }
}


/// Email sign-in for the connected app: sign in, create an account (a
/// verification link is emailed), or reset a forgotten password.
class _EmailSignIn extends StatefulWidget {
  const _EmailSignIn();
  @override
  State<_EmailSignIn> createState() => _EmailSignInState();
}

enum _Mode { signIn, signUp, forgot, checkEmail }

class _EmailSignInState extends State<_EmailSignIn> {
  _Mode _mode = _Mode.signIn;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;
  String _sentTo = '';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _emailOk => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_emailOk) return setState(() => _error = 'Enter a valid email address.');
    if (_mode == _Mode.signUp && _name.text.trim().length < 2) return setState(() => _error = 'Enter your full name.');
    if (_mode != _Mode.forgot && _password.text.length < 6) return setState(() => _error = 'Use a password of at least 6 characters.');
    setState(() => _busy = true);
    try {
      switch (_mode) {
        case _Mode.signIn:
          await AuthService.i.signIn(_email.text, _password.text);
        case _Mode.signUp:
          final signedIn = await AuthService.i.signUp(name: _name.text, email: _email.text, password: _password.text);
          if (!signedIn) {
            _sentTo = _email.text.trim();
            _mode = _Mode.checkEmail;
          }
        case _Mode.forgot:
          await AuthService.i.sendPasswordReset(_email.text);
          _sentTo = _email.text.trim();
          _mode = _Mode.checkEmail;
        case _Mode.checkEmail:
          break;
      }
    } on AuthFailure catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not reach the server. Check your internet and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == _Mode.checkEmail) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 22),
        AuraCard(
          color: AppColors.goldSoft,
          borderColor: Colors.transparent,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.mark_email_read_outlined, color: AppColors.maroon, size: 30),
            const SizedBox(height: 8),
            Text('Check your email', style: AppText.display(size: 20)),
            const SizedBox(height: 4),
            Text('We sent a link to $_sentTo. Open it on this phone to continue — it signs you in automatically.', style: AppText.sans(size: 13.5, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 12),
        Btn(
          label: 'Resend the link',
          variant: BtnVariant.outline,
          onTap: () async {
            try {
              await AuthService.i.resendVerification(_sentTo);
              if (context.mounted) toast(context, 'Sent again.');
            } on AuthFailure catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          },
        ),
        TextButton(onPressed: () => setState(() => _mode = _Mode.signIn), child: Text('Back to sign in', style: AppText.sans(color: AppColors.mutedForeground))),
      ]);
    }
    final title = switch (_mode) { _Mode.signUp => 'Create account', _Mode.forgot => 'Reset password', _ => 'Sign in' };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 20),
      Row(children: [
        const Expanded(child: Divider()),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('or with email', style: AppText.sans(size: 12, color: AppColors.mutedForeground))),
        const Expanded(child: Divider()),
      ]),
      const SizedBox(height: 14),
      if (_mode != _Mode.forgot)
        Row(children: [
          Expanded(child: ChipPill('Sign in', selected: _mode == _Mode.signIn, onTap: () => setState(() => _mode = _Mode.signIn))),
          const SizedBox(width: 8),
          Expanded(child: ChipPill('Create account', selected: _mode == _Mode.signUp, onTap: () => setState(() => _mode = _Mode.signUp))),
        ]),
      if (_mode == _Mode.forgot) Text('We’ll email you a link to choose a new password.', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
      const SizedBox(height: 12),
      if (_mode == _Mode.signUp) ...[
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded))),
        const SizedBox(height: 10),
      ],
      TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(hintText: 'Email address', prefixIcon: Icon(Icons.alternate_email_rounded))),
      if (_mode != _Mode.forgot) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: _hide,
          autofillHints: [_mode == _Mode.signUp ? AutofillHints.newPassword : AutofillHints.password],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Password (6+ characters)',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
          ),
        ),
      ],
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: AppText.sans(size: 12.5, color: AppColors.destructive))),
      const SizedBox(height: 14),
      Btn(label: _mode == _Mode.forgot ? 'Send reset link' : title, loading: _busy, onTap: _submit),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (_mode == _Mode.signIn)
          TextButton(onPressed: () => setState(() => _mode = _Mode.forgot), child: Text('Forgot password?', style: AppText.sans(weight: FontWeight.w600, color: AppColors.maroon))),
        if (_mode == _Mode.forgot)
          TextButton(onPressed: () => setState(() => _mode = _Mode.signIn), child: Text('Back to sign in', style: AppText.sans(color: AppColors.mutedForeground))),
      ]),
    ]);
  }
}

/// Shown when the customer opens a password-reset link from their email.
class NewPasswordSheet extends StatefulWidget {
  const NewPasswordSheet({super.key});
  @override
  State<NewPasswordSheet> createState() => _NewPasswordSheetState();
}

class _NewPasswordSheetState extends State<NewPasswordSheet> {
  final _p = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Choose a new password', style: AppText.display(size: 22)),
        const SizedBox(height: 12),
        TextField(controller: _p, obscureText: true, decoration: const InputDecoration(hintText: 'New password (6+ characters)')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: AppText.sans(size: 12.5, color: AppColors.destructive))),
        const SizedBox(height: 14),
        Btn(
          label: 'Save password',
          loading: _busy,
          onTap: () async {
            if (_p.text.length < 6) return setState(() => _error = 'Use at least 6 characters.');
            setState(() => _busy = true);
            try {
              await AuthService.i.setNewPassword(_p.text);
              if (context.mounted) {
                Navigator.pop(context);
                toast(context, 'Password changed ✨');
              }
            } on AuthFailure catch (e) {
              setState(() {
                _busy = false;
                _error = e.message;
              });
            }
          },
        ),
      ]);
}
