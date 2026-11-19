import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../data/ops_models.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'admin_screens.dart';
import 'customers_screen.dart';
import 'delivery_screen.dart';
import 'issue_screens.dart';
import 'payroll_screens.dart';
import '../data/issue_models.dart';
import 'reports_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.t;
    final shop = app.shop!;
    final d = app.data!;
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    Widget tile(IconData icon, String title, VoidCallback onTap, {String? sub}) => ListTile(
          leading: Icon(icon, color: LD.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: LD.slate)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        );

    Widget group(List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: LD.line)),
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: LD.line),
              children[i],
            ],
          ]),
        );

    final who = app.isOwner ? '${app.owner!.name} · +${app.owner!.mobile}' : '${app.staffUser!.name} · ${roleLabel(app.role, t)}';

    return Scaffold(
      appBar: AppBar(title: Text(t('navMore'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        group([
          ListTile(
            leading: const LogoMark(size: 40),
            title: Text(shop.shopName, style: heading(16, weight: FontWeight.w700)),
            subtitle: Text(who, style: const TextStyle(color: LD.slate)),
          ),
          if (app.isOwner)
            ListTile(
              leading: const Icon(Icons.cloud_outlined, color: LD.primary),
              title: Text(t('mode'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(AuthService.instance.cloud ? t('modeCloud') : t('modeDemo')),
            ),
        ]),
        if (app.role != Role.washer && app.role != Role.delivery)
          group([
            tile(Icons.people_outline, t('customers'), () => go(const CustomersScreen())),
            if (app.module('delivery')) tile(Icons.delivery_dining_outlined, t('delivery'), () => go(const DeliveryBoardScreen())),
            tile(Icons.report_problem_outlined, L(app, 'Complaints & issues', 'शिकायतें और इश्यू'), () => go(const IssuesScreen())),
            tile(Icons.list_alt_rounded, t('rateCard'), () => go(const RateCardScreen())),
            if (app.canManage) tile(Icons.insights_outlined, t('reports'), () => go(const ReportsScreen())),
            if (app.canManage) tile(Icons.receipt_outlined, t('expenses'), () => go(const ExpensesScreen())),
            if (app.isOwner) tile(Icons.store_mall_directory_outlined, t('branches'), () => go(const BranchesScreen())),
            if (app.isOwner) tile(Icons.tune_rounded, L(app, 'Commission rules', 'कमीशन के नियम'), () => go(const RulesScreen())),
          ]),
        if (app.isOwner)
          group([
            tile(Icons.workspace_premium_outlined, t('plans'), () => go(const PlansScreen()),
                sub: d.plan == 'trial' ? t('trialLeft').replaceAll('{n}', '${shop.trialDaysLeft(AppConfig.trialDays)}') : d.plan.toUpperCase()),
            tile(Icons.tune_rounded, t('settings'), () => go(const SettingsScreen()), sub: '${t('shopCode')}: ${d.shopCode}'),
          ]),
        if (!app.isOwner && (d.rules['showEarnings'] as bool? ?? true))
          group([
            tile(Icons.savings_outlined, L(app, 'My earnings', 'मेरी कमाई'),
                () => go(PayslipScreen(staffId: app.staffUser!.id, month: monthKey(DateTime.now()), mine: true))),
          ]),
        group([
          ListTile(
            leading: const Icon(Icons.translate_rounded, color: LD.primary),
            title: Text(t('language'), style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const LangToggle(),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded, color: LD.primary),
            title: Text(t('version'), style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Text(AppConfig.version),
            onTap: app.isOwner
                ? () {
                    _taps++;
                    if (_taps >= 7) {
                      _taps = 0;
                      SuperAdminScreen.open(context);
                    }
                  }
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Color(0xFFB42318)),
            title: Text(t('logout'), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFB42318))),
            onTap: app.signOut,
          ),
        ]),
        const SizedBox(height: 10),
        const BrotrixFooter(),
      ]),
    );
  }
}
