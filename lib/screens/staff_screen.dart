import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../data/reports.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/branch_switch.dart';
import '../widgets/ui.dart';
import 'payroll_screens.dart';

/// Owner / manager: team, attendance and performance (staff tracking module).
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  Period _period = Period.week;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final scope = app.scopeBranch;
    final team = d.staff.where((s) => s.active && (scope == null || s.branchId == scope)).toList()
      ..sort((a, b) => a.role.index.compareTo(b.role.index));
    final tracking = app.module('staffTracking');

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('staff')),
          actions: const [BranchSwitch()],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: t('team')), Tab(text: t('attendance')), Tab(text: t('performance')), Tab(text: L(app, 'Payroll & ranks', 'पगार और रैंक'))]),
        ),
        floatingActionButton: app.canManage
            ? FloatingActionButton.extended(
                onPressed: () => app.limit('staff') != null ? toast(context, t(app.limit('staff')!)) : _addStaff(context, app),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(t('addStaff')),
              )
            : null,
        body: TabBarView(children: [
          // TEAM
          team.isEmpty
              ? ListView(children: [EmptyState(icon: Icons.groups_rounded, text: t('noStaff'))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: team.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = team[i];
                    final a = d.todayAttendance(s.id);
                    final on = a != null && a.outAt == null;
                    return Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
                      child: ListTile(
                        leading: Avatar(s.initials, color: avatarColor(s.id)),
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${roleLabel(s.role, t)} · ${d.branch(s.branchId)?.name ?? ''}\n'
                          '${a == null ? t('absent') : t('inAt').replaceAll('{t}', hm(a.inAt))}'
                          '${tracking ? ' · ${t('actionsToday').replaceAll('{n}', '${d.actionsToday(s.id)}')}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: _DutyChip(on: on, absent: a == null, t: t),
                        onTap: () => _staffSheet(context, app, s),
                      ),
                    );
                  },
                ),
          // ATTENDANCE
          ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
            for (var day = 0; day < 7; day++) ...[
              Builder(builder: (_) {
                final dt = DateTime.now().subtract(Duration(days: day));
                final k = dayKey(dt);
                final present = d.attendance.where((a) => a.day == k && team.any((s) => s.id == a.staffId)).toList();
                return SectionCard(
                  title: day == 0 ? t('today') : dmy(dt),
                  action: Text('${present.length}/${team.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  child: Column(children: [
                    for (final s in team)
                      Builder(builder: (_) {
                        final a = present.where((x) => x.staffId == s.id).firstOrNull;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Icon(a == null ? Icons.cancel_outlined : Icons.check_circle, size: 18, color: a == null ? const Color(0xFFB42318) : LD.success),
                            const SizedBox(width: 8),
                            Expanded(child: Text(s.name)),
                            Text(
                              a == null ? '—' : '${hm(a.inAt)}${a.outAt == null ? '' : ' – ${hm(a.outAt!)}'}',
                              style: const TextStyle(fontSize: 12, color: LD.slate),
                            ),
                          ]),
                        );
                      }),
                  ]),
                );
              }),
              const SizedBox(height: 10),
            ],
          ]),
          // PERFORMANCE
          ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
            Wrap(spacing: 8, children: [
              for (final p in [Period.today, Period.week, Period.month])
                Pill(label: t(p == Period.today ? 'today' : (p == Period.week ? 'week' : 'month')), on: _period == p, onTap: () => setState(() => _period = p)),
            ]),
            const SizedBox(height: 12),
            if (!tracking) Text(t('moduleOff'), style: const TextStyle(color: LD.slate)),
            if (tracking)
              Builder(builder: (_) {
                final stats = StaffStats.build(
                  activity: d.activity,
                  orders: d.orders,
                  attendance: d.attendance,
                  range: DateRange.of(_period),
                );
                return Column(children: [
                  for (final s in team) ...[
                    SectionCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Avatar(s.initials, color: avatarColor(s.id), size: 34),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                          Text(roleLabel(s.role, t), style: const TextStyle(fontSize: 12, color: LD.slate)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          _num(t('booked'), '${stats[s.id]?.ordersBooked ?? 0}'),
                          _num(t('updates'), '${stats[s.id]?.statusUpdates ?? 0}'),
                          _num(t('deliveries'), '${(stats[s.id]?.deliveries ?? 0) + (stats[s.id]?.pickups ?? 0)}'),
                          _num(t('collectedBy'), money(stats[s.id]?.cashCollected ?? 0, cur)),
                          _num(t('days'), '${stats[s.id]?.daysPresent ?? 0}'),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],
                ]);
              }),
          ]),
          const PayrollTab(),
        ]),
      ),
    );
  }

  Widget _num(String label, String v) => Expanded(
        child: Column(children: [
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: LD.slate)),
        ]),
      );

  void _staffSheet(BuildContext context, AppState app, Staff s) {
    final d = app.data!;
    final t = app.t;
    final today = dayKey(DateTime.now());
    final acts = d.activity.where((a) => a.by == s.id && dayKey(a.at) == today).toList().reversed.take(20).toList();
    sheet(context, s.name, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${roleLabel(s.role, t)} · ${d.branch(s.branchId)?.name ?? ''} · +${s.phone}', style: const TextStyle(color: LD.slate)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: d.todayAttendance(s.id) == null
                    ? () {
                        d.checkIn(s.id);
                        Navigator.pop(c);
                      }
                    : null,
                child: Text(t('checkIn')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonal(
                onPressed: d.todayAttendance(s.id)?.outAt == null && d.todayAttendance(s.id) != null
                    ? () {
                        d.checkOut(s.id);
                        Navigator.pop(c);
                      }
                    : null,
                child: Text(t('checkOut')),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => callPhone(s.phone), icon: const Icon(Icons.call_outlined), label: Text(t('call'))),
          const SizedBox(height: 12),
          Text(t('actionsToday').replaceAll('{n}', '${acts.length}'), style: heading(15, weight: FontWeight.w700)),
          for (final a in acts)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bolt_outlined, size: 18),
              title: Text('${_kindText(a.kind, t)} ${a.text}'),
              trailing: Text(hm(a.at), style: const TextStyle(color: LD.slate)),
            ),
          if (app.isOwner) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(c);
                _editStaff(context, app, s);
              },
              icon: const Icon(Icons.edit_outlined),
              label: Text(L(app, 'Edit: branch, role, salary, PIN', 'बदलें: ब्रांच, रोल, सैलरी, PIN')),
            ),
          ],
          if (app.canManage) ...[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFB42318)),
              onPressed: () async {
                if (await confirm(context, t('deactivate'), s.name, danger: true)) {
                  s.active = false;
                  d.changed();
                  if (c.mounted) Navigator.pop(c);
                }
              },
              child: Text(t('deactivate')),
            ),
          ],
        ]));
  }

  void _editStaff(BuildContext context, AppState app, Staff s) {
    final d = app.data!;
    final t = app.t;
    final name = TextEditingController(text: s.name);
    final salary = TextEditingController(text: s.salary == 0 ? '' : s.salary.toStringAsFixed(0));
    final pin = TextEditingController();
    var role = s.role;
    var branch = d.branch(s.branchId) == null ? d.branches.first.id : s.branchId;
    sheet(context, s.name, (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, decoration: fieldDeco(t('name'), icon: Icons.person_outline)),
            const SizedBox(height: 10),
            Text(t('role'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in [Role.manager, Role.counter, Role.washer, Role.delivery])
                Pill(label: roleLabel(r, t), on: role == r, onTap: () => set(() => role = r)),
            ]),
            if (d.branches.length > 1) ...[
              const SizedBox(height: 10),
              Text(L(app, 'Works at branch', 'किस ब्रांच में'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final b in d.branches) Pill(label: b.name, on: branch == b.id, onTap: () => set(() => branch = b.id)),
              ]),
            ],
            const SizedBox(height: 10),
            TextField(controller: salary, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Monthly salary', 'मासिक सैलरी'), icon: Icons.currency_rupee)),
            const SizedBox(height: 10),
            TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: fieldDeco(L(app, 'New 4-digit PIN (leave empty to keep)', 'नया 4 अंक PIN (खाली = वही)'), icon: Icons.pin_outlined)),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () {
                if (pin.text.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin.text)) {
                  toast(c, L(app, 'PIN must be 4 digits.', 'PIN 4 अंक का हो।'));
                  return;
                }
                final moved = branch != s.branchId;
                s
                  ..name = name.text.trim().isEmpty ? s.name : name.text.trim()
                  ..role = role
                  ..branchId = branch
                  ..salary = double.tryParse(salary.text) ?? s.salary;
                if (moved) d.log('owner', 'staff.move', text: '${s.name} → ${d.branch(branch)?.name ?? ''}');
                if (pin.text.isNotEmpty) {
                  d.setStaffPin(s, pin.text);
                } else {
                  d.changed();
                }
                Navigator.pop(c);
                toast(context, L(app, 'Saved. Staff must log in again if PIN changed.', 'सेव हो गया। PIN बदला है तो स्टाफ दोबारा लॉगिन करे।'));
              },
              child: Text(t('save')),
            ),
          ]);
        }));
  }

  static String _kindText(String kind, String Function(String) t) {
    if (kind == 'order.new') return t('newOrder');
    if (kind == 'pay') return t('recordPayment');
    if (kind == 'delivery.done') return t('deliveredBtn');
    if (kind == 'pickup.done') return t('pickedUp');
    if (kind.startsWith('status.')) return '→ ${t(kind.substring(7))}';
    if (kind == 'checkin') return t('checkIn');
    if (kind == 'checkout') return t('checkOut');
    return kind;
  }

  void _addStaff(BuildContext context, AppState app) {
    final d = app.data!;
    final t = app.t;
    final name = TextEditingController();
    final phone = TextEditingController();
    final pin = TextEditingController(text: (1000 + DateTime.now().millisecond * 7 % 9000).toString());
    final salary = TextEditingController();
    var role = Role.counter;
    var branch = app.scopeBranch ?? d.branches.first.id;
    sheet(context, t('addStaff'), (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, decoration: fieldDeco(t('name'), icon: Icons.person_outline)),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: fieldDeco(t('phone'), icon: Icons.phone_outlined)),
            const SizedBox(height: 10),
            Text(t('role'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in [Role.manager, Role.counter, Role.washer, Role.delivery])
                Pill(label: roleLabel(r, t), on: role == r, onTap: () => set(() => role = r)),
            ]),
            const SizedBox(height: 10),
            if (d.branches.length > 1)
              DropdownButtonFormField<String>(
                initialValue: branch,
                decoration: fieldDeco(t('branch')),
                items: [for (final b in d.branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
                onChanged: (v) => set(() => branch = v ?? branch),
              ),
            const SizedBox(height: 10),
            TextField(controller: pin, keyboardType: TextInputType.number, maxLength: 4, decoration: fieldDeco(t('pin'), icon: Icons.pin_outlined)),
            TextField(controller: salary, keyboardType: TextInputType.number, decoration: fieldDeco(t('salary'), icon: Icons.payments_outlined)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                final digits = phone.text.replaceAll(RegExp(r'[^0-9]'), '');
                if (name.text.trim().length < 2 || digits.length < 7 || !RegExp(r'^\d{4}$').hasMatch(pin.text)) return;
                d.addStaff(name: name.text, phone: digits, role: role, branchId: branch, pin: pin.text, salary: double.tryParse(salary.text) ?? 0);
                Navigator.pop(c);
                toast(context, t('staffAdded').replaceAll('{c}', d.shopCode).replaceAll('{p}', pin.text));
              },
              child: Text(t('save')),
            ),
          ]);
        }));
  }
}

class _DutyChip extends StatelessWidget {
  const _DutyChip({required this.on, required this.absent, required this.t});
  final bool on;
  final bool absent;
  final String Function(String) t;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = absent
        ? (const Color(0xFFEDF0F4), const Color(0xFF475569), t('absent'))
        : on
            ? (const Color(0xFFDCF5E8), const Color(0xFF146C43), t('onDuty'))
            : (const Color(0xFFE6EEFC), const Color(0xFF1F4FB0), t('offDuty'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
