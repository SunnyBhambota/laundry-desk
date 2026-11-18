import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Owner admin dashboard (canvas: "Owner – Admin dashboard").
/// v0.1 shows the real shop with zero orders; orders/staff arrive in v0.2.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.t;
    final shop = app.shop!;
    final owner = app.owner!;
    final sym = AppConfig.currencySymbols[shop.currency] ?? '${shop.currency} ';
    final days = shop.trialDaysLeft(AppConfig.trialDays);
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? t('goodMorning') : (hour < 17 ? t('goodAfternoon') : t('goodEvening'));
    final firstName = owner.name.split(' ').first;
    final modules = [...AppConfig.freeModules, ...AppConfig.premiumModules];

    Widget card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: LD.line),
          ),
          child: child,
        );

    Widget title(String text, [Widget? action]) => Row(children: [
          Expanded(child: Text(text, style: heading(16, weight: FontWeight.w700))),
          if (action != null) action,
        ]);

    Widget kpi(String label, String value, String note, Color noteColor) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: LD.line),
            boxShadow: const [BoxShadow(color: Color(0x0F0F2340), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LD.slate)),
            const SizedBox(height: 6),
            Text(value, style: heading(22)),
            const SizedBox(height: 4),
            Text(note, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: noteColor)),
          ]),
        );

    Widget quick(IconData icon, String label) => Expanded(
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => toast(context, t('soon')),
              child: SizedBox(
                height: 78,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: const Color(0xFFE6EEFC), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, size: 20, color: LD.primary),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        );

    const stages = ['received', 'washing', 'ready', 'out', 'delivered'];

    return Scaffold(
      backgroundColor: LD.mist,
      body: ListView(padding: EdgeInsets.zero, children: [
        // header
        Container(
          color: LD.navy,
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 18, 20, 74),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const LogoMark(size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(shop.shopName, style: heading(16, color: Colors.white), overflow: TextOverflow.ellipsis),
                  const Text('Owner · Admin', style: TextStyle(fontSize: 12, color: Color(0xFFC9D6EA))),
                ]),
              ),
              IconButton(
                tooltip: 'Notifications',
                onPressed: () => toast(context, t('soon')),
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .12)),
                icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
              ),
            ]),
            const SizedBox(height: 16),
            Text(_date(DateTime.now()), style: const TextStyle(fontSize: 13, color: Color(0xFFC9D6EA))),
            const SizedBox(height: 4),
            Text('$greet, $firstName', style: heading(24, color: Colors.white)),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: .25)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.store_mall_directory_outlined, size: 16, color: LD.aqua),
                  const SizedBox(width: 8),
                  Text('${t('allBranches')} (1)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: LD.sun, borderRadius: BorderRadius.circular(999)),
                child: Text(t('trialLeft').replaceAll('{n}', '$days'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: LD.navy)),
              ),
            ]),
          ]),
        ),
        Transform.translate(
          offset: const Offset(0, -54),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.45,
                padding: EdgeInsets.zero,
                children: [
                  kpi(t('todayCollection'), '${sym}0', t('noneYet'), LD.slate),
                  kpi(t('newOrders'), '0', t('noneYet'), LD.slate),
                  kpi(t('pendingUdhaar'), '${sym}0', '—', const Color(0xFF8A5A00)),
                  kpi(t('readyDeliver'), '0', '—', const Color(0xFFA8430F)),
                ],
              ),
              const SizedBox(height: 16),
              Row(children: [
                quick(Icons.add_rounded, t('qOrder')),
                const SizedBox(width: 8),
                quick(Icons.person_add_alt_1_outlined, t('qCustomer')),
                const SizedBox(width: 8),
                quick(Icons.currency_rupee_rounded, t('qPayment')),
                const SizedBox(width: 8),
                quick(Icons.list_alt_rounded, t('qRates')),
              ]),
              const SizedBox(height: 16),
              card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  title(t('pipeline')),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Container(height: 12, color: const Color(0xFFEDF0F4)),
                  ),
                  const SizedBox(height: 10),
                  for (final s in stages)
                    SizedBox(
                      height: 36,
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: LD.statusColors[s]![0], borderRadius: BorderRadius.circular(99)),
                          child: Text(t(s),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LD.statusColors[s]![1])),
                        ),
                        const Spacer(),
                        const Text('0', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 16),
              card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  title(
                    t('branchesToday'),
                    TextButton(onPressed: () => toast(context, t('soon')), child: Text(t('addBranch'))),
                  ),
                  const Divider(color: Color(0xFFEDF1F6)),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(shop.address.isEmpty ? t('mainBranch') : shop.address,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(t('ordersStaff').replaceAll('{o}', '0').replaceAll('{s}', '0'),
                            style: const TextStyle(fontSize: 12, color: LD.slate)),
                      ]),
                    ),
                    Text('${sym}0', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  title(t('staffActivity')),
                  const SizedBox(height: 8),
                  Text(t('noStaff'), style: const TextStyle(color: LD.slate, height: 1.5, fontSize: 13)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => toast(context, t('soon')),
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                      label: Text(t('addStaff')),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  title(
                    t('modules'),
                    Text(t('modulesOn').replaceAll('{n}', '${modules.length}').replaceAll('{t}', '${modules.length}'),
                        style: const TextStyle(fontSize: 12, color: LD.slate)),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final m in modules)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppConfig.premiumModules.contains(m) ? const Color(0xFFFFF4D6) : const Color(0xFFE6EEFC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (AppConfig.premiumModules.contains(m)) ...[
                            const Icon(Icons.star_rounded, size: 14, color: Color(0xFF8A5A00)),
                            const SizedBox(width: 4),
                          ],
                          Text(t('m.$m'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppConfig.premiumModules.contains(m) ? const Color(0xFF8A5A00) : const Color(0xFF1F4FB0),
                              )),
                        ]),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: LD.navy, borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(t('trialEnds').replaceAll('{n}', '$days'), style: heading(16, color: Colors.white)),
                      const SizedBox(height: 8),
                      Text(t('trialBody'), style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFFC9D6EA))),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: LD.sun,
                          foregroundColor: LD.navy,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => toast(context, t('soon')),
                        child: Text(t('choosePlan'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  static String _date(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }
}
