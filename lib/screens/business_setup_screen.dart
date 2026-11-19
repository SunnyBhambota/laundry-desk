import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

/// Register step 2: one-time shop setup.
class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({super.key});

  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final _shop = TextEditingController();
  final _address = TextEditingController();
  final _referral = TextEditingController();
  final _mobile = TextEditingController();
  final _pw = TextEditingController();
  final Set<String> _services = {'Wash & fold', 'Dry clean', 'Steam iron'};
  String _branches = '1';
  String _team = '1–3';
  String _country = 'India';
  bool _pickup = true;
  bool _gst = false;
  bool _sample = true;
  bool _saving = false;

  @override
  void dispose() {
    _shop.dispose();
    _address.dispose();
    _referral.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final app = context.read<AppState>();
    if (_shop.text.trim().length < 2) {
      toast(context, app.t('needShop'));
      return;
    }
    if (_services.isEmpty) {
      toast(context, app.t('needService'));
      return;
    }
    final needMobile = app.owner != null && app.owner!.mobile.isEmpty;
    final digits = _mobile.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (needMobile && digits.length < 10) {
      toast(context, app.t('err.mobile'));
      return;
    }
    if (needMobile && _pw.text.length < 8) {
      toast(context, L(app, 'Make a password (8+ letters) so you can also log in with your mobile.', 'पासवर्ड बनाएँ (8+ अक्षर) ताकि मोबाइल से भी लॉगिन हो सके।'));
      return;
    }
    setState(() => _saving = true);
    if (needMobile) {
      final full = AuthService.fullMobile(_mobile.text);
      try {
        await AuthService.instance.addPassword(full, _pw.text);
      } on AuthError catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        toast(context, e.code == 'exists' ? L(app, 'This mobile already has an account. Log out and log in with mobile + password.', 'इस मोबाइल का अकाउंट पहले से है। लॉगआउट करके मोबाइल + पासवर्ड से लॉगिन करें।') : app.t('err.${e.code}'));
        return;
      }
      await AuthService.instance.saveOwnerMobile(app.owner!, full);
      app.owner = Owner(uid: app.owner!.uid, name: app.owner!.name, mobile: full, email: app.owner!.email);
    }
    await app.saveShop(ShopProfile(
      shopName: _shop.text.trim(),
      services: AppConfig.services.where(_services.contains).toList(),
      branches: _branches,
      team: _team,
      country: _country,
      currency: AppConfig.countries[_country] ?? 'INR',
      address: _address.text.trim(),
      pickupDelivery: _pickup,
      gst: _gst,
      referral: _referral.text.trim(),
    ), sample: _sample);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.t;

    Widget chip(String label, bool on, VoidCallback tap) => Semantics(
          button: true,
          selected: on,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: tap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: on ? LD.navy : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? LD.navy : LD.line, width: 1.5),
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : LD.navy)),
            ),
          ),
        );

    Widget group(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            child,
          ]),
        );

    Widget row(List<String> opts, String value, ValueChanged<String> pick) => Row(children: [
          for (var i = 0; i < opts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: chip(opts[i], value == opts[i], () => setState(() => pick(opts[i])))),
          ],
        ]);

    Widget sw(String label, bool v, ValueChanged<bool> on) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          value: v,
          activeTrackColor: LD.navy,
          onChanged: (x) => setState(() => on(x)),
        );

    return Scaffold(
      backgroundColor: LD.glossBase,
      body: GlossyBackground(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
            Row(children: [
              IconButton(
                tooltip: t('logout'),
                onPressed: app.signOut,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  LogoMark(size: 30),
                  SizedBox(width: 8),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Wordmark(size: 16))),
                ]),
              ),
              const LangToggle(),
            ]),
            const SizedBox(height: 14),
            Text(t('setupTitle'), style: heading(26)),
            const SizedBox(height: 4),
            Text('${t('setupSub')} ${t('step2')}', style: const TextStyle(fontSize: 14, color: LD.slate)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Container(height: 5, decoration: BoxDecoration(color: LD.navy, borderRadius: BorderRadius.circular(9)))),
              const SizedBox(width: 6),
              Expanded(child: Container(height: 5, decoration: BoxDecoration(color: LD.navy, borderRadius: BorderRadius.circular(9)))),
            ]),
            const SizedBox(height: 18),
            GlassField(key: const ValueKey('f.shop'), controller: _shop, hint: t('shopName').replaceAll(RegExp(r'\s*\(.*\)'), ''), icon: Icons.storefront_outlined),
            group(
              t('servicesQ'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in AppConfig.services)
                  chip(hiName(app, s), _services.contains(s), () => setState(() => _services.contains(s) ? _services.remove(s) : _services.add(s))),
              ]),
            ),
            group(t('branchesQ'), row(const ['1', '2 – 5', '6+'], _branches, (v) => _branches = v)),
            group(t('teamQ'), row(const ['1–3', '4–10', '11–25', '25+'], _team, (v) => _team = v)),
            group(
              '${t('country')} · ${t('currency')}',
              DropdownButtonFormField<String>(
                initialValue: _country,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .78),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                ),
                items: [
                  for (final c in AppConfig.countries.keys)
                    DropdownMenuItem(value: c, child: Text('$c · ${AppConfig.countries[c]}')),
                ],
                onChanged: (v) => setState(() => _country = v ?? 'India'),
              ),
            ),
            const SizedBox(height: 14),
            if (app.owner != null && app.owner!.mobile.isEmpty) ...[
              GlassField(controller: _mobile, hint: t('mobile'), icon: Icons.phone_iphone_rounded),
              const SizedBox(height: 10),
              GlassField(controller: _pw, hint: L(app, 'Password for mobile login (8+)', 'मोबाइल लॉगिन का पासवर्ड (8+)'), icon: Icons.lock_outline_rounded, obscure: true),
              const SizedBox(height: 10),
            ],
            GlassField(controller: _address, hint: t('address'), icon: Icons.place_outlined),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: LD.line),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(children: [
                sw(t('pickupOffer'), _pickup, (v) => _pickup = v),
                sw(t('gst'), _gst, (v) => _gst = v),
                sw(t('sampleOn'), _sample, (v) => _sample = v),
              ]),
              ),
            ),
            const SizedBox(height: 14),
            GlassField(controller: _referral, hint: t('referral'), icon: Icons.card_giftcard_outlined, action: TextInputAction.done),
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: FilledButton(
                key: const ValueKey('b.finish'),
                style: FilledButton.styleFrom(backgroundColor: LD.navy, shape: const StadiumBorder()),
                onPressed: _saving ? null : _finish,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(t('finish'), style: heading(16, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
            Text(t('trialNote'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: LD.slate)),
            const SizedBox(height: 18),
            const BrotrixFooter(),
          ]),
        ),
      ),
    );
  }
}
