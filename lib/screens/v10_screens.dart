import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/issue_models.dart';
import '../data/ops_models.dart';
import '../data/shop_data.dart';
import '../services/export_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/branch_switch.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'customers_screen.dart';

String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// ======================= machines =======================

class MachinesScreen extends StatelessWidget {
  const MachinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final scope = app.staffUser?.branchId ?? app.scopeBranch;
    final list = d.machines.where((m) => scope == null || m.branchId.isEmpty || m.branchId == scope).toList();
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Machines', 'मशीनें')), actions: const [BranchSwitch()]),
      floatingActionButton: app.isOwner
          ? FloatingActionButton.extended(onPressed: () => _add(context, app), icon: const Icon(Icons.add), label: Text(L(app, 'Add machine', 'मशीन जोड़ें')))
          : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
        if (list.isEmpty) EmptyState(icon: Icons.local_laundry_service_outlined, text: L(app, 'Add your washing machines, dryers, steam press…', 'अपनी वॉशिंग मशीन, ड्रायर, स्टीम प्रेस… जोड़ें')),
        for (final m in list)
          Builder(builder: (_) {
            final faults = d.requests.where((r) => r.kind == 'fault' && r.itemId == m.id && r.open).toList();
            final bad = m.status == 'broken' || faults.isNotEmpty;
            return Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: bad ? const Color(0xFFB42318) : (m.serviceDue ? const Color(0xFFE8A317) : LD.line))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(bad ? Icons.report_gmailerrorred : Icons.local_laundry_service_outlined, color: bad ? const Color(0xFFB42318) : LD.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${m.name} · ${m.kind}', style: heading(15, weight: FontWeight.w700))),
                    Text(bad ? L(app, 'NOT WORKING', 'खराब') : L(app, 'OK', 'ठीक'), style: TextStyle(fontWeight: FontWeight.w800, color: bad ? const Color(0xFFB42318) : LD.success)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                      '${L(app, 'Last service', 'पिछली सर्विस')}: ${m.lastService == null ? '—' : dmy(m.lastService!)} · '
                      '${L(app, 'next', 'अगली')}: ${m.nextService == null ? '—' : dmy(m.nextService!)}${m.serviceDue ? ' ⚠' : ''}'
                      '${d.branches.length > 1 ? ' · ${d.branch(m.branchId)?.name ?? ''}' : ''}',
                      style: TextStyle(color: m.serviceDue ? const Color(0xFF8A5A00) : LD.slate)),
                  for (final f in faults) Text('⚠ ${d.nameOf(f.by)}: ${f.note.isEmpty ? L(app, 'reported a problem', 'खराबी बताई') : f.note} · ${whenText(f.at)}', style: const TextStyle(color: Color(0xFFB42318))),
                  if (m.note.isNotEmpty) Text(m.note, style: const TextStyle(fontSize: 12, color: LD.slate)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (!app.canManage)
                      OutlinedButton.icon(
                        onPressed: () => _fault(context, app, m),
                        icon: const Icon(Icons.report_problem_outlined, size: 18),
                        label: Text(L(app, 'Report problem', 'खराबी बताएँ')),
                      ),
                    if (app.canManage) ...[
                      FilledButton.tonalIcon(
                        onPressed: () => _service(context, app, m, faults),
                        icon: const Icon(Icons.build_outlined, size: 18),
                        label: Text(bad ? L(app, 'Repaired', 'ठीक हो गई') : L(app, 'Serviced today', 'आज सर्विस हुई')),
                      ),
                      if (!bad)
                        TextButton(
                          onPressed: () {
                            m.status = 'broken';
                            d.log(app.actorId, 'machine.fault', text: m.name);
                            d.changed();
                          },
                          child: Text(L(app, 'Mark broken', 'खराब मार्क करें'), style: const TextStyle(color: Color(0xFFB42318))),
                        ),
                    ],
                  ]),
                ]),
              ),
            );
          }),
      ]),
    );
  }

  void _add(BuildContext context, AppState app) {
    final d = app.data!;
    final name = TextEditingController();
    final every = TextEditingController(text: '90');
    var kind = 'Washer';
    var branch = app.scopeBranch ?? d.branches.first.id;
    sheet(context, L(app, 'Add machine', 'मशीन जोड़ें'), (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, decoration: fieldDeco(L(app, 'Name (e.g. LG 10 kg)', 'नाम (जैसे LG 10 kg)'))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in ['Washer', 'Dryer', 'Steam press', 'Boiler', 'Other']) Pill(label: k, on: kind == k, onTap: () => set(() => kind = k)),
            ]),
            if (d.branches.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final b in d.branches) Pill(label: b.name, on: branch == b.id, onTap: () => set(() => branch = b.id))]),
            ],
            const SizedBox(height: 10),
            TextField(controller: every, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Service every … days', 'हर … दिन में सर्विस'))),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                if (name.text.trim().length < 2) return;
                d.addMachine(name.text, branchId: branch, kind: kind, everyDays: int.tryParse(every.text) ?? 90);
                Navigator.pop(c);
              },
              child: Text(app.t('save')),
            ),
          ]);
        }));
  }

  void _fault(BuildContext context, AppState app, Machine m) {
    final note = TextEditingController();
    sheet(context, '${m.name} – ${L(app, 'problem', 'खराबी')}', (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: note, autofocus: true, decoration: fieldDeco(L(app, 'What happened? (not spinning, leaking…)', 'क्या हुआ? (घूम नहीं रही, पानी लीक…)'))),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
            onPressed: () {
              app.data!.reportFault(m, by: app.actorId, branchId: app.staffUser?.branchId ?? m.branchId, note: note.text);
              Navigator.pop(c);
              toast(context, L(app, 'Boss is told.', 'बॉस को बता दिया।'));
            },
            child: Text(L(app, 'Tell the boss', 'बॉस को बताएँ')),
          ),
        ]));
  }

  void _service(BuildContext context, AppState app, Machine m, List<StaffRequest> faults) {
    final cost = TextEditingController();
    final note = TextEditingController();
    sheet(context, m.name, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: cost, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Cost (adds to expenses)', 'खर्च (खर्चे में जुड़ेगा)'), icon: Icons.currency_rupee)),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: fieldDeco(L(app, 'What was done', 'क्या किया'))),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              final d = app.data!;
              d.serviceMachine(m, by: app.actorId, cost: double.tryParse(cost.text) ?? 0, note: note.text);
              for (final f in faults) {
                d.decideRequest(f, 'given', by: app.actorId, reply: L(app, 'Repaired', 'ठीक हो गई'));
              }
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }
}

// ======================= meters =======================

class MetersScreen extends StatelessWidget {
  const MetersScreen({super.key});
  static const kinds = {'electricity': ('Electricity', 'बिजली', 'units'), 'water': ('Water', 'पानी', 'L'), 'gas': ('Gas', 'गैस', 'kg')};

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final b = app.staffUser?.branchId ?? app.scopeBranch ?? d.branches.first.id;
    final n = DateTime.now();
    final m0 = DateTime(n.year, n.month, 1);
    final p0 = DateTime(n.year, n.month - 1, 1);
    final kg = d.kgWashed(m0, n.add(const Duration(days: 1)), branchId: b);
    return Scaffold(
      appBar: AppBar(title: Text('${L(app, 'Meter readings', 'मीटर रीडिंग')}${d.branches.length > 1 ? ' · ${d.branch(b)?.name ?? ''}' : ''}'), actions: const [BranchSwitch()]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        for (final e in kinds.entries)
          Builder(builder: (_) {
            final l = d.readings.where((r) => r.kind == e.key && r.branchId == b).toList()..sort((a, c) => c.at.compareTo(a.at));
            final used = d.meterUsed(e.key, b, m0, n.add(const Duration(days: 1)));
            final usedPrev = d.meterUsed(e.key, b, p0, m0);
            final rate = d.meterRates[e.key] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SectionCard(
                title: L(app, e.value.$1, e.value.$2),
                action: TextButton.icon(onPressed: () => _add(context, app, e.key, b), icon: const Icon(Icons.add, size: 18), label: Text(L(app, 'Reading', 'रीडिंग'))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${L(app, 'This month', 'इस महीने')}: ${_q(used)} ${e.value.$3}${rate > 0 ? ' ≈ ${money(used * rate, cur)}' : ''}', style: heading(16, weight: FontWeight.w700)),
                  Text('${L(app, 'Last month', 'पिछले महीने')}: ${_q(usedPrev)} ${e.value.$3}${rate > 0 ? ' ≈ ${money(usedPrev * rate, cur)}' : ''}', style: const TextStyle(color: LD.slate)),
                  if (kg > 0 && used > 0) Text('${L(app, 'Per 10 kg clothes', 'हर 10 kg कपड़े पर')}: ${(used / kg * 10).toStringAsFixed(2)} ${e.value.$3}', style: const TextStyle(color: LD.slate)),
                  if (l.isEmpty)
                    Text(L(app, 'Write the meter number every morning (or every week).', 'हर सुबह (या हर हफ्ते) मीटर नंबर लिखें।'), style: const TextStyle(fontSize: 12, color: LD.slate))
                  else
                    for (final r in l.take(4)) Text('${dmy(r.at)} ${hm(r.at)} · ${_q(r.value)} · ${d.nameOf(r.by)}', style: const TextStyle(fontSize: 12)),
                  if (app.isOwner)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: () => _rate(context, app, e.key), child: Text('${L(app, 'Rate per unit', 'प्रति यूनिट रेट')}: ${money(rate, cur)}')),
                    ),
                ]),
              ),
            );
          }),
      ]),
    );
  }

  void _add(BuildContext context, AppState app, String kind, String b) {
    final v = TextEditingController();
    sheet(context, L(app, kinds[kind]!.$1, kinds[kind]!.$2), (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: v, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDeco(L(app, 'Meter shows', 'मीटर में लिखा है'))),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              final x = double.tryParse(v.text);
              if (x == null || x < 0) return;
              app.data!.addReading(kind, b, x, by: app.actorId);
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }

  void _rate(BuildContext context, AppState app, String kind) {
    final d = app.data!;
    final v = TextEditingController(text: '${d.meterRates[kind] ?? 0}');
    sheet(context, L(app, 'Rate per unit', 'प्रति यूनिट रेट'), (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: v, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDeco(L(app, 'Rate', 'रेट'), icon: Icons.currency_rupee)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              d.meterRates[kind] = double.tryParse(v.text) ?? 0;
              d.changed();
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }
}

// ======================= staff report: late, overtime, leave, mistakes, loans, training =======================

class StaffReportScreen extends StatefulWidget {
  const StaffReportScreen({super.key});
  @override
  State<StaffReportScreen> createState() => _StaffReportScreenState();
}

class _StaffReportScreenState extends State<StaffReportScreen> {
  int _back = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final n = DateTime.now();
    final m0 = DateTime(n.year, n.month - _back, 1);
    final month = monthKey(m0);
    final team = d.staff.where((s) => s.active && (app.scopeBranch == null || s.branchId == app.scopeBranch)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Staff report', 'स्टाफ रिपोर्ट')), actions: const [BranchSwitch()]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Row(children: [
          IconButton(onPressed: () => setState(() => _back++), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Center(child: Text('${_months[m0.month - 1]} ${m0.year}', style: heading(16, weight: FontWeight.w700)))),
          IconButton(onPressed: _back == 0 ? null : () => setState(() => _back--), icon: const Icon(Icons.chevron_right)),
        ]),
        for (final s in team)
          Builder(builder: (_) {
            final r = d.shiftReport(s, month);
            final leave = d.leaveDaysIn(s.id, month);
            final notes = d.staffNotes.where((x) => x.staffId == s.id && monthKey(x.at) == month).toList();
            final mistakes = notes.where((x) => x.kind == 'mistake').toList();
            final praise = notes.where((x) => x.kind == 'praise').length;
            final issues = d.issues.where((i) => i.fault.contains(s.id) && monthKey(i.openedAt) == month).length;
            final loans = d.loans.where((l) => l.staffId == s.id && l.leftAfter(month) > 0 || (l.staffId == s.id && l.cutIn(month) > 0)).toList();
            final trained = d.trainingItems.where((t) => s.training[t] == true).length;
            return Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LD.line)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Avatar(s.initials, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.name, style: heading(15, weight: FontWeight.w700)),
                        Text('${roleText(app, s.role)}${s.shiftStart.isEmpty ? '' : ' · ${s.shiftStart}–${s.shiftEnd}'}', style: const TextStyle(fontSize: 12, color: LD.slate)),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'mistake' || v == 'praise') {
                          _note(context, app, s, v);
                        } else if (v == 'loan') {
                          _loan(context, app, s);
                        } else {
                          _training(context, app, s);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'mistake', child: Text(L(app, 'Write a mistake (fine)', 'गलती लिखें (जुर्माना)'))),
                        PopupMenuItem(value: 'praise', child: Text(L(app, 'Write a praise', 'तारीफ़ लिखें'))),
                        if (app.isOwner) PopupMenuItem(value: 'loan', child: Text(L(app, 'Give loan (cut monthly)', 'लोन दें (हर महीने कटे)'))),
                        PopupMenuItem(value: 'training', child: Text(L(app, 'Training checklist', 'ट्रेनिंग चेकलिस्ट'))),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 14, runSpacing: 6, children: [
                    _chip(L(app, 'Present', 'हाज़िर'), '${r.days} ${L(app, 'days', 'दिन')}', LD.navy),
                    _chip(L(app, 'Late', 'लेट'), '${r.lateDays}× · ${r.lateMin} min', r.lateDays > 0 ? const Color(0xFFB42318) : LD.slate),
                    _chip(L(app, 'Overtime', 'ओवरटाइम'), '${(r.overMin / 60).toStringAsFixed(1)} h', LD.success),
                    _chip(L(app, 'Leave', 'छुट्टी'), '$leave', LD.slate),
                    _chip(L(app, 'Mistakes', 'गलतियाँ'), '${mistakes.length + issues}', mistakes.length + issues > 0 ? const Color(0xFFB42318) : LD.slate),
                    _chip(L(app, 'Praise', 'तारीफ़'), '$praise', LD.success),
                    _chip(L(app, 'Training', 'ट्रेनिंग'), '$trained/${d.trainingItems.length}', LD.primary),
                  ]),
                  if (s.shiftStart.isEmpty)
                    Text(L(app, 'Set shift time in Staff → Edit to see late / overtime.', 'लेट / ओवरटाइम देखने के लिए Staff → Edit में शिफ्ट टाइम डालें।'), style: const TextStyle(fontSize: 11, color: LD.slate)),
                  for (final x in mistakes)
                    Text('• ${x.text}${x.fine > 0 ? ' (−${money(x.fine, cur)})' : ''} · ${dmy(x.at)}', style: const TextStyle(fontSize: 12, color: Color(0xFFB42318))),
                  for (final l in loans)
                    Text('• ${L(app, 'Loan', 'लोन')} ${money(l.amount, cur)}: ${L(app, 'cut', 'कटौती')} ${money(l.cutIn(month), cur)} · ${L(app, 'left', 'बाकी')} ${money(l.leftAfter(month), cur)}',
                        style: const TextStyle(fontSize: 12)),
                ]),
              ),
            );
          }),
      ]),
    );
  }

  Widget _chip(String k, String v, Color c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
        Text(k, style: const TextStyle(fontSize: 11, color: LD.slate)),
      ]);

  void _note(BuildContext context, AppState app, Staff s, String kind) {
    final text = TextEditingController();
    final fine = TextEditingController();
    sheet(context, '${s.name} – ${kind == 'mistake' ? L(app, 'mistake', 'गलती') : L(app, 'praise', 'तारीफ़')}', (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: text, autofocus: true, decoration: fieldDeco(L(app, 'What happened', 'क्या हुआ'))),
          if (kind == 'mistake' && app.isOwner) ...[
            const SizedBox(height: 10),
            TextField(controller: fine, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Fine from salary (optional)', 'सैलरी से जुर्माना (ज़रूरी नहीं)'), icon: Icons.currency_rupee)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              if (text.text.trim().length < 2) return;
              app.data!.addStaffNote(s.id, kind, text.text, by: app.actorId, fine: double.tryParse(fine.text) ?? 0);
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }

  void _loan(BuildContext context, AppState app, Staff s) {
    final amt = TextEditingController();
    final mon = TextEditingController();
    final note = TextEditingController();
    final n = DateTime.now();
    var start = monthKey(DateTime(n.year, n.month + 1, 1));
    sheet(context, '${s.name} – ${L(app, 'loan', 'लोन')}', (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: amt, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Loan amount', 'लोन की रकम'), icon: Icons.currency_rupee)),
            const SizedBox(height: 10),
            TextField(controller: mon, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Cut every month', 'हर महीने कटेगा'), icon: Icons.currency_rupee)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              Pill(label: L(app, 'From this month', 'इसी महीने से'), on: start == monthKey(n), onTap: () => set(() => start = monthKey(n))),
              Pill(label: L(app, 'From next month', 'अगले महीने से'), on: start != monthKey(n), onTap: () => set(() => start = monthKey(DateTime(n.year, n.month + 1, 1)))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: fieldDeco(L(app, 'Note', 'नोट'))),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                final a = double.tryParse(amt.text) ?? 0, m = double.tryParse(mon.text) ?? 0;
                if (a <= 0 || m <= 0) return;
                app.data!.addLoan(s.id, a, m, start, by: app.actorId, note: note.text);
                Navigator.pop(c);
              },
              child: Text(app.t('save')),
            ),
          ]);
        }));
  }

  void _training(BuildContext context, AppState app, Staff s) {
    final d = app.data!;
    final add = TextEditingController();
    sheet(context, '${s.name} – ${L(app, 'training', 'ट्रेनिंग')}', (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final t in d.trainingItems)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t),
                value: s.training[t] == true,
                onChanged: app.canManage
                    ? (v) {
                        set(() => s.training[t] = v == true);
                        d.changed();
                      }
                    : null,
              ),
            if (app.isOwner)
              Row(children: [
                Expanded(child: TextField(controller: add, decoration: fieldDeco(L(app, 'Add a training item', 'ट्रेनिंग आइटम जोड़ें')))),
                IconButton(
                  onPressed: () {
                    if (add.text.trim().length < 2) return;
                    set(() => d.trainingItems.add(add.text.trim()));
                    add.clear();
                    d.changed();
                  },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]),
          ]);
        }));
  }
}

String roleText(AppState app, Role r) => switch (r) {
      Role.manager => L(app, 'Manager', 'मैनेजर'),
      Role.counter => L(app, 'Counter', 'काउंटर'),
      Role.washer => L(app, 'Washer / ironer', 'धुलाई / प्रेस'),
      Role.delivery => L(app, 'Delivery', 'डिलीवरी'),
      Role.owner => L(app, 'Owner', 'मालिक'),
    };

// ======================= business insights: graphs, services, lost customers, delivery, GST =======================

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _back = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final scope = app.scopeBranch;
    final n = DateTime.now();
    final from = DateTime(n.year, n.month - _back, 1);
    final to = DateTime(n.year, n.month - _back + 1, 1);
    final six = d.monthlySales(6, branchId: scope);
    final busy = d.busyTimes(DateTime(n.year, n.month - 2, 1), to, branchId: scope);
    final svc = d.serviceRevenue(from, to, branchId: scope).entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final svcTotal = svc.fold<double>(0, (s, e) => s + e.value.$1);
    final lost = d.lostRegulars();
    final agents = d.staff.where((s) => s.active && s.role == Role.delivery && (scope == null || s.branchId == scope)).toList();
    final gstOrders = d.ordersIn(scope).where((o) => o.status != 'cancelled' && !o.createdAt.isBefore(from) && o.createdAt.isBefore(to)).toList();
    final taxable = gstOrders.fold<double>(0, (s, o) => s + o.taxable);
    final tax = gstOrders.fold<double>(0, (s, o) => s + o.tax);
    final maxHour = busy.$2.fold<int>(0, (m, v) => v > m ? v : m);
    final peak = maxHour == 0 ? -1 : busy.$2.indexOf(maxHour);
    final maxDay = busy.$1.fold<int>(0, (m, v) => v > m ? v : m);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Business insights', 'बिज़नेस की समझ')), actions: const [BranchSwitch()]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Row(children: [
          IconButton(onPressed: () => setState(() => _back++), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Center(child: Text('${_months[from.month - 1]} ${from.year}', style: heading(16, weight: FontWeight.w700)))),
          IconButton(onPressed: _back == 0 ? null : () => setState(() => _back--), icon: const Icon(Icons.chevron_right)),
        ]),
        SectionCard(
          title: L(app, 'Sales – last 6 months', 'बिक्री – पिछले 6 महीने'),
          child: Bars(values: six.map((e) => e.$2).toList(), labels: six.map((e) => _months[int.parse(e.$1.substring(5)) - 1]).toList()),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Busiest days & time (last 3 months)', 'सबसे व्यस्त दिन और समय (3 महीने)'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Bars(values: busy.$1.map((e) => e.toDouble()).toList(), labels: days, height: 90),
            const SizedBox(height: 8),
            Bars(values: [for (var h = 7; h <= 22; h++) busy.$2[h].toDouble()], labels: [for (var h = 7; h <= 22; h++) h % 3 == 0 ? '$h' : ''], height: 80, color: LD.success),
            const SizedBox(height: 6),
            if (maxDay > 0)
              Text('${L(app, 'Busiest', 'सबसे व्यस्त')}: ${days[busy.$1.indexOf(maxDay)]}${peak >= 0 ? ', $peak:00–${peak + 1}:00' : ''} → ${L(app, 'keep more staff then', 'तब ज़्यादा स्टाफ रखें')}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Earning by service', 'सर्विस के हिसाब से कमाई'),
          child: Column(children: [
            if (svc.isEmpty) Text(L(app, 'No orders this month.', 'इस महीने कोई ऑर्डर नहीं।'), style: const TextStyle(color: LD.slate)),
            for (final e in svc)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(hiName(app, e.key), style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text(money(e.value.$1, cur), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  LinearProgressIndicator(value: svcTotal == 0 ? 0 : e.value.$1 / svcTotal, minHeight: 6, backgroundColor: const Color(0xFFEDF0F4)),
                  Text('${(svcTotal == 0 ? 0 : e.value.$1 / svcTotal * 100).toStringAsFixed(0)}% · ${_q(e.value.$2)} ${L(app, 'pcs/kg', 'पीस/kg')} · '
                      '${L(app, 'avg', 'औसत')} ${money(e.value.$2 == 0 ? 0 : e.value.$1 / e.value.$2, cur)} · ${e.value.$3} ${L(app, 'orders', 'ऑर्डर')}',
                      style: const TextStyle(fontSize: 11, color: LD.slate)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '${L(app, 'Regular customers who stopped coming', 'जो पक्के ग्राहक आना बंद कर दिए')} (${lost.length})',
          child: Column(children: [
            if (lost.isEmpty) Text(L(app, 'None – good!', 'कोई नहीं – बढ़िया!'), style: const TextStyle(color: LD.success)),
            for (final c in lost.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(c.name),
                subtitle: Text('${L(app, 'last', 'आख़िरी')} ${dmy(d.lastVisit(c.id)!)} · ${L(app, 'spent', 'खर्च')} ${money(d.spendOf(c.id), cur)}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => callPhone(c.phone)),
                  IconButton(
                      icon: const Icon(Icons.chat_outlined),
                      onPressed: () => openWhatsApp(c.phone, 'Namaste ${c.name}, we miss you at ${app.shop!.shopName}! 10% off on your next order this week – free pickup.')),
                ]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id))),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (agents.isNotEmpty)
          SectionCard(
            title: L(app, 'Delivery report', 'डिलीवरी रिपोर्ट'),
            child: Column(children: [
              for (final a in agents)
                Builder(builder: (_) {
                  final r = d.deliveryStats(a.id, from, to);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Avatar(a.initials, size: 32),
                    title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${r.drops} ${L(app, 'deliveries', 'डिलीवरी')} · ${r.pickups} ${L(app, 'pickups', 'पिकअप')} · '
                        '${r.avgMin.toStringAsFixed(0)} ${L(app, 'min avg', 'मिनट औसत')} · ${r.km.toStringAsFixed(1)} km · ${r.onTime.toStringAsFixed(0)}% ${L(app, 'on time', 'समय पर')}'),
                  );
                }),
            ]),
          ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'GST',
          action: TextButton.icon(
            onPressed: () => ExportService.shareCsv(ExportService.gstCsv(d, from, to, branchId: scope), 'gst-${monthKey(from)}.csv'),
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: const Text('Excel/CSV'),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${L(app, 'Bills', 'बिल')}: ${gstOrders.length} · ${L(app, 'Taxable value', 'टैक्स योग्य')}: ${money(taxable, cur)}'),
            Text('CGST: ${money(tax / 2, cur)} · SGST: ${money(tax / 2, cur)} · ${L(app, 'Total GST', 'कुल GST')}: ${money(tax, cur)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (tax == 0)
              Text(L(app, 'GST is 0%. Set GST % in Settings if you charge GST.', 'GST 0% है। GST लेते हैं तो Settings में GST % डालें।'), style: const TextStyle(fontSize: 12, color: LD.slate)),
            if (app.isOwner)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => _gstin(context, app), child: Text('GSTIN: ${d.gstin.isEmpty ? L(app, 'add', 'जोड़ें') : d.gstin}')),
              ),
          ]),
        ),
      ]),
    );
  }

  void _gstin(BuildContext context, AppState app) {
    final d = app.data!;
    final v = TextEditingController(text: d.gstin);
    sheet(context, 'GSTIN', (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: v, textCapitalization: TextCapitalization.characters, decoration: fieldDeco('GSTIN (15)')),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              final x = v.text.trim().toUpperCase();
              if (x.isNotEmpty && !RegExp(r'^[0-9]{2}[A-Z0-9]{13}$').hasMatch(x)) {
                toast(c, L(app, 'GSTIN should be 15 letters/numbers.', 'GSTIN 15 अक्षर/नंबर का होता है।'));
                return;
              }
              d.gstin = x;
              d.changed();
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }
}

// ======================= daily backup reminder =======================

const lastBackupKey = 'ld_last_backup';

Future<void> markBackupDone() async {
  final p = await SharedPreferences.getInstance();
  await p.setString(lastBackupKey, DateTime.now().toIso8601String());
}

class BackupReminder extends StatefulWidget {
  const BackupReminder({super.key, required this.onBackup});
  final Future<void> Function() onBackup;
  @override
  State<BackupReminder> createState() => _BackupReminderState();
}

class _BackupReminderState extends State<BackupReminder> {
  DateTime? _last;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _last = DateTime.tryParse(p.getString(lastBackupKey) ?? '');
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!_loaded || !app.isOwner) return const SizedBox.shrink();
    final days = _last == null ? 999 : DateTime.now().difference(_last!).inDays;
    if (days < 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: const Color(0xFFE6EEFC),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: const Icon(Icons.backup_outlined, color: LD.primary),
          title: Text(_last == null ? L(app, 'Keep a backup copy today', 'आज बैकअप कॉपी रखें') : '${L(app, 'Last backup', 'पिछला बैकअप')}: $days ${L(app, 'days ago', 'दिन पहले')}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: LD.navy)),
          subtitle: Text(L(app, 'One tap – send it to your WhatsApp / email / Drive.', 'एक टैप – अपने WhatsApp / ईमेल / Drive पर भेजें।')),
          trailing: FilledButton(
            onPressed: () async {
              await widget.onBackup();
              await markBackupDone();
              if (mounted) setState(() => _last = DateTime.now());
            },
            child: Text(L(app, 'Backup', 'बैकअप')),
          ),
        ),
      ),
    );
  }
}


void textSizeSheet(BuildContext context, AppState app) {
  sheet(context, L(app, 'Text size (this phone)', 'अक्षर का साइज़ (इस फ़ोन पर)'), (c) => Column(children: [
        for (final v in const [1.0, 1.15, 1.3])
          ListTile(
            title: Text(v == 1.0 ? L(app, 'Normal', 'सामान्य') : (v == 1.15 ? L(app, 'Big', 'बड़ा') : L(app, 'Very big', 'बहुत बड़ा')), style: TextStyle(fontSize: 15 * v)),
            trailing: app.textScale == v ? const Icon(Icons.check_circle, color: LD.success) : null,
            onTap: () {
              app.setTextScale(v);
              Navigator.pop(c);
            },
          ),
      ]));
}
