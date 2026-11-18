import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../data/ops_models.dart';
import '../data/reports.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

// ---------------- Expenses ----------------

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  Period _p = Period.month;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final range = DateRange.of(_p);
    final list = d.expenses.where((e) => range.has(e.at) && (app.scopeBranch == null || e.branchId == app.scopeBranch)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final total = list.fold<double>(0, (s, e) => s + e.amount);
    return Scaffold(
      appBar: AppBar(title: Text(t('expenses'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, app),
        icon: const Icon(Icons.add_rounded),
        label: Text(t('addExpense')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        Wrap(spacing: 8, children: [
          for (final p in [Period.today, Period.week, Period.month, Period.all])
            Pill(
              label: t(const {Period.today: 'today', Period.week: 'week', Period.month: 'month', Period.all: 'allTime'}[p]!),
              on: _p == p,
              onTap: () => setState(() => _p = p),
            ),
        ]),
        const SizedBox(height: 12),
        SectionCard(child: Row(children: [Text(t('total'), style: const TextStyle(color: LD.slate)), const Spacer(), Text(money(total, cur), style: heading(20))])),
        const SizedBox(height: 10),
        if (list.isEmpty) EmptyState(icon: Icons.receipt_outlined, text: t('noExpenses')),
        for (final e in list)
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
            child: ListTile(
              title: Text(e.category, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${dmy(e.at)}${d.branches.length > 1 ? ' · ${d.branch(e.branchId)?.name ?? ''}' : ''}${e.note.isEmpty ? '' : ' · ${e.note}'}'),
              trailing: Text(money(e.amount, cur), style: const TextStyle(fontWeight: FontWeight.w700)),
              onLongPress: app.canManage
                  ? () async {
                      if (await confirm(context, t('remove'), '${e.category} · ${money(e.amount, cur)}', danger: true)) {
                        d.expenses.remove(e);
                        d.changed();
                      }
                    }
                  : null,
            ),
          ),
      ]),
    );
  }

  void _add(BuildContext context, AppState app) {
    final d = app.data!;
    final t = app.t;
    final amount = TextEditingController();
    final note = TextEditingController();
    var cat = expenseCategories.first;
    var branch = app.scopeBranch ?? d.branches.first.id;
    sheet(context, t('addExpense'), (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final x in expenseCategories) Pill(label: x, on: cat == x, onTap: () => set(() => cat = x)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: amount, autofocus: true, keyboardType: TextInputType.number, decoration: fieldDeco(t('amount'), icon: Icons.currency_rupee_rounded)),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: fieldDeco(t('notes'))),
            if (d.branches.length > 1) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: branch,
                decoration: fieldDeco(t('branch')),
                items: [for (final b in d.branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
                onChanged: (v) => set(() => branch = v ?? branch),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                final a = double.tryParse(amount.text.trim()) ?? 0;
                if (a <= 0) return;
                d.addExpense(branchId: branch, category: cat, amount: a, note: note.text.trim());
                Navigator.pop(c);
              },
              child: Text(t('save')),
            ),
          ]);
        }));
  }
}

// ---------------- Branches ----------------

class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final multi = app.module('multiBranch');
    final r = Report(orders: d.orders, expenses: d.expenses, range: DateRange.of(Period.today));
    return Scaffold(
      appBar: AppBar(title: Text(t('branches'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: multi || d.branches.isEmpty ? () => _add(context, app) : () => toast(context, t('moduleOff')),
        icon: const Icon(Icons.add_business_outlined),
        label: Text(t('addBranch').replaceAll('+ ', '')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        for (final b in d.branches) ...[
          SectionCard(
            child: Row(children: [
              const Icon(Icons.store_mall_directory_outlined, color: LD.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  if (b.address.isNotEmpty) Text(b.address, style: const TextStyle(color: LD.slate, fontSize: 12)),
                  Text(
                    t('ordersStaff')
                        .replaceAll('{o}', '${d.orders.where((o) => o.branchId == b.id && DateRange.of(Period.today).has(o.createdAt)).length}')
                        .replaceAll('{s}', '${d.staff.where((s) => s.active && s.branchId == b.id && d.todayAttendance(s.id) != null).length}'),
                    style: const TextStyle(color: LD.slate, fontSize: 12),
                  ),
                ]),
              ),
              Text(money(r.branchSales[b.id] ?? 0, cur), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }

  void _add(BuildContext context, AppState app) {
    final t = app.t;
    final name = TextEditingController();
    final addr = TextEditingController();
    sheet(context, t('addBranch').replaceAll('+ ', ''), (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: name, autofocus: true, decoration: fieldDeco(t('branchName'), icon: Icons.store_mall_directory_outlined)),
          const SizedBox(height: 10),
          TextField(controller: addr, decoration: fieldDeco(t('branchAddr'), icon: Icons.place_outlined)),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () {
              if (name.text.trim().length < 2) return;
              app.data!.addBranch(name.text, address: addr.text);
              Navigator.pop(c);
            },
            child: Text(t('save')),
          ),
        ]));
  }
}

// ---------------- Rate card ----------------

class RateCardScreen extends StatefulWidget {
  const RateCardScreen({super.key});
  @override
  State<RateCardScreen> createState() => _RateCardScreenState();
}

class _RateCardScreenState extends State<RateCardScreen> {
  String? _service;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final services = app.shop!.services;
    _service ??= services.isNotEmpty ? services.first : null;
    return Scaffold(
      appBar: AppBar(title: Text(t('rateCard'))),
      floatingActionButton: app.canManage
          ? FloatingActionButton.extended(onPressed: () => _addGarment(context, app), icon: const Icon(Icons.add_rounded), label: Text(t('addGarment')))
          : null,
      body: Column(children: [
        SizedBox(
          height: 50,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            scrollDirection: Axis.horizontal,
            itemCount: services.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Pill(label: services[i], on: _service == services[i], onTap: () => setState(() => _service = services[i])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(t('rateHint'), style: const TextStyle(fontSize: 12, color: LD.slate)),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            for (final g in d.garments)
              Card(
                elevation: 0,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: LD.line)),
                child: ListTile(
                  title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${g.category} · /${g.unit}', style: const TextStyle(fontSize: 12)),
                  trailing: Text(
                    d.rate(g.id, _service ?? '') == null ? '—' : money(d.rate(g.id, _service!)!, cur),
                    style: TextStyle(fontWeight: FontWeight.w700, color: d.rate(g.id, _service ?? '') == null ? LD.slate : LD.navy),
                  ),
                  onTap: app.canManage ? () => _edit(context, app, g) : null,
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  void _edit(BuildContext context, AppState app, Garment g) {
    final d = app.data!;
    final t = app.t;
    final ctrl = TextEditingController(text: d.rate(g.id, _service!)?.toStringAsFixed(0) ?? '');
    sheet(context, '${g.name} · $_service', (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldDeco('${t('price')} /${g.unit}', icon: Icons.currency_rupee_rounded),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  d.setRate(g.id, _service!, null);
                  Navigator.pop(c);
                },
                child: Text(t('remove')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  final v = double.tryParse(ctrl.text.trim());
                  d.setRate(g.id, _service!, v == null || v <= 0 ? null : v);
                  Navigator.pop(c);
                },
                child: Text(t('save')),
              ),
            ),
          ]),
        ]));
  }

  void _addGarment(BuildContext context, AppState app) {
    final t = app.t;
    final name = TextEditingController();
    final price = TextEditingController();
    var unit = 'pc';
    var cat = 'Other';
    sheet(context, t('addGarment'), (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, autofocus: true, decoration: fieldDeco(t('name'))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [for (final u in ['pc', 'kg', 'sqft']) Pill(label: u, on: unit == u, onTap: () => set(() => unit = u))]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final x in ['Men', 'Women', 'Kids', 'Household', 'Other']) Pill(label: x, on: cat == x, onTap: () => set(() => cat = x)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: fieldDeco('${t('price')} · $_service')),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                if (name.text.trim().length < 2) return;
                final g = app.data!.addGarment(name.text, unit: unit, category: cat);
                final p = double.tryParse(price.text.trim());
                if (p != null && p > 0) app.data!.setRate(g.id, _service!, p);
                Navigator.pop(c);
              },
              child: Text(t('save')),
            ),
          ]);
        }));
  }
}

// ---------------- Plans & modules ----------------

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final shop = app.shop!;
    final days = shop.trialDaysLeft(AppConfig.trialDays);

    Widget plan(String id, String name, String feat, List<int> prices) {
      final current = d.plan == id;
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: id == 'business' ? LD.navy : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: current ? LD.aqua : LD.line, width: current ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(name, style: heading(20, color: id == 'business' ? Colors.white : LD.navy)),
            const Spacer(),
            if (current)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: LD.aqua, borderRadius: BorderRadius.circular(99)),
                child: Text(t('current'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: LD.navy)),
              ),
          ]),
          const SizedBox(height: 6),
          Text(feat, style: TextStyle(color: id == 'business' ? const Color(0xFFC9D6EA) : LD.slate, height: 1.5)),
          if (prices.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: id == 'business' ? Colors.white.withValues(alpha: .08) : LD.mist,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(children: [
                      Text(t(['m1', 'm6', 'y1'][i]), style: TextStyle(fontSize: 11, color: id == 'business' ? const Color(0xFFC9D6EA) : LD.slate)),
                      Text('₹${prices[i]}', style: heading(16, color: id == 'business' ? Colors.white : LD.navy)),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: LD.sun, foregroundColor: LD.navy, minimumSize: const Size.fromHeight(46)),
              onPressed: AppConfig.enforcePremium
                  ? () => toast(context, t('billingSoon'))
                  : () {
                      d.setPlan(id, months: 1);
                      toast(context, '$name ✓');
                    },
              child: Text(AppConfig.enforcePremium ? t('choose') : t('testActivate')),
            ),
          ],
        ]),
      );
    }

    final modules = [...AppConfig.freeModules, ...AppConfig.premiumModules];
    return Scaffold(
      appBar: AppBar(title: Text(t('plans'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        if (d.plan == 'trial')
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(14)),
            child: Text(t('trialEnds').replaceAll('{n}', '$days'), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8A5A00))),
          ),
        plan('free', t('planFree'), t('freeFeat'), const []),
        plan('pro', t('planPro'), t('proFeat'), AppConfig.planPrices['pro']!),
        plan('business', t('planBusiness'), t('bizFeat'), AppConfig.planPrices['business']!),
        Text(t('billingSoon'), style: const TextStyle(fontSize: 12, color: LD.slate)),
        const SizedBox(height: 18),
        Text(t('modules'), style: heading(18)),
        const SizedBox(height: 8),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final m in modules)
              ListTile(
                leading: Icon(AppConfig.premiumModules.contains(m) ? Icons.star_rounded : Icons.check_circle_outline,
                    color: AppConfig.premiumModules.contains(m) ? const Color(0xFF8A5A00) : LD.primary),
                title: Text(t('m.$m')),
                trailing: Icon(app.module(m) ? Icons.toggle_on : Icons.toggle_off, size: 34, color: app.module(m) ? LD.success : LD.slate),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// BrotriX (app company) controls for one shop: module switches and plan. PIN-protected.
class SuperAdminScreen extends StatelessWidget {
  const SuperAdminScreen({super.key});

  static Future<void> open(BuildContext context) async {
    final t = context.read<AppState>().t;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('superAdmin')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: t('superPin')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text == AppConfig.superAdminPin), child: const Text('OK')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final modules = [...AppConfig.freeModules, ...AppConfig.premiumModules];
    return Scaffold(
      appBar: AppBar(title: Text(t('superAdmin'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Text(t('superSub'), style: const TextStyle(color: LD.slate)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.shop!.shopName, style: heading(16, weight: FontWeight.w700)),
            Text('${t('shopCode')}: ${d.shopCode} · ${app.shop!.country} · ${app.shop!.currency}', style: const TextStyle(color: LD.slate)),
            Text('${t('branches')}: ${d.branches.length} · ${t('staff')}: ${d.staff.where((s) => s.active).length} · ${t('orders')}: ${d.orders.length}',
                style: const TextStyle(color: LD.slate)),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in ['trial', 'free', 'pro', 'business'])
            Pill(label: p, on: d.plan == p, onTap: () => p == 'trial' ? (d..plan = 'trial').changed() : d.setPlan(p, months: 12)),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final m in modules)
              SwitchListTile(
                title: Text(t('m.$m')),
                subtitle: Text(AppConfig.premiumModules.contains(m) ? 'Premium' : 'Free'),
                value: !d.disabledModules.contains(m),
                onChanged: (v) => d.setModule(m, v),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------- Settings ----------------

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;

    Future<void> number(String title, double value, ValueChanged<double> set) async {
      final ctrl = TextEditingController(text: value.toStringAsFixed(0));
      await sheet(context, title, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number, decoration: fieldDeco(title)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text.trim());
                if (v != null && v >= 0) set(v);
                Navigator.pop(c);
              },
              child: Text(t('save')),
            ),
          ]));
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('settings'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('shopCode'), style: const TextStyle(color: LD.slate)),
            const SizedBox(height: 4),
            Row(children: [
              SelectableText(d.shopCode, style: heading(28).copyWith(letterSpacing: 4)),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                onPressed: () => Clipboard.setData(ClipboardData(text: d.shopCode)),
                icon: const Icon(Icons.copy_rounded),
              ),
            ]),
            Text(t('shopCodeSub'), style: const TextStyle(fontSize: 12, color: LD.slate)),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            ListTile(
              title: Text(t('taxPct')),
              trailing: Text('${d.taxPct.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => number(t('taxPct'), d.taxPct, (v) => (d..taxPct = v).changed()),
            ),
            ListTile(
              title: Text(t('expressPct')),
              trailing: Text('${d.expressPct.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => number(t('expressPct'), d.expressPct, (v) => (d..expressPct = v).changed()),
            ),
            ListTile(
              title: Text(t('dueDays')),
              trailing: Text('${d.dueDays}', style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => number(t('dueDays'), d.dueDays.toDouble(), (v) => (d..dueDays = v.round().clamp(0, 30)).changed()),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: t('security'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(app.lockOn ? Icons.lock_outline : Icons.lock_open_outlined, color: app.lockOn ? LD.success : LD.slate),
              title: Text(t('appLock')),
              subtitle: Text(t('appLockSub')),
              trailing: Text(app.lockOn ? 'ON' : 'OFF', style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => _lockSheet(context, app),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (d.hasSample)
          SectionCard(
            title: t('sample'),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB42318)),
              onPressed: () async {
                if (await confirm(context, t('clearSample'), t('clearSure'), danger: true)) d.clearSample();
              },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(t('clearSample')),
            ),
          ),
      ]),
    );
  }
}

void _lockSheet(BuildContext context, AppState app) {
  final t = app.t;
  final a = TextEditingController();
  final b = TextEditingController();
  var err = '';
  sheet(context, t('appLock'), (c) => StatefulBuilder(builder: (c, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: a,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: fieldDeco(t('newPin'), icon: Icons.pin_outlined),
          ),
          TextField(
            controller: b,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: fieldDeco(t('confirmPin'), icon: Icons.pin_outlined),
          ),
          if (err.isNotEmpty) Text(err, style: const TextStyle(color: Color(0xFFB42318))),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () {
              if (a.text.length != 4 || a.text != b.text) {
                set(() => err = t('pinMismatch'));
                return;
              }
              app.setLockPin(a.text);
              Navigator.pop(c);
              toast(context, t('lockSet'));
            },
            child: Text(t('save')),
          ),
          if (app.lockOn)
            TextButton(
              onPressed: () {
                app.setLockPin(null);
                Navigator.pop(c);
              },
              child: Text(t('lockRemove')),
            ),
        ]);
      }));
}
