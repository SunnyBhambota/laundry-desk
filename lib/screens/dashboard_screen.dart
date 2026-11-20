import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../data/ops_models.dart';
import '../data/reports.dart';
import '../data/shop_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'admin_screens.dart';
import 'customers_screen.dart';
import 'delivery_screen.dart';
import 'issue_screens.dart';
import 'v04_screens.dart';
import 'new_order_screen.dart';
import 'orders_screen.dart';
import 'reports_screen.dart';
import 'staff_screen.dart';
import 'v03_screens.dart';
import 'v06_screens.dart';
import 'v08_screens.dart';
import 'v10_screens.dart';

/// Owner / manager / counter home (canvas: "Owner – Admin dashboard").
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.t;
    final shop = app.shop!;
    final d = app.data!;
    final cur = shop.currency;
    final scope = app.scopeBranch;
    final today = Report(orders: d.orders, expenses: d.expenses, range: DateRange.of(Period.today), branchId: scope);
    final scoped = d.ordersIn(scope).toList();
    final days = shop.trialDaysLeft(AppConfig.trialDays);
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? t('goodMorning') : (hour < 17 ? t('goodAfternoon') : t('goodEvening'));
    final firstName = app.actorName.split(' ').first;
    final modules = [...AppConfig.freeModules, ...AppConfig.premiumModules];
    final late = scoped.where((o) => o.late).length;
    final ready = scoped.where((o) => o.status == 'ready').length;
    final out = scoped.where((o) => o.status == 'out').length;
    final pickupsToday = scoped.where((o) => o.status == 'pickup').length;
    final dueTotal = scoped.where((o) => o.status != 'cancelled').fold<double>(0, (s, o) => s + o.due);
    final dueCustomers = scoped.where((o) => o.status != 'cancelled' && o.due > 0).map((o) => o.customerId).toSet().length;
    final stages = ['pickup', 'received', 'washing', 'ready', 'out', 'delivered'];
    final counts = {for (final s in stages) s: scoped.where((o) => o.status == s && (s != 'delivered' || DateRange.of(Period.today).has(o.timeOf('delivered') ?? DateTime(2000)))).length};
    final pipeTotal = counts.values.fold<int>(0, (a, b) => a + b);
    final branchName = scope == null ? '${t('allBranches')} (${d.branches.length})' : (d.branch(scope)?.name ?? '');
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    Widget kpi(String label, String value, String note, Color noteColor, VoidCallback onTap) => Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LD.line)),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LD.slate)),
                const SizedBox(height: 6),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: heading(22))),
                const SizedBox(height: 4),
                Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: noteColor)),
              ]),
            ),
          ),
        );

    Widget quick(IconData icon, String label, VoidCallback onTap) => Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: const Color(0xFFE6EEFC), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 20, color: LD.primary),
              ),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        );

    final staffList = d.staff.where((s) => s.active && (scope == null || s.branchId == scope)).toList()
      ..sort((a, b) => d.actionsToday(b.id).compareTo(d.actionsToday(a.id)));

    return Scaffold(
      backgroundColor: LD.mist,
      body: ListView(padding: EdgeInsets.zero, children: [
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
                  Text(app.isOwner ? 'Owner · Admin' : roleLabel(app.role, t), style: const TextStyle(fontSize: 12, color: Color(0xFFC9D6EA))),
                ]),
              ),
              IconButton(
                tooltip: L(app, 'Scan tag', 'टैग स्कैन'),
                onPressed: () => go(const ScanScreen()),
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .12)),
                icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Stack(children: [
                IconButton(
                  tooltip: t('late'),
                  onPressed: () => go(const OrdersScreen(initialFilter: 'late')),
                  style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .12)),
                  icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                ),
                if (late > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFE8742A), borderRadius: BorderRadius.circular(99)),
                      child: Text('$late', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ]),
            ]),
            const SizedBox(height: 16),
            Text(_date(DateTime.now()), style: const TextStyle(fontSize: 13, color: Color(0xFFC9D6EA))),
            const SizedBox(height: 4),
            Text('$greet, $firstName', style: heading(24, color: Colors.white)),
            const SizedBox(height: 14),
            Row(children: [
              PopupMenuButton<String>(
                enabled: app.isOwner && d.branches.length > 1,
                onSelected: (v) => app.setBranchFilter(v == '*' ? null : v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: '*', child: Text('${t('allBranches')} (${d.branches.length})')),
                  for (final b in d.branches) PopupMenuItem(value: b.id, child: Text(b.name)),
                ],
                child: Container(
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
                    Text(branchName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    if (app.isOwner && d.branches.length > 1) const Icon(Icons.expand_more_rounded, color: Colors.white, size: 18),
                  ]),
                ),
              ),
              const Spacer(),
              if (app.isOwner)
                InkWell(
                  onTap: () => go(const PlansScreen()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: LD.sun, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      d.plan == 'trial' ? t('trialLeft').replaceAll('{n}', '$days') : d.plan.toUpperCase(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: LD.navy),
                    ),
                  ),
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
                  kpi(t('todayCollection'), money(today.collected, cur), '${d.ordersIn(scope).expand((o) => o.payments).where((p) => DateRange.of(Period.today).has(p.at)).length} ${t('payments').toLowerCase()}',
                      const Color(0xFF146C43), app.canManage ? () => go(const ReportsScreen()) : () {}),
                  kpi(t('newOrders'), '${today.orderCount}', '${today.pieces} ${t('pcs')} · $pickupsToday ${t('pickups').toLowerCase()}', LD.slate,
                      () => go(const OrdersScreen(initialFilter: 'all'))),
                  kpi(t('pendingUdhaar'), money(dueTotal, cur), '$dueCustomers ${t('customers').toLowerCase()}', const Color(0xFF8A5A00),
                      () => go(const CustomersScreen())),
                  kpi(t('readyDeliver'), '$ready', '$out ${t('out').toLowerCase()}', const Color(0xFFA8430F),
                      () => go(const OrdersScreen(initialFilter: 'ready'))),
                ],
              ),
              Builder(builder: (_) {
                final openIss = d.issues.where((i) => i.open && (scope == null || i.branchId == scope)).toList();
                if (openIss.isEmpty) return const SizedBox.shrink();
                final late = openIss.where((i) => DateTime.now().isAfter(i.dueAt)).length;
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: const Color(0xFFFDE8E8),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => go(const IssuesScreen()),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          const Icon(Icons.report_problem_outlined, color: Color(0xFFB42318)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${openIss.length} ${L(app, 'open complaints / issues', 'खुली शिकायतें / इश्यू')}${late > 0 ? ' · $late ${L(app, 'late', 'देरी')}' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB42318)),
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Color(0xFFB42318)),
                        ]),
                      ),
                    ),
                  ),
                );
              }),
              const TargetCard(),
              BackupReminder(onBackup: () => shareBackup(app)),
              if (app.canManage && d.machinesDue.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: const Color(0xFFFDE8E8),
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: const Icon(Icons.build_circle_outlined, color: Color(0xFFB42318)),
                      title: Text('${L(app, 'Machines need attention', 'मशीनों पर ध्यान दें')}: ${d.machinesDue.map((m) => m.name).take(3).join(', ')}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB42318))),
                      trailing: const Icon(Icons.chevron_right, color: Color(0xFFB42318)),
                      onTap: () => go(const MachinesScreen()),
                    ),
                  ),
                ),
              if (d.sync != null && (d.sync!.lastError.contains('unavailable') || d.sync!.lastError.contains('network')))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(L(app, '● Offline – work normally, everything is saved on the phone and goes to the cloud when internet is back.',
                      '● ऑफ़लाइन – काम करते रहें, सब फ़ोन में सेव है और इंटरनेट आते ही क्लाउड में जाएगा।'), style: const TextStyle(color: Color(0xFF8A5A00), fontWeight: FontWeight.w600)),
                ),
              if (!app.isOwner) const Padding(padding: EdgeInsets.only(top: 12), child: NoticeBanner()),
              if (app.canManage && d.pendingRequests.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: const Color(0xFFE6EEFC),
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: Icon(Icons.campaign_outlined, color: d.pendingRequests.any((r) => r.urgent) ? const Color(0xFFB42318) : LD.primary),
                      title: Text('${d.pendingRequests.length} ${L(app, 'staff requests waiting', 'स्टाफ की माँग इंतज़ार में')}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: LD.navy)),
                      subtitle: Text(d.pendingRequests.take(3).map((r) => '${r.item} (${d.nameOf(r.by).split(' ').first})').join(', '),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right, color: LD.navy),
                      onTap: () => go(const RequestsScreen()),
                    ),
                  ),
                ),
              if (app.module('stock') && app.canManage && d.lowStock.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: const Color(0xFFFFF4D6),
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: const Icon(Icons.inventory_2_outlined, color: Color(0xFF8A5A00)),
                      title: Text('${L(app, 'Stock running low', 'स्टॉक खत्म हो रहा है')}: ${d.lowStock.map((s) => s.name).take(3).join(', ')}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8A5A00))),
                      trailing: const Icon(Icons.chevron_right, color: Color(0xFF8A5A00)),
                      onTap: () => go(const StockScreen()),
                    ),
                  ),
                ),
              if (d.hasSample) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const Icon(Icons.science_outlined, size: 18, color: Color(0xFF5B3FC4)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t('sampleBanner'), style: const TextStyle(fontSize: 12, color: Color(0xFF5B3FC4)))),
                    ]),
                    if (app.isOwner) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5B3FC4), visualDensity: VisualDensity.compact),
                          onPressed: () => deleteSampleFlow(context, app),
                          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                          label: Text(t('clearSample')),
                        ),
                      ),
                    ],
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: .95,
                padding: EdgeInsets.zero,
                children: [
                  quick(Icons.add_rounded, t('qOrder'), () => go(const NewOrderScreen())),
                  quick(Icons.people_outline, t('customers'), () => go(const CustomersScreen())),
                  quick(Icons.delivery_dining_outlined, t('delivery'),
                      app.module('delivery') ? () => go(const DeliveryBoardScreen()) : () => toast(context, t('moduleOff'))),
                  quick(Icons.report_problem_outlined, L(app, 'Issues', 'इश्यू'), () => go(const IssuesScreen())),
                  if (app.canManage) ...[
                    quick(Icons.insights_outlined, t('reports'), () => go(const ReportsScreen())),
                    quick(Icons.receipt_outlined, t('expenses'), () => go(const ExpensesScreen())),
                    quick(Icons.groups_outlined, t('staff'), () => go(const StaffScreen())),
                    quick(Icons.list_alt_rounded, t('qRates'), () => go(const RateCardScreen())),
                    quick(Icons.engineering_outlined, L(app, 'Work board', 'काम बोर्ड'), () => go(const WorkBoardScreen())),
                    quick(Icons.point_of_sale_outlined, L(app, 'Cash drawer', 'कैश ड्रॉअर'), () => go(const DayCloseScreen())),
                    quick(Icons.campaign_outlined, L(app, 'Notices', 'नोटिस'), () => go(const NoticeBoardScreen())),
                    quick(Icons.manage_search_rounded, L(app, 'Who changed', 'किसने बदला'), () => go(const AuditScreen())),
                  ],
                  if (app.role == Role.counter) quick(Icons.point_of_sale_outlined, L(app, 'Cash drawer', 'कैश ड्रॉअर'), () => go(const DayCloseScreen())),
                ],
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: t('pipeline'),
                action: TextButton(onPressed: () => go(const OrdersScreen()), child: Text(t('all'))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: SizedBox(
                      height: 12,
                      child: pipeTotal == 0
                          ? Container(color: const Color(0xFFEDF0F4))
                          : Row(children: [
                              for (final s in stages)
                                if (counts[s]! > 0)
                                  Expanded(
                                    flex: counts[s]!,
                                    child: Container(margin: const EdgeInsets.only(right: 2), color: _barColor(s)),
                                  ),
                            ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final s in stages)
                    InkWell(
                      onTap: () => go(OrdersScreen(initialFilter: s)),
                      child: SizedBox(
                        height: 38,
                        child: Row(children: [
                          StatusChip(s),
                          if (s == 'delivered') Text('  ${t('today')}', style: const TextStyle(fontSize: 11, color: LD.slate)),
                          const Spacer(),
                          Text('${counts[s]}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const Icon(Icons.chevron_right_rounded, color: LD.slate, size: 20),
                        ]),
                      ),
                    ),
                ]),
              ),
              if (app.isOwner && scope == null) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: t('branchesToday'),
                  action: TextButton(onPressed: () => go(const BranchesScreen()), child: Text(t('addBranch'))),
                  child: Column(children: [
                    for (final b in d.branches)
                      InkWell(
                        onTap: () => app.setBranchFilter(b.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(
                                  t('ordersStaff')
                                      .replaceAll('{o}', '${today.booked.where((o) => o.branchId == b.id).length}')
                                      .replaceAll('{s}', '${d.staff.where((s) => s.active && s.branchId == b.id && d.todayAttendance(s.id) != null && d.todayAttendance(s.id)!.outAt == null).length}'),
                                  style: const TextStyle(fontSize: 12, color: LD.slate),
                                ),
                              ]),
                            ),
                            Text(money(today.branchSales[b.id] ?? 0, cur), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ],
              if (app.canManage) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: t('staffActivity'),
                  action: TextButton(onPressed: () => go(const StaffScreen()), child: Text(t('staff'))),
                  child: staffList.isEmpty
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t('noStaff'), style: const TextStyle(color: LD.slate, height: 1.5, fontSize: 13)),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => go(const StaffScreen()),
                            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                            label: Text(t('addStaff')),
                          ),
                        ])
                      : Column(children: [
                          for (final s in staffList.take(5))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(children: [
                                Avatar(s.initials, color: avatarColor(s.id)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text('${roleLabel(s.role, t)} · ${d.branch(s.branchId)?.name ?? ''}', style: const TextStyle(fontSize: 12, color: LD.slate)),
                                    Text(_work(d, s, t), style: const TextStyle(fontSize: 12)),
                                  ]),
                                ),
                                _duty(d, s, t),
                              ]),
                            ),
                        ]),
                ),
              ],
              if (app.isOwner) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: t('modules'),
                  action: Text(
                    t('modulesOn').replaceAll('{n}', '${modules.where(app.module).length}').replaceAll('{t}', '${modules.length}'),
                    style: const TextStyle(fontSize: 12, color: LD.slate),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final m in modules)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: !app.module(m)
                                ? const Color(0xFFEDF0F4)
                                : (AppConfig.premiumModules.contains(m) ? const Color(0xFFFFF4D6) : const Color(0xFFE6EEFC)),
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
                                  decoration: app.module(m) ? null : TextDecoration.lineThrough,
                                  color: AppConfig.premiumModules.contains(m) ? const Color(0xFF8A5A00) : const Color(0xFF1F4FB0),
                                )),
                          ]),
                        ),
                    ]),
                    if (d.plan == 'trial' || d.plan == 'free') ...[
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
                            onPressed: () => go(const PlansScreen()),
                            child: Text(t('choosePlan'), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  static Color _barColor(String s) => const {
        'pickup': Color(0xFF9B87F5),
        'received': Color(0xFF1F5FD1),
        'washing': Color(0xFF3CC6D8),
        'ready': Color(0xFF22A06B),
        'out': Color(0xFFE8742A),
        'delivered': Color(0xFF9AA6B6),
      }[s]!;

  static String _work(ShopData d, Staff s, String Function(String) t) {
    final a = d.todayAttendance(s.id);
    final n = d.actionsToday(s.id);
    final when = a == null ? t('absent') : t('inAt').replaceAll('{t}', hm(a.inAt));
    return '$when · ${t('actionsToday').replaceAll('{n}', '$n')}';
  }

  static Widget _duty(ShopData d, Staff s, String Function(String) t) {
    final a = d.todayAttendance(s.id);
    final on = a != null && a.outAt == null;
    final bg = a == null ? const Color(0xFFEDF0F4) : (on ? const Color(0xFFDCF5E8) : const Color(0xFFE6EEFC));
    final fg = a == null ? const Color(0xFF475569) : (on ? const Color(0xFF146C43) : const Color(0xFF1F4FB0));
    final label = a == null ? t('absent') : (on ? t('onDuty') : t('offDuty'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  static String _date(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }
}


/// Asks, removes all sample (demo) records from this phone and the cloud, and says what is left.
Future<void> deleteSampleFlow(BuildContext context, AppState app) async {
  final d = app.data!;
  final ok = await confirm(
      context,
      L(app, 'Delete sample data?', 'सैंपल डेटा हटाएँ?'),
      L(app, 'All demo branches, staff, customers, orders, expenses and reports will be removed from this phone and the cloud. Your own entries stay.',
          'सारी डेमो ब्रांच, स्टाफ, ग्राहक, ऑर्डर, खर्चे और रिपोर्ट इस फ़ोन और क्लाउड से हट जाएँगे। आपकी अपनी एंट्री रहेंगी।'),
      danger: true);
  if (!ok) return;
  final n = d.clearSample();
  app.setBranchFilter(null);
  await d.flush();
  if (context.mounted) {
    toast(context, L(app, 'Sample data deleted ($n records). Now add your own branches, staff and orders.', 'सैंपल डेटा हट गया ($n)। अब अपनी ब्रांच, स्टाफ और ऑर्डर डालें।'));
  }
}
