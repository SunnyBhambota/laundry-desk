import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../data/reports.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _p = Period.month;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final advanced = app.module('advancedReports');
    final range = DateRange.of(_p);
    final r = Report(orders: d.orders, expenses: d.expenses, range: range, branchId: app.scopeBranch);

    // daily bars: last 7 days, or days of this month
    final days = _p == Period.month ? DateTime.now().day : 7;
    final barVals = <double>[];
    final barLabels = <String>[];
    for (var i = days - 1; i >= 0; i--) {
      final dt = DateTime.now().subtract(Duration(days: i));
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
          IconButton(
            tooltip: t('shareSummary'),
            icon: const Icon(Icons.share_outlined),
            onPressed: () => openWhatsApp('', _summary(app, r, cur)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in Period.values)
            Pill(
              label: t(const {Period.today: 'today', Period.week: 'week', Period.month: 'month', Period.all: 'allTime'}[p]!),
              on: _p == p,
              onTap: () => setState(() => _p = p),
            ),
        ]),
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
        const SizedBox(height: 12),
        if (_p != Period.today && _p != Period.all)
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
          if (d.branches.length > 1 && app.isOwner && app.scopeBranch == null) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: t('branchCompare'),
              child: Column(children: [
                for (final b in d.branches)
                  ShareRow(label: b.name, value: r.branchSales[b.id] ?? 0, max: brMax, text: money(r.branchSales[b.id] ?? 0, cur), color: LD.softBlue),
              ]),
            ),
          ],
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

  String _summary(AppState app, Report r, String cur) {
    final t = app.t;
    return '*${app.shop!.shopName} – ${t(const {Period.today: 'today', Period.week: 'week', Period.month: 'month', Period.all: 'allTime'}[_p]!)}*\n'
        '${t('orders')}: ${r.orderCount} (${r.pieces} ${t('pcs')})\n'
        '${t('sales')}: ${money(r.sales, cur)}\n'
        '${t('collected')}: ${money(r.collected, cur)}\n'
        '${t('expenses')}: ${money(r.expense, cur)}\n'
        '${t('profit')}: ${money(r.profit, cur)}\n'
        '${t('pendingDues')}: ${money(r.pendingDues, cur)}\n'
        '– Laundry Desk';
  }
}
