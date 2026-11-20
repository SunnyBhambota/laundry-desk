import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Owner app lock: 4-digit PIN keypad. Shown on start and when the app comes back.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  bool _wrong = false;
  int _fails = 0;
  DateTime? _waitUntil;

  void _press(String k) {
    if (_waitUntil != null && DateTime.now().isBefore(_waitUntil!)) return;
    setState(() {
      _wrong = false;
      if (k == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 4) {
        _pin += k;
      }
    });
    if (_pin.length == 4) {
      final ok = context.read<AppState>().unlock(_pin);
      if (!ok) {
        setState(() {
          _fails++;
          _wrong = true;
          _pin = '';
          // after 5 wrong tries wait 30 s
          if (_fails % 5 == 0) _waitUntil = DateTime.now().add(const Duration(seconds: 30));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.t;
    Widget key(String k) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Material(
              color: Colors.white.withValues(alpha: .8),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _press(k),
                child: SizedBox(
                  height: 70,
                  child: Center(
                    child: k == '<'
                        ? const Icon(Icons.backspace_outlined, semanticLabel: 'Delete')
                        : Text(k, style: heading(26, weight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ),
        );
    return Scaffold(
      body: GlossyBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(children: [
              const Spacer(),
              const LogoMark(size: 64),
              const SizedBox(height: 14),
              Text(app.shop?.shopName ?? 'LaundryCase', style: heading(22)),
              const SizedBox(height: 6),
              Text(t('lockEnter'), style: const TextStyle(color: LD.slate)),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? LD.navy : Colors.transparent,
                      border: Border.all(color: _wrong ? const Color(0xFFB42318) : LD.navy, width: 2),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                height: 20,
                child: _wrong ? Text(t('lockWrong'), style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w600)) : null,
              ),
              const Spacer(),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(children: [for (final k in row) key(k)]),
              Row(children: [const Expanded(child: SizedBox()), key('0'), key('<')]),
              TextButton(onPressed: app.signOut, child: Text(t('logout'))),
              const SizedBox(height: 10),
            ]),
          ),
        ),
      ),
    );
  }
}
