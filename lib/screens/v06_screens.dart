import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../data/shop_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/branch_switch.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

/// Things staff often ask for (quick chips in the request form).
const commonNeeds = ['Hanger', 'Iron / istri', 'Washing powder', 'Detergent liquid', 'Poly cover', 'Tag roll', 'Starch', 'Stain remover', 'Bill roll', 'Soap'];

String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

Color _statusColor(String s) => switch (s) {
      'pending' => const Color(0xFF8A5A00),
      'approved' => LD.primary,
      'given' => LD.success,
      _ => const Color(0xFFB42318),
    };

String _statusText(AppState app, String s) => switch (s) {
      'pending' => L(app, 'Waiting', 'इंतज़ार'),
      'approved' => L(app, 'Approved – coming', 'मंज़ूर – आ रहा है'),
      'given' => L(app, 'Given', 'दे दिया'),
      _ => L(app, 'Rejected', 'मना'),
    };

// ---------------- staff requests ----------------

/// Staff: "my requests" + new request. Owner / manager: everyone's requests with actions.
class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final boss = app.canManage;
    final scope = app.scopeBranch;
    final mine = d.requests.where((r) => r.by == app.actorId).toList()..sort((a, b) => b.at.compareTo(a.at));
    final all = d.requests.where((r) => scope == null || r.branchId == scope).toList()..sort((a, b) => b.at.compareTo(a.at));
    final pending = all.where((r) => r.status == 'pending').toList()
      ..sort((a, b) => a.urgent == b.urgent ? a.at.compareTo(b.at) : (a.urgent ? -1 : 1));
    final approved = all.where((r) => r.status == 'approved').toList();

    Widget list(List<StaffRequest> l, {required bool actions}) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            if (l.isEmpty) EmptyState(icon: Icons.inbox_outlined, text: L(app, 'No requests.', 'कोई रिक्वेस्ट नहीं।')),
            for (final r in l) RequestTile(request: r, actions: actions),
          ],
        );

    final fab = FloatingActionButton.extended(
      onPressed: () => newRequestSheet(context, app),
      icon: const Icon(Icons.add),
      label: Text(L(app, 'New request', 'नई रिक्वेस्ट')),
    );

    if (!boss) {
      return Scaffold(
        appBar: AppBar(title: Text(L(app, 'My requests to boss', 'बॉस से मेरी माँग'))),
        floatingActionButton: fab,
        body: list(mine, actions: false),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L(app, 'Staff requests', 'स्टाफ की माँग')),
          actions: const [BranchSwitch()],
          bottom: TabBar(tabs: [
            Tab(text: '${L(app, 'Waiting', 'इंतज़ार')} (${pending.length})'),
            Tab(text: '${L(app, 'Approved', 'मंज़ूर')} (${approved.length})'),
            Tab(text: L(app, 'All', 'सब')),
          ]),
        ),
        floatingActionButton: fab,
        body: TabBarView(children: [
          list(pending, actions: true),
          list(approved, actions: true),
          list(all, actions: true),
        ]),
      ),
    );
  }
}

class RequestTile extends StatelessWidget {
  const RequestTile({super.key, required this.request, required this.actions});
  final StaffRequest request;
  final bool actions;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final r = request;
    final staff = d.staff.where((s) => s.id == r.by).firstOrNull;
    final c = _statusColor(r.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: r.urgent && r.open ? const Color(0xFFB42318) : LD.line, width: r.urgent && r.open ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (r.urgent) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.priority_high_rounded, color: Color(0xFFB42318), size: 20)),
          Expanded(child: Text('${r.item} · ${_q(r.qty)} ${r.unit}', style: heading(16, weight: FontWeight.w700))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
            child: Text(_statusText(app, r.status), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            d.nameOf(r.by),
            if (d.branches.length > 1) d.branch(r.branchId)?.name ?? '',
            whenText(r.at),
          ].where((x) => x.isNotEmpty).join(' · '),
          style: const TextStyle(color: LD.slate, fontSize: 12),
        ),
        if (r.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${r.note}”')),
        if (r.reply.isNotEmpty || r.doneAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_statusText(app, r.status)}${r.doneAt == null ? '' : ' ${whenText(r.doneAt!)}'}${r.reply.isEmpty ? '' : ' – ${r.reply}'}',
              style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        if (actions && r.open) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (r.status == 'pending')
              OutlinedButton.icon(
                onPressed: () => d.decideRequest(r, 'approved', by: app.actorId),
                icon: const Icon(Icons.check, size: 18),
                label: Text(L(app, 'Approve', 'मंज़ूर')),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: LD.success),
              onPressed: () => _giveSheet(context, app, r),
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: Text(L(app, 'Given', 'दे दिया')),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFB42318)),
              onPressed: () => _rejectSheet(context, app, r),
              child: Text(L(app, 'Reject', 'मना करें')),
            ),
            if ((staff?.phone ?? '').isNotEmpty)
              IconButton(
                tooltip: 'WhatsApp',
                onPressed: () => openWhatsApp(staff!.phone, '${r.item} ${_q(r.qty)} ${r.unit}: '),
                icon: const Icon(Icons.chat_outlined),
              ),
          ]),
        ],
      ]),
    );
  }

  void _giveSheet(BuildContext context, AppState app, StaffRequest r) {
    final d = app.data!;
    final it = r.itemId.isEmpty ? null : d.stock.where((x) => x.id == r.itemId).firstOrNull;
    final cost = TextEditingController();
    final reply = TextEditingController();
    var fromStock = it != null && it.qty >= r.qty;
    var bought = it == null || it.qty < r.qty;
    sheet(context, '${r.item} · ${_q(r.qty)} ${r.unit}', (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (it != null)
              Text('${L(app, 'In stock', 'स्टॉक में')}: ${_q(it.qty)} ${it.unit}', style: const TextStyle(color: LD.slate)),
            if (it != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L(app, 'Take it out of stock', 'स्टॉक से कम करें')),
                value: fromStock,
                onChanged: (v) => set(() => fromStock = v),
              ),
            if (app.isOwner)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L(app, 'I bought it now (add to expenses)', 'अभी खरीदा (खर्चे में जोड़ें)')),
                value: bought,
                onChanged: (v) => set(() => bought = v),
              ),
            if (app.isOwner && bought)
              TextField(controller: cost, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Price paid', 'कितने में खरीदा'), icon: Icons.currency_rupee)),
            const SizedBox(height: 10),
            TextField(controller: reply, decoration: fieldDeco(L(app, 'Note to staff (optional)', 'स्टाफ के लिए नोट (ज़रूरी नहीं)'))),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: LD.success),
              onPressed: () {
                d.decideRequest(r, 'given',
                    by: app.actorId, reply: reply.text, fromStock: fromStock, cost: app.isOwner && bought ? (double.tryParse(cost.text) ?? 0) : 0);
                Navigator.pop(c);
              },
              child: Text(L(app, 'Mark as given', 'दे दिया')),
            ),
          ]);
        }));
  }

  void _rejectSheet(BuildContext context, AppState app, StaffRequest r) {
    final reply = TextEditingController();
    sheet(context, L(app, 'Reject request', 'रिक्वेस्ट मना करें'), (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: reply, decoration: fieldDeco(L(app, 'Reason (staff will see it)', 'वजह (स्टाफ को दिखेगी)'))),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
            onPressed: () {
              app.data!.decideRequest(r, 'rejected', by: app.actorId, reply: reply.text);
              Navigator.pop(c);
            },
            child: Text(L(app, 'Reject', 'मना करें')),
          ),
        ]));
  }
}

void newRequestSheet(BuildContext context, AppState app) {
  final d = app.data!;
  final item = TextEditingController();
  final qty = TextEditingController(text: '1');
  final unit = TextEditingController(text: 'pc');
  final note = TextEditingController();
  var urgent = false;
  String itemId = '';
  final branch = app.staffUser?.branchId ?? app.scopeBranch ?? d.branches.first.id;
  final stockHere = d.stock.where((s) => s.branchId.isEmpty || s.branchId == branch).toList();
  sheet(context, L(app, 'Ask the boss for…', 'बॉस से माँगें…'), (c) => StatefulBuilder(builder: (c, set) {
        void pick(String name, String id, String u) => set(() {
              item.text = name;
              itemId = id;
              unit.text = u;
            });
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in stockHere) Pill(label: s.name, on: itemId == s.id, onTap: () => pick(s.name, s.id, s.unit)),
            for (final n in commonNeeds.where((n) => !stockHere.any((s) => s.name.toLowerCase() == n.toLowerCase())))
              Pill(label: n, on: itemId.isEmpty && item.text == n, onTap: () => pick(n, '', 'pc')),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: item,
            onChanged: (_) => set(() => itemId = ''),
            decoration: fieldDeco(L(app, 'What do you need? (anything)', 'क्या चाहिए? (कुछ भी)'), icon: Icons.shopping_bag_outlined),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDeco(L(app, 'How many', 'कितने')))),
            const SizedBox(width: 10),
            SizedBox(width: 110, child: TextField(controller: unit, decoration: fieldDeco(L(app, 'Unit', 'यूनिट')))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: fieldDeco(L(app, 'Note (why / which machine…)', 'नोट (क्यों / कौन सी मशीन…)'))),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L(app, 'Urgent', 'अर्जेंट')),
            secondary: const Icon(Icons.priority_high_rounded, color: Color(0xFFB42318)),
            value: urgent,
            onChanged: (v) => set(() => urgent = v),
          ),
          FilledButton(
            onPressed: () {
              final q = double.tryParse(qty.text) ?? 0;
              if (item.text.trim().length < 2 || q <= 0) {
                toast(c, L(app, 'Write what you need and how many.', 'क्या और कितना चाहिए, लिखें।'));
                return;
              }
              d.addRequest(by: app.actorId, branchId: branch, item: item.text, itemId: itemId, qty: q, unit: unit.text.trim(), note: note.text, urgent: urgent);
              Navigator.pop(c);
              toast(context, L(app, 'Request sent to the boss.', 'बॉस को रिक्वेस्ट भेज दी।'));
            },
            child: Text(L(app, 'Send request', 'रिक्वेस्ट भेजें')),
          ),
        ]);
      }));
}

// ---------------- staff: stock used ----------------

/// Washer / counter: "I used 2 kg powder" – booked into stock by the owner's phone.
class StockUseScreen extends StatelessWidget {
  const StockUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final branch = app.staffUser?.branchId ?? app.scopeBranch;
    final items = d.stock.where((s) => branch == null || s.branchId.isEmpty || s.branchId == branch).toList();
    final today = DateTime.now();
    final day0 = DateTime(today.year, today.month, today.day);
    final myToday = d.stockUses.where((u) => u.by == app.actorId && !u.at.isBefore(day0)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Stock used', 'स्टॉक इस्तेमाल'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        Text(L(app, 'Tap an item and write how much you used. Running low? Send a request.', 'आइटम दबाएँ और कितना इस्तेमाल किया लिखें। कम है? रिक्वेस्ट भेजें।'),
            style: const TextStyle(color: LD.slate)),
        const SizedBox(height: 10),
        if (items.isEmpty) EmptyState(icon: Icons.inventory_2_outlined, text: L(app, 'The owner has not added stock items yet.', 'मालिक ने अभी स्टॉक आइटम नहीं जोड़े।')),
        for (final it in items)
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
            child: ListTile(
              title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${L(app, 'Left about', 'बचा लगभग')} ${_q(it.qty - d.pendingUse(it.id))} ${it.unit}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: L(app, 'Ask for more', 'और माँगें'),
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                  onPressed: () => newRequestSheet(context, app),
                ),
                FilledButton.tonal(onPressed: () => _use(context, app, it), child: Text(L(app, '− Used', '− इस्तेमाल'))),
              ]),
            ),
          ),
        if (myToday.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(L(app, 'My entries today', 'आज की मेरी एंट्री'), style: heading(15, weight: FontWeight.w700)),
          for (final u in myToday.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${d.stock.where((s) => s.id == u.itemId).firstOrNull?.name ?? '?'} − ${_q(u.qty)}'),
              trailing: Text(hm(u.at)),
            ),
        ],
      ]),
    );
  }

  void _use(BuildContext context, AppState app, StockItem it) {
    final qty = TextEditingController();
    final note = TextEditingController();
    sheet(context, '${it.name} – ${L(app, 'used', 'इस्तेमाल')}', (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
              controller: qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: fieldDeco('${L(app, 'How much', 'कितना')} (${it.unit})')),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: fieldDeco(L(app, 'For what (optional)', 'किसके लिए (ज़रूरी नहीं)'))),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              final q = double.tryParse(qty.text) ?? 0;
              if (q <= 0) return;
              final d = app.data!;
              if (app.isOwner) {
                d.moveStock(it, -q, by: app.actorId, note: note.text);
              } else {
                d.addStockUse(it, q, by: app.actorId, branchId: app.staffUser?.branchId ?? '', note: note.text);
              }
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }
}

// ---------------- stock report ----------------

class StockReportView extends StatefulWidget {
  const StockReportView({super.key});
  @override
  State<StockReportView> createState() => _StockReportViewState();
}

class _StockReportViewState extends State<StockReportView> {
  int _monthsBack = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final n = DateTime.now();
    final from = DateTime(n.year, n.month - _monthsBack, 1);
    final to = DateTime(n.year, n.month - _monthsBack + 1, 1);
    final scope = app.scopeBranch;
    final items = d.stock.where((s) => scope == null || s.branchId.isEmpty || s.branchId == scope).toList();
    final kg = d.kgWashed(from, to, branchId: scope);
    var totalCost = 0.0;
    final rows = <Widget>[];
    for (final it in items) {
      final used = d.usedIn(it.id, from, to);
      final bought = d.boughtIn(it.id, from, to);
      final uc = d.unitCost(it.id);
      totalCost += used * uc;
      // days left from the last 30 days' use
      final last30 = d.usedIn(it.id, n.subtract(const Duration(days: 30)), n.add(const Duration(days: 1)));
      final daysLeft = last30 <= 0 ? null : (it.qty / (last30 / 30)).floor();
      rows.add(Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: it.low ? const Color(0xFFB42318) : LD.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(it.name, style: heading(15, weight: FontWeight.w700))),
            Text('${_q(it.qty)} ${it.unit} ${L(app, 'left', 'बचा')}', style: TextStyle(fontWeight: FontWeight.w800, color: it.low ? const Color(0xFFB42318) : LD.navy)),
          ]),
          const SizedBox(height: 6),
          Text('${L(app, 'Used', 'इस्तेमाल')}: ${_q(used)} ${it.unit}${uc > 0 ? ' (${money(used * uc, cur)})' : ''}  ·  ${L(app, 'Bought', 'खरीदा')}: ${_q(bought)} ${it.unit}'),
          if (kg > 0 && used > 0 && (it.unit == 'kg' || it.unit == 'L' || it.unit == 'l' || it.unit == 'g' || it.unit == 'ml'))
            Text('${L(app, 'Per 10 kg clothes', 'हर 10 kg कपड़े पर')}: ${(used / kg * 10).toStringAsFixed(2)} ${it.unit}', style: const TextStyle(color: LD.slate)),
          if (daysLeft != null)
            Text('${L(app, 'Lasts about', 'लगभग चलेगा')} $daysLeft ${L(app, 'days', 'दिन')}',
                style: TextStyle(color: daysLeft <= 7 ? const Color(0xFFB42318) : LD.slate, fontWeight: daysLeft <= 7 ? FontWeight.w700 : FontWeight.w400)),
          for (final who in _users(d, it.id, from, to))
            Text('  • ${d.nameOf(who.$1)}: ${_q(who.$2)} ${it.unit}', style: const TextStyle(fontSize: 12, color: LD.slate)),
        ]),
      ));
    }
    final monthName = '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][from.month - 1]} ${from.year}';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => _monthsBack++), icon: const Icon(Icons.chevron_left)),
        Expanded(child: Center(child: Text(monthName, style: heading(16, weight: FontWeight.w700)))),
        IconButton(onPressed: _monthsBack == 0 ? null : () => setState(() => _monthsBack--), icon: const Icon(Icons.chevron_right)),
      ]),
      SectionCard(
        child: Row(children: [
          Expanded(child: _kv(L(app, 'Stock used (value)', 'इस्तेमाल (कीमत)'), money(totalCost, cur))),
          Expanded(child: _kv(L(app, 'Clothes washed', 'धुले कपड़े'), '${kg.toStringAsFixed(0)} kg*')),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Text('* kg orders + about 0.25 kg per piece', style: TextStyle(fontSize: 11, color: LD.slate)),
      ),
      ...rows,
    ]);
  }

  List<(String, double)> _users(ShopData d, String itemId, DateTime from, DateTime to) {
    final m = <String, double>{};
    for (final x in d.stockMoves.where((x) => x.itemId == itemId && x.qty < 0 && !x.at.isBefore(from) && x.at.isBefore(to))) {
      m[x.by] = (m[x.by] ?? 0) - x.qty;
    }
    final l = m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return l;
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(color: LD.slate, fontSize: 12)),
        Text(v, style: heading(18)),
      ]);
}

/// Washer / delivery home: quick "ask the boss" and "stock used" buttons + my open requests.
class StaffQuickRow extends StatelessWidget {
  const StaffQuickRow({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final open = d.requests.where((r) => r.by == app.actorId && r.open).length;
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RequestsScreen())),
          icon: const Icon(Icons.campaign_outlined, size: 18),
          label: Text(open == 0 ? L(app, 'Ask boss', 'बॉस से माँगें') : '${L(app, 'My requests', 'मेरी माँग')} ($open)'),
        ),
      ),
      if (app.module('stock')) ...[
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockUseScreen())),
            icon: const Icon(Icons.water_drop_outlined, size: 18),
            label: Text(L(app, 'Stock used', 'स्टॉक इस्तेमाल')),
          ),
        ),
      ],
    ]);
  }
}
