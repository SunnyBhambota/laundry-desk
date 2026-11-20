import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../data/reports.dart';
import '../data/shop_data.dart';
import '../services/export_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/branch_switch.dart';
import '../widgets/ui.dart';
import 'issue_screens.dart';
import 'order_detail_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _p = Period.month;
  DateRange? _custom; // last month / picked dates
  String _customLabel = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final advanced = app.module('advancedReports');
    final range = _custom ?? DateRange.of(_p);
    final r = Report(orders: d.orders, expenses: d.expenses, range: range, branchId: app.scopeBranch);

    // daily bars: last 7 days, or days of this month
    final lastDay = _custom == null ? DateTime.now() : range.to.subtract(const Duration(days: 1));
    final days = _custom != null ? range.to.difference(range.from).inDays.clamp(1, 62) : (_p == Period.month ? DateTime.now().day : 7);
    final barVals = <double>[];
    final barLabels = <String>[];
    for (var i = days - 1; i >= 0; i--) {
      final dt = lastDay.subtract(Duration(days: i));
      barVals.add(r.daily[dayKey(dt)] ?? 0);
      barLabels.add(days <= 7 ? ['M', 'T', 'W', 'T', 'F', 'S', 'S'][dt.weekday - 1] : (dt.day % 5 == 0 || dt.day == 1 ? '${dt.day}' : ''));
    }

    Widget kpi(String label, String value, {Color? color}) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: LD.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: LD.slate, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(value, style: heading(20, color: color ?? LD.navy)),
          ]),
        );

    final svcMax = r.services.values.fold<double>(0, (a, b) => b > a ? b : a);
    final topC = r.top(r.customerSpend);
    final topCMax = topC.isEmpty ? 0.0 : topC.first.value;
    final brMax = r.branchSales.values.fold<double>(0, (a, b) => b > a ? b : a);
    final exMax = r.expenseByCat.values.fold<double>(0, (a, b) => b > a ? b : a);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('reports')),
        actions: [
          const BranchSwitch(),
          IconButton(
            tooltip: t('printReport'),
            icon: const Icon(Icons.print_outlined),
            onPressed: () async => ExportService.printPdf(await _pdf(app, r), 'Report'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final label = _label(t);
              if (v == 'pdf') ExportService.sharePdf(await _pdf(app, r), 'laundry-report-$label.pdf');
              if (v == 'wa') openWhatsApp('', _summary(app, r, cur));
              if (v == 'orders') {
                ExportService.shareCsv(
                    ExportService.ordersCsv(d, d.ordersIn(app.scopeBranch).where((o) => r.range.has(o.createdAt))), 'orders-$label.csv');
              }
              if (v == 'customers') ExportService.shareCsv(ExportService.customersCsv(d), 'customers.csv');
              if (v == 'branches') ExportService.shareCsv(ExportService.branchCsv(d, r.range), 'branches-$label.csv');
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'pdf', child: Text(t('sharePdf'))),
              PopupMenuItem(value: 'orders', child: Text(t('csvOrders'))),
              PopupMenuItem(value: 'customers', child: Text(t('csvCustomers'))),
              if (d.branches.length > 1 && app.isOwner) PopupMenuItem(value: 'branches', child: Text(L(app, 'Branch comparison (Excel/CSV)', 'ब्रांच तुलना (Excel/CSV)'))),
              PopupMenuItem(value: 'wa', child: Text(t('shareSummary'))),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in Period.values)
            Pill(
              label: t(const {Period.today: 'today', Period.week: 'week', Period.month: 'month', Period.all: 'allTime'}[p]!),
              on: _custom == null && _p == p,
              onTap: () => setState(() {
                _p = p;
                _custom = null;
              }),
            ),
          Pill(
            label: L(app, 'Last month', 'पिछला महीना'),
            on: _custom != null && _customLabel == 'last',
            onTap: () => setState(() {
              final n = DateTime.now();
              _custom = DateRange(DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 1));
              _customLabel = 'last';
            }),
          ),
          Pill(
            label: _custom != null && _customLabel == 'pick' ? '${dmy(range.from)} – ${dmy(range.to.subtract(const Duration(days: 1)))}' : L(app, 'Pick dates', 'तारीख चुनें'),
            on: _custom != null && _customLabel == 'pick',
            onTap: () async {
              final n = DateTime.now();
              final p = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: n);
              if (p == null) return;
              setState(() {
                _custom = DateRange(DateTime(p.start.year, p.start.month, p.start.day), DateTime(p.end.year, p.end.month, p.end.day + 1));
                _customLabel = 'pick';
              });
            },
          ),
        ]),
        if (app.isOwner && d.branches.length > 1) ...[
          const SizedBox(height: 10),
          Text(app.scopeBranch == null ? L(app, 'All branches', 'सभी ब्रांच') : (d.branches.where((b) => b.id == app.scopeBranch).firstOrNull?.name ?? ''),
              style: const TextStyle(color: LD.slate, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.9,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            kpi(t('collected'), money(r.collected, cur), color: const Color(0xFF146C43)),
            kpi(t('sales'), money(r.sales, cur)),
            kpi(t('orders'), '${r.orderCount} · ${r.pieces} ${t('pcs')}'),
            kpi(t('avgOrder'), money(r.avgOrder, cur)),
            kpi(t('expenses'), money(r.expense, cur), color: const Color(0xFFA8430F)),
            kpi(t('profit'), money(r.profit, cur), color: r.profit >= 0 ? const Color(0xFF146C43) : const Color(0xFFB42318)),
          ],
        ),
        const SizedBox(height: 10),
        kpi(t('pendingDues'), money(r.pendingDues, cur), color: const Color(0xFF8A5A00)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DayCloseScreen())),
              icon: const Icon(Icons.point_of_sale_outlined),
              label: Text(L(app, 'Day closing', 'दिन का हिसाब')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OverdueScreen())),
              icon: const Icon(Icons.schedule_outlined),
              label: Text(L(app, 'Late orders', 'देरी वाले ऑर्डर')),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IssueReportsScreen())),
          icon: const Icon(Icons.report_problem_outlined),
          label: Text(L(app, 'Complaint & wrong-delivery report', 'शिकायत और गलत डिलीवरी रिपोर्ट')),
        ),
        const SizedBox(height: 12),
        if (d.branches.length > 1 && app.isOwner && app.scopeBranch == null) ...[
          BranchCompareCard(range: range),
          const SizedBox(height: 12),
        ],
        if (_custom != null || (_p != Period.today && _p != Period.all))
          SectionCard(title: t('dailyColl'), child: Bars(values: barVals, labels: barLabels)),
        const SizedBox(height: 12),
        SectionCard(
          title: t('byMode'),
          child: Column(children: [
            for (final m in payModes)
              ShareRow(label: t(m), value: r.byMode[m] ?? 0, max: r.collected, text: money(r.byMode[m] ?? 0, cur), color: LD.aqua),
          ]),
        ),
        const SizedBox(height: 12),
        if (!advanced)
          SectionCard(child: Text('${t('moduleOff')} (${t('m.advancedReports')})', style: const TextStyle(color: LD.slate))),
        if (advanced) ...[
          SectionCard(
            title: t('serviceMix'),
            child: Column(children: [
              for (final e in r.top(r.services, 8)) ShareRow(label: e.key, value: e.value, max: svcMax, text: money(e.value, cur)),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: t('topCustomers'),
            child: Column(children: [
              for (final e in topC)
                ShareRow(label: d.customer(e.key)?.name ?? '—', value: e.value, max: topCMax, text: money(e.value, cur), color: LD.lilac),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: t('expenseByCat'),
            child: r.expenseByCat.isEmpty
                ? Text(t('noExpenses'), style: const TextStyle(color: LD.slate))
                : Column(children: [
                    for (final e in r.top(r.expenseByCat, 9))
                      ShareRow(label: e.key, value: e.value, max: exMax, text: money(e.value, cur), color: const Color(0xFFE8742A)),
                  ]),
          ),
        ],
      ]),
    );
  }

  String _label(String Function(String) t) => _custom != null
      ? '${dmy(_custom!.from)}_${dmy(_custom!.to.subtract(const Duration(days: 1)))}'.replaceAll(' ', '-')
      : t(const {Period.today: 'today', Period.week: 'week', Period.month: 'month', Period.all: 'allTime'}[_p]!);

  Future<Uint8List> _pdf(AppState app, Report r) =>
      ExportService.reportPdf(shop: app.shop!, data: app.data!, r: r, periodLabel: _label(app.t), branchId: app.scopeBranch);

  String _summary(AppState app, Report r, String cur) {
    final t = app.t;
    return '*${app.shop!.shopName} – ${_label(t)}*\n'
        '${t('orders')}: ${r.orderCount} (${r.pieces} ${t('pcs')})\n'
        '${t('sales')}: ${money(r.sales, cur)}\n'
        '${t('collected')}: ${money(r.collected, cur)}\n'
        '${t('expenses')}: ${money(r.expense, cur)}\n'
        '${t('profit')}: ${money(r.profit, cur)}\n'
        '${t('pendingDues')}: ${money(r.pendingDues, cur)}\n'
        '– LaundryCase';
  }
}


/// One row per branch: orders, sales, collected, expense, profit, dues, complaints, staff on duty.
class BranchRow {
  BranchRow(this.branch, this.r, this.complaints, this.wrong, this.staff);
  final Branch branch;
  final Report r;
  final int complaints;
  final int wrong;
  final int staff;

  static List<BranchRow> build(ShopData d, DateRange range) => [
        for (final b in d.branches)
          BranchRow(
            b,
            Report(orders: d.orders, expenses: d.expenses, range: range, branchId: b.id),
            d.issues.where((i) => i.branchId == b.id && i.kind == 'complaint' && range.has(i.openedAt)).length,
            d.issues.where((i) => i.branchId == b.id && i.kind != 'complaint' && range.has(i.openedAt)).length,
            d.staff.where((s) => s.active && s.branchId == b.id).length,
          ),
      ];
}

class BranchCompareCard extends StatelessWidget {
  const BranchCompareCard({super.key, required this.range});
  final DateRange range;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final rows = BranchRow.build(d, range);
    final best = rows.isEmpty ? null : (rows.toList()..sort((a, b) => b.r.sales.compareTo(a.r.sales))).first;
    DataCell num(String s, {Color? c}) => DataCell(Text(s, style: TextStyle(fontWeight: FontWeight.w600, color: c)));
    return SectionCard(
      title: L(app, 'Branch comparison', 'ब्रांच तुलना'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            headingRowHeight: 36,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 48,
            columns: [
              DataColumn(label: Text(L(app, 'Branch', 'ब्रांच'))),
              DataColumn(label: Text(app.t('orders')), numeric: true),
              DataColumn(label: Text(app.t('sales')), numeric: true),
              DataColumn(label: Text(app.t('collected')), numeric: true),
              DataColumn(label: Text(app.t('expenses')), numeric: true),
              DataColumn(label: Text(app.t('profit')), numeric: true),
              DataColumn(label: Text(app.t('pendingDues')), numeric: true),
              DataColumn(label: Text(L(app, 'Complaints', 'शिकायत')), numeric: true),
              DataColumn(label: Text(L(app, 'Wrong del.', 'गलत डिलीवरी')), numeric: true),
              DataColumn(label: Text(app.t('staff')), numeric: true),
            ],
            rows: [
              for (final x in rows)
                DataRow(
                  onSelectChanged: (_) {
                    app.setBranchFilter(x.branch.id);
                  },
                  cells: [
                    DataCell(Text(x.branch.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                    num('${x.r.orderCount}'),
                    num(money(x.r.sales, cur)),
                    num(money(x.r.collected, cur), c: const Color(0xFF146C43)),
                    num(money(x.r.expense, cur), c: const Color(0xFFA8430F)),
                    num(money(x.r.profit, cur), c: x.r.profit >= 0 ? const Color(0xFF146C43) : const Color(0xFFB42318)),
                    num(money(x.r.pendingDues, cur), c: const Color(0xFF8A5A00)),
                    num('${x.complaints}', c: x.complaints > 0 ? const Color(0xFFB42318) : null),
                    num('${x.wrong}', c: x.wrong > 0 ? const Color(0xFFB42318) : null),
                    num('${x.staff}'),
                  ],
                ),
            ],
          ),
        ),
        if (best != null && best.r.sales > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${L(app, 'Top branch', 'सबसे आगे')}: ${best.branch.name} · ${L(app, 'tap a row to open that branch', 'ब्रांच खोलने के लिए लाइन दबाएँ')}',
                style: const TextStyle(fontSize: 12, color: LD.slate)),
          ),
      ]),
    );
  }
}

/// Day-end closing: what came in, what went out, cash in hand – per branch, any date.
class DayCloseScreen extends StatefulWidget {
  const DayCloseScreen({super.key});
  @override
  State<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends State<DayCloseScreen> {
  DateTime _day = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final t = app.t;
    final scope = app.scopeBranch;
    final range = DateRange(DateTime(_day.year, _day.month, _day.day), DateTime(_day.year, _day.month, _day.day + 1));
    final r = Report(orders: d.orders, expenses: d.expenses, range: range, branchId: scope);
    final inBranch = d.ordersIn(scope).toList();
    final delivered = inBranch.where((o) => range.has(o.timeOf('delivered') ?? DateTime(2000))).length;
    final cashExp = d.expenses.where((e) => range.has(e.at) && (scope == null || e.branchId == scope)).fold<double>(0, (s, e) => s + e.amount);
    final cashIn = r.byMode['cash'] ?? 0;
    final overdue = inBranch.where((o) => o.status != 'delivered' && o.status != 'cancelled' && o.dueAt.isBefore(range.to)).length;
    final present = d.staff.where((s) => s.active && (scope == null || s.branchId == scope) && d.attendance.any((a) => a.staffId == s.id && a.day == dayKey(_day))).length;
    final branchName = scope == null ? (d.branches.length > 1 ? L(app, 'All branches', 'सभी ब्रांच') : '') : (d.branch(scope)?.name ?? '');

    String text() => '*${app.shop!.shopName}${branchName.isEmpty ? '' : ' – $branchName'}*\n'
        '${L(app, 'Day closing', 'दिन का हिसाब')} ${dmy(_day)}\n'
        '${t('orders')}: ${r.orderCount} (${r.pieces} ${t('pcs')}) · ${L(app, 'Delivered', 'डिलीवर')}: $delivered\n'
        '${t('sales')}: ${money(r.sales, cur)}\n'
        '${t('collected')}: ${money(r.collected, cur)} (Cash ${money(cashIn, cur)} · UPI ${money(r.byMode['upi'] ?? 0, cur)} · Card ${money(r.byMode['card'] ?? 0, cur)})\n'
        '${t('expenses')}: ${money(cashExp, cur)}\n'
        '${L(app, 'Cash in hand', 'हाथ में कैश')}: ${money(cashIn - cashExp, cur)}\n'
        '${L(app, 'Overdue orders', 'देरी वाले ऑर्डर')}: $overdue · ${L(app, 'Staff present', 'हाज़िर स्टाफ')}: $present\n'
        '– LaundryCase';

    Widget line(String a, String b, {Color? c, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
            Text(b, style: TextStyle(fontWeight: FontWeight.w800, color: c ?? LD.navy, fontSize: bold ? 17 : 14)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Day closing', 'दिन का हिसाब')), actions: [
        const BranchSwitch(),
        IconButton(
          tooltip: t('printReport'),
          icon: const Icon(Icons.print_outlined),
          onPressed: () async => ExportService.printPdf(
              await ExportService.reportPdf(shop: app.shop!, data: d, r: r, periodLabel: 'Day closing ${dmy(_day)}', branchId: scope), 'Day closing'),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Row(children: [
          IconButton(onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: TextButton(
              onPressed: () async {
                final p = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (p != null) setState(() => _day = p);
              },
              child: Text('${dmy(_day)}${branchName.isEmpty ? '' : ' · $branchName'}', style: heading(16, weight: FontWeight.w700)),
            ),
          ),
          IconButton(
              onPressed: dayKey(_day) == dayKey(DateTime.now()) ? null : () => setState(() => _day = _day.add(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_right)),
        ]),
        SectionCard(
          child: Column(children: [
            line(t('orders'), '${r.orderCount} · ${r.pieces} ${t('pcs')}'),
            line(L(app, 'Delivered today', 'आज डिलीवर'), '$delivered'),
            line(t('sales'), money(r.sales, cur)),
            const Divider(),
            line('Cash', money(cashIn, cur)),
            line('UPI', money(r.byMode['upi'] ?? 0, cur)),
            line('Card', money(r.byMode['card'] ?? 0, cur)),
            line(t('collected'), money(r.collected, cur), c: const Color(0xFF146C43), bold: true),
            const Divider(),
            line(t('expenses'), '− ${money(cashExp, cur)}', c: const Color(0xFFA8430F)),
            line(L(app, 'Cash in hand (cash − expenses)', 'हाथ में कैश (कैश − खर्चे)'), money(cashIn - cashExp, cur), bold: true),
            const Divider(),
            line(L(app, 'Overdue orders', 'देरी वाले ऑर्डर'), '$overdue', c: overdue > 0 ? const Color(0xFFB42318) : null),
            line(L(app, 'Staff present', 'हाज़िर स्टाफ'), '$present'),
          ]),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => openWhatsApp('', text()),
          icon: const Icon(Icons.chat_outlined),
          label: Text(L(app, 'Send on WhatsApp', 'WhatsApp पर भेजें')),
        ),
      ]),
    );
  }
}

/// Orders past their promised date and not delivered.
class OverdueScreen extends StatelessWidget {
  const OverdueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final now = DateTime.now();
    final list = d.ordersIn(app.scopeBranch).where((o) => o.status != 'delivered' && o.status != 'cancelled' && o.dueAt.isBefore(now)).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return Scaffold(
      appBar: AppBar(title: Text('${L(app, 'Late orders', 'देरी वाले ऑर्डर')} · ${list.length}'), actions: const [BranchSwitch()]),
      body: list.isEmpty
          ? Center(child: Text(L(app, 'Nothing late.', 'कुछ भी देरी में नहीं।')))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              for (final o in list)
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
                  child: ListTile(
                    title: Text('${o.code} · ${d.customer(o.customerId)?.name ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${app.t(o.status)} · ${L(app, 'due', 'तय')} ${dmy(o.dueAt)} · ${now.difference(o.dueAt).inDays} ${L(app, 'days late', 'दिन देरी')}'
                        '${d.branches.length > 1 ? ' · ${d.branch(o.branchId)?.name ?? ''}' : ''}'),
                    trailing: Text(money(o.total, cur), style: const TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id))),
                  ),
                ),
            ]),
    );
  }
}
