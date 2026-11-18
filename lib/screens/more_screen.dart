import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.t;
    final shop = app.shop!;
    final owner = app.owner!;

    Widget tile(IconData icon, String title, String sub) => ListTile(
          leading: Icon(icon, color: LD.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sub, style: const TextStyle(color: LD.slate)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(t('navMore'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: LD.line)),
          child: Column(children: [
            ListTile(
              leading: const LogoMark(size: 40),
              title: Text(shop.shopName, style: heading(16, weight: FontWeight.w700)),
              subtitle: Text('${owner.name} · +${owner.mobile}', style: const TextStyle(color: LD.slate)),
            ),
            const Divider(height: 1, color: LD.line),
            tile(Icons.local_laundry_service_outlined, t('servicesQ'), shop.services.join(', ')),
            tile(Icons.public_rounded, '${t('country')} · ${t('currency')}', '${shop.country} · ${shop.currency}'),
            tile(Icons.cloud_outlined, t('mode'), AuthService.instance.cloud ? t('modeCloud') : t('modeDemo')),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: LD.line)),
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.translate_rounded, color: LD.primary),
              title: Text(t('language'), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const LangToggle(),
            ),
            const Divider(height: 1, color: LD.line),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: LD.primary),
              title: Text(t('version'), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Text(AppConfig.version),
            ),
            const Divider(height: 1, color: LD.line),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Color(0xFFB42318)),
              title: Text(t('logout'), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFB42318))),
              onTap: app.signOut,
            ),
          ]),
        ),
        const SizedBox(height: 24),
        const BrotrixFooter(),
      ]),
    );
  }
}
