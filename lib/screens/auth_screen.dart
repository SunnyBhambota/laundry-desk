import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/validators.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/laundry_scene.dart';

/// Glossy Login / Sign up with the "runaway" button: until every field is right,
/// tapping the button makes it jump to the other side of its dock.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _login = true;
  bool _showPw = false;
  bool _side = false;
  bool _agree = false;
  RunPhase _phase = RunPhase.idle;

  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _spw = TextEditingController();

  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void dispose() {
    for (final c in [_id, _pw, _name, _mobile, _email, _spw]) {
      c.dispose();
    }
    _glow.dispose();
    super.dispose();
  }

  List<bool> get _checks => _login
      ? [V.isLoginId(_id.text), V.isPassword(_pw.text)]
      : [V.isName(_name.text), V.isMobile(_mobile.text), V.isPassword(_spw.text), _agree];

  bool get _ready => _checks.every((c) => c);

  void _changed([String? _]) {
    setState(() {});
    if (_ready && !_glow.isAnimating) _glow.repeat(reverse: true);
    if (!_ready && _glow.isAnimating) _glow.stop();
  }

  void _dodge() {
    if (_phase != RunPhase.idle || _ready) return;
    setState(() => _side = !_side);
  }

  void _switchMode() {
    setState(() {
      _login = !_login;
      _side = false;
      _phase = RunPhase.idle;
    });
    _changed();
  }

  Future<void> _submit() async {
    if (!_ready) {
      _dodge();
      return;
    }
    if (_phase != RunPhase.idle) return;
    final app = context.read<AppState>();
    FocusScope.of(context).unfocus();
    setState(() => _phase = RunPhase.loading);
    try {
      final owner = _login
          ? await AuthService.instance.signIn(loginId: _id.text, password: _pw.text)
          : await AuthService.instance.register(
              name: _name.text,
              mobile: _mobile.text,
              password: _spw.text,
              email: V.isEmail(_email.text) ? _email.text : '',
            );
      if (!mounted) return;
      setState(() => _phase = RunPhase.done);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await app.signedInAs(owner);
    } on AuthError catch (e) {
      if (!mounted) return;
      setState(() => _phase = RunPhase.idle);
      toast(context, app.t('err.${e.code}'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = RunPhase.idle);
      toast(context, app.t('err.generic'));
    }
  }

  Future<void> _google() async {
    if (_phase != RunPhase.idle) return;
    final app = context.read<AppState>();
    setState(() => _phase = RunPhase.loading);
    try {
      final owner = await AuthService.instance.signInWithGoogle();
      if (!mounted) return;
      if (owner == null) {
        setState(() => _phase = RunPhase.idle);
        return;
      }
      setState(() => _phase = RunPhase.done);
      await app.signedInAs(owner);
    } on AuthError catch (e) {
      if (!mounted) return;
      setState(() => _phase = RunPhase.idle);
      toast(context, app.t('err.${e.code}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.t;
    final checks = _checks;
    final left = checks.where((c) => !c).length;
    final status = runawayStatus(login: _login, total: checks.length, left: left, phase: _phase, t: t);

    return Scaffold(
      backgroundColor: LD.glossBase,
      body: GlossyBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 26),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const LogoMark(size: 34),
                    const SizedBox(width: 9),
                    const Expanded(child: Wordmark(size: 18)),
                    const LangToggle(),
                  ]),
                  const SizedBox(height: 8),
                  LaundryScene(height: _login ? 230 : 140),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a),
                        child: child,
                      ),
                    ),
                    child: _login ? _loginFields(t) : _signupFields(t),
                  ),
                  const SizedBox(height: 14),
                  _dock(t),
                  const SizedBox(height: 6),
                  Semantics(
                    liveRegion: true,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: left == 0 ? LD.success : LD.lilac, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3E4F66))),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Expanded(child: Divider(color: Color(0x1F0F2340))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(t('orContinue'), style: const TextStyle(fontSize: 12, color: Color(0xFF6B7790))),
                    ),
                    const Expanded(child: Divider(color: Color(0x1F0F2340))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: GlassButton(
                        label: t('google'),
                        icon: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: LD.primary, width: 2)),
                          child: const Text('G', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: LD.primary)),
                        ),
                        onTap: _google,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GlassButton(
                        label: t('otp'),
                        icon: const Icon(Icons.smartphone_rounded, size: 19, color: LD.navy),
                        onTap: () => toast(context, t('soon')),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_login ? t('noAccount') : t('haveAccount'),
                        style: const TextStyle(fontSize: 14, color: Color(0xFF3E4F66))),
                    TextButton(
                      onPressed: _switchMode,
                      child: Text(
                        _login ? t('signUp') : t('logIn'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: LD.navy, decoration: TextDecoration.underline),
                      ),
                    ),
                  ]),
                  if (_login)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _staffLogin(context),
                        icon: const Icon(Icons.badge_outlined, size: 18, color: LD.navy),
                        label: Text(t('staffLogin'), style: const TextStyle(color: LD.navy, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  if (!AuthService.instance.cloud)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(t('demoNote'),
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: LD.slate)),
                    ),
                  const SizedBox(height: 4),
                  const BrotrixFooter(),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _staffLogin(BuildContext context) {
    final app = context.read<AppState>();
    final t = app.t;
    final code = TextEditingController();
    final mobile = TextEditingController();
    final pin = TextEditingController();
    var busy = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: LD.glossBase,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('staffLogin'), style: heading(22)),
            const SizedBox(height: 4),
            Text(t('staffLoginSub'), style: const TextStyle(color: LD.slate)),
            const SizedBox(height: 14),
            GlassField(controller: code, hint: t('shopCode'), icon: Icons.storefront_outlined),
            const SizedBox(height: 10),
            GlassField(controller: mobile, hint: t('mobile'), prefixText: '+91', keyboard: TextInputType.phone),
            const SizedBox(height: 10),
            GlassField(controller: pin, hint: t('pin'), icon: Icons.pin_outlined, obscure: true, keyboard: TextInputType.number, action: TextInputAction.done),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: LD.navy, shape: const StadiumBorder()),
                onPressed: busy
                    ? null
                    : () async {
                        set(() => busy = true);
                        final err = await app.staffLogin(code: code.text, mobile: mobile.text, pin: pin.text.trim());
                        if (!c.mounted) return;
                        set(() => busy = false);
                        if (err == null) {
                          Navigator.pop(c);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(err))));
                        }
                      },
                child: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(t('logIn'), style: heading(16, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _eye() => IconButton(
        tooltip: 'Show or hide password',
        onPressed: () => setState(() => _showPw = !_showPw),
        icon: Icon(_showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19, color: LD.slate),
      );

  Widget _loginFields(String Function(String) t) {
    return Column(key: const ValueKey('login'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DrumHeading(text: t('welcome')),
      const SizedBox(height: 4),
      Text(t('welcomeSub'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: LD.slate)),
      const SizedBox(height: 14),
      GlassField(
        controller: _id,
        hint: t('loginId'),
        icon: Icons.mail_outline_rounded,
        keyboard: TextInputType.emailAddress,
        valid: V.isLoginId(_id.text),
        onChanged: _changed,
      ),
      const SizedBox(height: 12),
      GlassField(
        controller: _pw,
        hint: t('password'),
        icon: Icons.lock_outline_rounded,
        obscure: !_showPw,
        valid: V.isPassword(_pw.text),
        onChanged: _changed,
        action: TextInputAction.done,
        trailing: _eye(),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => toast(context, t('forgotNote')),
          child: Text(t('forgot'), style: const TextStyle(fontWeight: FontWeight.w600, color: LD.navy)),
        ),
      ),
    ]);
  }

  Widget _signupFields(String Function(String) t) {
    final strength = V.strength(_spw.text);
    const colors = [Color(0xFFF0A5C8), LD.lilac, LD.softBlue, LD.aqua];
    final labels = ['', t('weak'), t('okay'), t('good'), t('strong')];
    return Column(key: const ValueKey('signup'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DrumHeading(text: t('create')),
      const SizedBox(height: 4),
      Text(t('createSub'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: LD.slate)),
      const SizedBox(height: 12),
      GlassField(
        controller: _name,
        hint: t('ownerName'),
        icon: Icons.person_outline_rounded,
        keyboard: TextInputType.name,
        valid: V.isName(_name.text),
        onChanged: _changed,
      ),
      const SizedBox(height: 10),
      GlassField(
        controller: _mobile,
        hint: t('mobile'),
        prefixText: '+91',
        keyboard: TextInputType.phone,
        valid: V.isMobile(_mobile.text),
        onChanged: _changed,
      ),
      const SizedBox(height: 10),
      GlassField(
        controller: _email,
        hint: t('email'),
        icon: Icons.mail_outline_rounded,
        keyboard: TextInputType.emailAddress,
        valid: V.isEmail(_email.text),
        onChanged: _changed,
      ),
      const SizedBox(height: 10),
      GlassField(
        controller: _spw,
        hint: t('createPassword'),
        icon: Icons.lock_outline_rounded,
        obscure: !_showPw,
        valid: V.isPassword(_spw.text),
        onChanged: _changed,
        action: TextInputAction.done,
        trailing: _eye(),
      ),
      const SizedBox(height: 10),
      Row(children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                color: i < strength ? colors[i] : const Color(0x1A0F2340),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        SizedBox(
          width: 56,
          child: Text(labels[strength],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4F5DB8))),
        ),
      ]),
      const SizedBox(height: 4),
      InkWell(
        onTap: () {
          _agree = !_agree;
          _changed();
        },
        child: Row(children: [
          Checkbox(
            value: _agree,
            activeColor: LD.navy,
            onChanged: (v) {
              _agree = v ?? false;
              _changed();
            },
          ),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: t('agree1')),
              TextSpan(text: t('terms'), style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: t('and')),
              TextSpan(text: t('privacy'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]), style: const TextStyle(fontSize: 13, color: Color(0xFF3E4F66))),
          ),
        ]),
      ),
    ]);
  }

  Widget _dock(String Function(String) t) {
    const btnW = 130.0;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final x = _ready ? (w - btnW) / 2 : (_side ? w - btnW - 6 : 6.0);
      final turns = _ready ? 0.0 : (_side ? 6 / 360 : -6 / 360);
      final label = _phase == RunPhase.done ? '${t('done')} ✓' : (_login ? '${t('logIn')} →' : '${t('createBtn')} →');
      return Container(
        height: 62,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .95)),
        ),
        child: Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            left: x,
            top: 5,
            child: AnimatedRotation(
              turns: turns,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              child: MouseRegion(
                onEnter: (_) => _dodge(),
                child: AnimatedBuilder(
                  animation: _glow,
                  builder: (context, child) {
                    final g = _glow.value;
                    return Container(
                      width: btnW,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: _ready ? LD.navy : Colors.white,
                        boxShadow: _ready
                            ? [
                                BoxShadow(
                                  color: Color.lerp(const Color(0x667C6FF5), const Color(0x8C3CC6D8), g)!,
                                  blurRadius: 22 + 8 * g,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : const [BoxShadow(color: Color(0x1F0F2340), blurRadius: 10, offset: Offset(0, 3))],
                      ),
                      child: child,
                    );
                  },
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _submit,
                      child: Semantics(
                        button: true,
                        enabled: _ready,
                        label: label,
                        child: Center(
                          child: _phase == RunPhase.loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : Text(
                                  label,
                                  style: heading(15,
                                      weight: FontWeight.w700, color: _ready ? Colors.white : const Color(0xFF6B7790)),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    });
  }
}
