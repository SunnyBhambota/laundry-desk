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
import 'v03_screens.dart';
import 'v04_screens.dart';
import '../data/issue_models.dart';
import 'reports_screen.dart';
import 'v06_screens.dart';
import 'v08_screens.dart';
import 'v09_screens.dart';

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
          if (d.sync != null)
            ListTile(
              leading: Icon(d.sync!.lastError.isEmpty ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  color: d.sync!.lastError.isEmpty ? LD.success : const Color(0xFFB42318)),
              title: Text(
                  d.sync!.lastError.isEmpty
                      ? '${L(app, 'Cloud synced', 'क्लाउड सिंक')} ${d.sync!.lastOk == null ? '' : hm(d.sync!.lastOk!)}'
                      : L(app, 'Cloud sync problem – tap to retry', 'क्लाउड सिंक में दिक्कत – दोबारा कोशिश करें'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: d.sync!.lastError.isEmpty ? null : Text(d.sync!.lastError, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.sync_rounded),
              onTap: () async {
                await d.flush();
                if (context.mounted) toast(context, d.sync!.lastError.isEmpty ? L(app, 'All saved to cloud.', 'सब क्लाउड में सेव है।') : d.sync!.lastError);
                setState(() {});
              },
            ),
        ]),
        if (app.role != Role.washer && app.role != Role.delivery)
          group([
            tile(Icons.people_outline, t('customers'), () => go(const CustomersScreen())),
            if (app.module('delivery')) tile(Icons.delivery_dining_outlined, t('delivery'), () => go(const DeliveryBoardScreen())),
            if (app.module('delivery')) tile(Icons.map_outlined, L(app, 'Live map & route', 'लाइव मैप और रूट'), () => go(const RouteMapScreen())),
            if (app.module('loyalty')) tile(Icons.local_offer_outlined, L(app, 'Offers, points & packages', 'ऑफ़र, पॉइंट और पैकेज'), () => go(const OffersScreen())),
            if (app.module('stock') && app.canManage)
              tile(Icons.inventory_2_outlined, L(app, 'Stock & suppliers', 'स्टॉक और सप्लायर'), () => go(const StockScreen()),
                  sub: d.lowStock.isEmpty ? null : '${d.lowStock.length} ${L(app, 'running low', 'खत्म होने वाले')}'),
            tile(Icons.qr_code_scanner, L(app, 'Scan tag / bill QR', 'टैग / बिल QR स्कैन'), () => go(const ScanScreen())),
            tile(Icons.print_outlined, L(app, 'Printer & UPI', 'प्रिंटर और UPI'), () => go(const PrinterScreen())),
            tile(Icons.qr_code_2_rounded, L(app, 'Customer booking QR', 'ग्राहक बुकिंग QR'), () => go(const BookingQrScreen()),
                sub: L(app, 'WhatsApp pickup requests · poster', 'WhatsApp पिकअप रिक्वेस्ट · पोस्टर')),
            tile(Icons.report_problem_outlined, L(app, 'Complaints & issues', 'शिकायतें और इश्यू'), () => go(const IssuesScreen())),
            tile(Icons.list_alt_rounded, t('rateCard'), () => go(const RateCardScreen())),
            if ((app.canManage || app.role == Role.counter) && app.can('reports')) tile(Icons.insights_outlined, t('reports'), () => go(const ReportsScreen())),
            if (app.canManage) tile(Icons.point_of_sale_outlined, L(app, 'Day closing (cash book)', 'दिन का हिसाब (कैश बुक)'), () => go(const DayCloseScreen())),
            if ((app.canManage || app.role == Role.counter) && app.can('expenses')) tile(Icons.receipt_outlined, t('expenses'), () => go(const ExpensesScreen())),
            if (app.isOwner) tile(Icons.store_mall_directory_outlined, t('branches'), () => go(const BranchesScreen())),
            if (app.isOwner) tile(Icons.tune_rounded, L(app, 'Commission rules', 'कमीशन के नियम'), () => go(const RulesScreen())),
          ]),
        if (app.isOwner)
          group([
            tile(Icons.workspace_premium_outlined, t('plans'), () => go(const PlansScreen()),
                sub: d.plan == 'trial' ? t('trialLeft').replaceAll('{n}', '${shop.trialDaysLeft(AppConfig.trialDays)}') : d.plan.toUpperCase()),
            tile(Icons.tune_rounded, t('settings'), () => go(const SettingsScreen()), sub: '${t('shopCode')}: ${d.shopCode}'),
          ]),
        if (app.role == Role.washer || app.role == Role.delivery)
          group([
            tile(Icons.campaign_outlined, L(app, 'Notice board', 'नोटिस बोर्ड'), () => go(const NoticeBoardScreen())),
            if (app.canManage) tile(Icons.engineering_outlined, L(app, 'Work board (who does what)', 'काम बोर्ड (कौन क्या कर रहा)'), () => go(const WorkBoardScreen())),
            if (app.canManage) tile(Icons.manage_search_rounded, L(app, 'Who changed what', 'किसने क्या बदला'), () => go(const AuditScreen())),
            if (app.isOwner) tile(Icons.flag_outlined, L(app, 'Daily target', 'रोज़ का टारगेट'), () => targetSheet(context, app)),
            tile(Icons.inbox_outlined, app.canManage ? L(app, 'Staff requests & leave', 'स्टाफ की माँग और छुट्टी') : L(app, 'Ask the boss (things / leave)', 'बॉस से माँगें (चीज़ / छुट्टी)'),
                () => go(const RequestsScreen()),
                sub: app.canManage && d.pendingRequests.isNotEmpty ? '${d.pendingRequests.length} ${L(app, 'waiting', 'इंतज़ार में')}' : null),
            if (!app.isOwner && app.module('stock')) tile(Icons.water_drop_outlined, L(app, 'Stock used (powder…)', 'स्टॉक इस्तेमाल (पाउडर…)'), () => go(const StockUseScreen())),
            tile(Icons.qr_code_scanner, L(app, 'Scan tag / bill QR', 'टैग / बिल QR स्कैन'), () => go(const ScanScreen())),
            if (app.role == Role.delivery) tile(Icons.route_outlined, L(app, 'My route (nearest first)', 'मेरा रूट (पास वाला पहले)'), () => go(RouteMapScreen(agentId: app.staffUser!.id))),
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
                      openBrotrixAdmin(context);
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
