import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/issue_models.dart';
import '../data/ops_models.dart';
import '../logic/payroll.dart';
import '../services/export_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

Payslip slipFor(AppState app, Staff s, String month) {
  final d = app.data!;
  return buildPayslip(
    s: s,
    month: month,
    orders: d.orders,
    activity: d.activity,
    attendance: d.attendance,
    issues: d.issues,
    payouts: d.payouts,
    rules: d.rules,
    loans: d.loans,
    notes: d.staffNotes,
    leaveDays: d.leaveDaysIn(s.id, month),
  );
}

String monthLabel(String m) {
  const n = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  final p = m.split('-');
  return '${n[int.parse(p[1]) - 1]} ${p[0]}';
}

String shiftMonth(String m, int by) {
  final p = m.split('-');
  final d = DateTime(int.parse(p[0]), int.parse(p[1]) + by);
  return monthKey(d);
}

/// Staff → Payroll tab: leaderboard + everyone's month.
class PayrollTab extends StatefulWidget {
  const PayrollTab({super.key});
  @override
  State<PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<PayrollTab> {
  String _month = monthKey(DateTime.now());
  String _metric = 'sales';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final team = d.staff.where((s) => s.active && (app.scopeBranch == null || s.branchId == app.scopeBranch)).toList();
    final slips = [for (final s in team) slipFor(app, s, _month)];
    double metric(Payslip p) => switch (_metric) {
          'sales' => p.sales,
          'pieces' => p.pieces.toDouble(),
          'delivery' => (p.drops + p.pickups).toDouble(),
          _ => p.collected,
        };
    final ranked = slips.where((p) => metric(p) > 0).toList()..sort((a, b) => metric(b).compareTo(metric(a)));
    final mx = ranked.isEmpty ? 0.0 : metric(ranked.first);
    String fmt(Payslip p) => switch (_metric) {
          'sales' => money(p.sales, cur),
          'pieces' => '${p.pieces} pcs${p.kg > 0 ? ' + ${p.kg.toStringAsFixed(0)} kg' : ''}',
          'delivery' => '${p.drops} + ${p.pickups}',
          _ => money(p.collected, cur),
        };
    final totalNet = slips.fold<double>(0, (s, p) => s + p.net);
    final totalPaid = slips.fold<double>(0, (s, p) => s + p.paid);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => _month = shiftMonth(_month, -1)), icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text(monthLabel(_month), textAlign: TextAlign.center, style: heading(16, weight: FontWeight.w700))),
        IconButton(onPressed: () => setState(() => _month = shiftMonth(_month, 1)), icon: const Icon(Icons.chevron_right)),
      ]),
      if (app.isOwner)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesScreen())),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(L(app, 'Commission rules', 'कमीशन के नियम')),
          ),
        ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in const ['sales', 'pieces', 'delivery', 'collection'])
          Pill(
            label: {
              'sales': L(app, 'Sales', 'बिक्री'),
              'pieces': L(app, 'Pieces', 'पीस'),
              'delivery': L(app, 'Delivery', 'डिलीवरी'),
              'collection': L(app, 'Collection', 'वसूली'),
            }[m]!,
            on: _metric == m,
            onTap: () => setState(() => _metric = m),
          ),
      ]),
      const SizedBox(height: 10),
      SectionCard(
        title: L(app, 'Leaderboard', 'लीडरबोर्ड'),
        child: ranked.isEmpty
            ? Text(L(app, 'No work recorded this month yet.', 'इस महीने अभी कोई काम दर्ज नहीं।'), style: const TextStyle(color: LD.slate))
            : Column(children: [
                for (var i = 0; i < ranked.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == 0 ? LD.sun : (i == 1 ? LD.line : (i == 2 ? const Color(0xFFF3C6A5) : const Color(0xFFEDF0F4))),
                        ),
                        child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(ranked[i].staff.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                            Text(fmt(ranked[i]), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: mx == 0 ? 0 : metric(ranked[i]) / mx,
                              minHeight: 6,
                              color: LD.primary,
                              backgroundColor: const Color(0xFFEDF0F4),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),
              ]),
      ),
      const SizedBox(height: 12),
      if (app.isOwner)
        SectionCard(
          title: L(app, 'Payroll', 'पगार'),
          action: IconButton(
            tooltip: 'Excel (CSV)',
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => ExportService.shareCsv(ExportService.payrollCsv(slips), 'payroll-$_month.csv'),
          ),
          child: Column(children: [
            for (final p in slips)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(p.staff.initials, color: avatarColor(p.staff.id)),
                title: Text(p.staff.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${L(app, 'Salary', 'तनख़्वाह')} ${money(p.staff.salary, cur)} · ${L(app, 'Incentive', 'इंसेंटिव')} ${money(p.incentive, cur)}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(p.balance, cur), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    p.balance <= 0.5 && p.net > 0 ? L(app, 'Paid', 'दे दिया') : L(app, 'To pay', 'देना है'),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.balance <= 0.5 && p.net > 0 ? LD.success : const Color(0xFF8A5A00)),
                  ),
                ]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(staffId: p.staff.id, month: _month))),
              ),
            const Divider(),
            Row(children: [
              Expanded(child: Text(L(app, 'Total this month', 'इस महीने कुल'), style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${money(totalNet, cur)} · ${L(app, 'paid', 'दिया')} ${money(totalPaid, cur)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
    ]);
  }
}

/// One staff member's month (owner view; also used for "My earnings").
class PayslipScreen extends StatefulWidget {
  const PayslipScreen({super.key, required this.staffId, required this.month, this.mine = false});
  final String staffId;
  final String month;
  final bool mine;
  @override
  State<PayslipScreen> createState() => _PayslipScreenState();
}

class _PayslipScreenState extends State<PayslipScreen> {
  late String _month = widget.month;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final s = d.staffBy(widget.staffId);
    if (s == null) return Scaffold(appBar: AppBar());
    final p = slipFor(app, s, _month);

    Widget stat(String v, String l) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: LD.line)),
            child: Column(children: [
              FittedBox(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Text(l, style: const TextStyle(fontSize: 10, color: LD.slate)),
            ]),
          ),
        );

    final work = switch (s.role) {
      Role.counter => [stat('${p.orders}', L(app, 'Orders', 'ऑर्डर')), stat(money(p.sales, cur), L(app, 'Sales', 'बिक्री'))],
      Role.washer => [stat('${p.pieces}', L(app, 'Pieces', 'पीस')), stat('${p.kg.toStringAsFixed(0)} kg', L(app, 'By weight', 'वज़न'))],
      Role.delivery => [stat('${p.drops}', L(app, 'Delivery', 'डिलीवरी')), stat('${p.pickups}', L(app, 'Pickup', 'पिकअप'))],
      _ => [stat(money(p.branchSales, cur), L(app, 'Branch sales', 'ब्रांच बिक्री'))],
    };

    return Scaffold(
      appBar: AppBar(title: Text(widget.mine ? L(app, 'My earnings', 'मेरी कमाई') : s.name)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: LD.navy, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(
                onPressed: () => setState(() => _month = shiftMonth(_month, -1)),
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Expanded(child: Text(monthLabel(_month), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              IconButton(
                onPressed: () => setState(() => _month = shiftMonth(_month, 1)),
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ]),
            Text(money(p.net, cur), style: heading(32, color: Colors.white)),
            Text(
              '${roleLabel(s.role, app.t)} · ${d.branch(s.branchId)?.name ?? ''} · ${p.days} ${L(app, 'days', 'दिन')}',
              style: const TextStyle(color: Color(0xFFC9D6EA)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          ...work.expand((w) => [w, const SizedBox(width: 8)]),
          stat(money(p.collected, cur), L(app, 'Collected', 'वसूली')),
          const SizedBox(width: 8),
          stat('${p.complaints + p.wrongs}', L(app, 'Issues', 'इश्यू')),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Calculation', 'हिसाब'),
          child: Column(children: [
            for (final l in p.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.label),
                      Text(l.calc, style: const TextStyle(fontSize: 11, color: LD.slate)),
                    ]),
                  ),
                  Text(
                    '${l.amount > 0 && l.label != 'Salary' ? '+' : ''}${money(l.amount, cur)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: l.amount < 0 ? const Color(0xFFB42318) : (l.label == 'Salary' ? LD.navy : const Color(0xFF146C43))),
                  ),
                ]),
              ),
            for (final x in p.payouts.where((x) => x.kind != 'paid'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text('${x.kind == 'advance' ? L(app, 'Advance', 'एडवांस') : (x.kind == 'bonus' ? L(app, 'Extra bonus', 'अतिरिक्त बोनस') : L(app, 'Deduction', 'कटौती'))} · ${dmy(x.at)}${x.note.isEmpty ? '' : ' · ${x.note}'}')),
                  Text(
                    '${x.kind == 'bonus' ? '+' : '−'}${money(x.amount, cur)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: x.kind == 'bonus' ? const Color(0xFF146C43) : const Color(0xFFB42318)),
                  ),
                ]),
              ),
            const Divider(),
            Row(children: [
              Expanded(child: Text(L(app, 'To pay', 'देना है'), style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(money(p.net, cur), style: heading(20)),
            ]),
            if (p.paid > 0)
              Row(children: [
                Expanded(child: Text(L(app, 'Paid', 'दे दिया'), style: const TextStyle(color: LD.success))),
                Text(money(p.paid, cur), style: const TextStyle(fontWeight: FontWeight.w700, color: LD.success)),
              ]),
            if (p.paid > 0)
              Row(children: [
                Expanded(child: Text(L(app, 'Balance', 'बाकी'))),
                Text(money(p.balance, cur), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
          ]),
        ),
        if (!widget.mine) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: () => _payout(context, app, s, 'advance'), icon: const Icon(Icons.add), label: Text(L(app, 'Advance', 'एडवांस'))),
            OutlinedButton.icon(onPressed: () => _payout(context, app, s, 'bonus'), icon: const Icon(Icons.card_giftcard), label: Text(L(app, 'Bonus', 'बोनस'))),
            OutlinedButton.icon(onPressed: () => _payout(context, app, s, 'deduction'), icon: const Icon(Icons.remove), label: Text(L(app, 'Deduction', 'कटौती'))),
            OutlinedButton.icon(
              onPressed: () async => ExportService.sharePdf(await ExportService.payslipPdf(shop: app.shop!, data: d, p: p), 'salary-${s.name}-$_month.pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(L(app, 'Salary slip PDF', 'सैलरी स्लिप PDF')),
            ),
          ]),
        ],
      ]),
      bottomNavigationBar: widget.mine || p.balance <= 0.5
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: LD.success, minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                  onPressed: () => _payout(context, app, s, 'paid', amount: p.balance),
                  child: Text('${L(app, 'Mark paid', 'दे दिया')} ${money(p.balance, cur)}'),
                ),
              ),
            ),
    );
  }

  void _payout(BuildContext context, AppState app, Staff s, String kind, {double? amount}) {
    final ctrl = TextEditingController(text: amount?.toStringAsFixed(0) ?? '');
    final note = TextEditingController();
    var mode = 'cash';
    sheet(context, {'advance': L(app, 'Advance', 'एडवांस'), 'bonus': L(app, 'Bonus', 'बोनस'), 'deduction': L(app, 'Deduction', 'कटौती'), 'paid': L(app, 'Payment', 'पेमेंट')}[kind]!,
        (c) => StatefulBuilder(builder: (c, set) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number, decoration: fieldDeco(app.t('amount'), icon: Icons.currency_rupee_rounded)),
                const SizedBox(height: 10),
                TextField(controller: note, decoration: fieldDeco(app.t('notes'))),
                const SizedBox(height: 10),
                if (kind == 'paid' || kind == 'advance')
                  Wrap(spacing: 8, children: [for (final m in const ['cash', 'upi']) Pill(label: app.t(m), on: mode == m, onTap: () => set(() => mode = m))]),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () {
                    final a = double.tryParse(ctrl.text.trim()) ?? 0;
                    if (a <= 0) return;
                    app.data!.addPayout(s.id, _month, kind, a, mode: mode, note: note.text.trim());
                    Navigator.pop(c);
                  },
                  child: Text(app.t('save')),
                ),
              ]);
            }));
  }
}

/// Owner: commission / incentive rules.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});
  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  String _tab = 'counter';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final groups = <String, List<List<String>>>{
      'counter': [
        ['counter.salePct', L(app, 'Sales commission (%)', 'बिक्री कमीशन (%)')],
        ['counter.express', L(app, 'Per express order', 'हर एक्सप्रेस ऑर्डर पर')],
      ],
      'washer': [
        ['washer.dry', L(app, 'Per dry-clean piece', 'हर ड्राई क्लीन पीस')],
        ['washer.wash', L(app, 'Per wash piece', 'हर धुलाई पीस')],
        ['washer.iron', L(app, 'Per steam-iron piece', 'हर प्रेस पीस')],
        ['washer.kg', L(app, 'Per kg', 'हर किलो')],
      ],
      'delivery': [
        ['delivery.drop', L(app, 'Per delivery', 'हर डिलीवरी')],
        ['delivery.pickup', L(app, 'Per pickup', 'हर पिकअप')],
        ['delivery.cashPct', L(app, 'Money collected (%)', 'वसूली (%)')],
      ],
      'manager': [
        ['manager.branchPct', L(app, 'Branch sales (%)', 'ब्रांच बिक्री (%)')],
      ],
      'all': [
        ['target.sale', L(app, 'Branch monthly sales target', 'ब्रांच का मासिक बिक्री टारगेट')],
        ['target.bonus', L(app, 'Target bonus (each staff)', 'टारगेट बोनस (हर स्टाफ़)')],
        ['bonus.zeroIssue', L(app, 'Bonus for a month with no issues', 'बिना इश्यू वाले महीने का बोनस')],
        ['penalty.complaint', L(app, 'Penalty per complaint', 'हर शिकायत पर कटौती')],
        ['penalty.wrong', L(app, 'Penalty per wrong delivery', 'हर गलत डिलीवरी पर कटौती')],
      ],
    };
    final tabs = {
      'counter': app.t('role.counter'),
      'washer': app.t('role.washer'),
      'delivery': app.t('role.delivery'),
      'manager': app.t('role.manager'),
      'all': L(app, 'Bonus & penalty', 'बोनस और कटौती'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Commission rules', 'कमीशन के नियम'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Text(L(app, 'Set once. Every staff member\'s month is worked out from these.', 'एक बार सेट करें। हर स्टाफ़ का महीना इन्हीं से बनेगा।'),
            style: const TextStyle(color: LD.slate)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final e in tabs.entries) Pill(label: e.value, on: _tab == e.key, onTap: () => setState(() => _tab = e.key))]),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final r in groups[_tab]!)
              ListTile(
                title: Text(r[1]),
                trailing: Text(rule(d.rules, r[0]).toStringAsFixed(r[0].endsWith('Pct') ? 1 : 0), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                onTap: () => _edit(context, app, r[0], r[1]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: Text(L(app, 'Staff can see their own earnings', 'स्टाफ़ अपनी कमाई देख सके')),
          value: d.rules['showEarnings'] as bool? ?? true,
          onChanged: (v) {
            d.rules = {...d.rules, 'showEarnings': v};
            d.changed();
          },
        ),
      ]),
    );
  }

  void _edit(BuildContext context, AppState app, String key, String label) {
    final d = app.data!;
    final ctrl = TextEditingController(text: rule(d.rules, key).toString());
    sheet(context, label, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: ctrl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDeco(label)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v == null || v < 0) return;
              d.rules = {...d.rules, key: v};
              d.changed();
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }
}

/// Quick card for staff home screens.
class MyEarningsCard extends StatelessWidget {
  const MyEarningsCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.staffUser;
    if (s == null || !(app.data!.rules['showEarnings'] as bool? ?? true)) return const SizedBox.shrink();
    final p = slipFor(app, s, monthKey(DateTime.now()));
    return Material(
      color: const Color(0xFFDCF5E8),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(staffId: s.id, month: monthKey(DateTime.now()), mine: true))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.savings_outlined, color: Color(0xFF146C43)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${L(app, 'My earnings this month', 'इस महीने मेरी कमाई')}: ${money(p.net, app.shop!.currency)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF146C43))),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF146C43)),
          ]),
        ),
      ),
    );
  }
}
