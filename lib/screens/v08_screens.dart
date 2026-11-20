import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../data/shop_data.dart';
import '../logic/messages.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/branch_switch.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'order_detail_screen.dart';

String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

// ======================= status change flow =======================

/// One place for every "next step" button:
/// ready → ask rack number + offer WhatsApp · out → offer WhatsApp ·
/// delivered → count the pieces handed over (+ payment is asked by the caller).
Future<bool> changeStatusFlow(BuildContext context, AppState app, LaundryOrder o, String next) async {
  final d = app.data!;
  final c = d.customer(o.customerId);
  final cur = app.shop!.currency;
  void wa() => openWhatsApp(c?.phone ?? '', Messages.statusUpdate(o, shopName: app.shop!.shopName, customerName: c?.name ?? '', currency: cur));

  if (next == 'ready') {
    final rack = TextEditingController(text: o.rack);
    var send = (c?.phone ?? '').isNotEmpty;
    final ok = await sheet<bool>(context, '${o.code} → ${app.t('ready')}', (sc) => StatefulBuilder(builder: (sc, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: rack,
              autofocus: o.rack.isEmpty,
              decoration: fieldDeco(L(app, 'Rack / hanger number (where it is kept)', 'रैक / हैंगर नंबर (कहाँ रखा है)'), icon: Icons.view_module_outlined),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in _usedRacks(d)) ActionChip(label: Text(r), onPressed: () => set(() => rack.text = r)),
            ]),
            if ((c?.phone ?? '').isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.chat_outlined, color: LD.success),
                title: Text(L(app, 'Tell the customer on WhatsApp', 'ग्राहक को WhatsApp पर बताएँ')),
                value: send,
                onChanged: (v) => set(() => send = v),
              ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: LD.success, minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(sc, true),
              child: Text(L(app, 'Mark ready', 'तैयार करें')),
            ),
          ]);
        }));
    if (ok != true) return false;
    o.rack = rack.text.trim();
    d.setStatus(o, 'ready', by: app.actorId);
    if (send) wa();
    return true;
  }

  if (next == 'delivered') {
    var n = o.countOut ?? o.pieces;
    final ok = await sheet<bool>(context, L(app, 'Count the clothes', 'कपड़े गिनें'), (sc) => StatefulBuilder(builder: (sc, set) {
          final bad = n != o.pieces;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${L(app, 'In this order', 'इस ऑर्डर में')}: ${o.pieces} ${app.t('pcs')}', style: heading(16, weight: FontWeight.w700)),
            for (final l in o.lines)
              Text('• ${l.garment} ${ShopData.qtyLabel(l)}${l.details.isEmpty ? '' : ' (${l.details})'}', style: const TextStyle(color: LD.slate)),
            const SizedBox(height: 12),
            Text(L(app, 'How many are you handing over?', 'कितने दे रहे हैं?')),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(onPressed: n > 0 ? () => set(() => n--) : null, icon: const Icon(Icons.remove)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Text('$n', style: heading(34, color: bad ? const Color(0xFFB42318) : LD.success))),
              IconButton.filledTonal(onPressed: () => set(() => n++), icon: const Icon(Icons.add)),
            ]),
            if (bad)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(10)),
                child: Text(
                    n < o.pieces
                        ? L(app, '${o.pieces - n} piece(s) missing! Check the rack before giving. It will be recorded.',
                            '${o.pieces - n} कपड़े कम हैं! देने से पहले रैक देखें। ये रिकॉर्ड होगा।')
                        : L(app, 'More pieces than the order – maybe someone else\'s clothes!', 'ऑर्डर से ज़्यादा कपड़े – शायद किसी और के!'),
                    style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: bad ? const Color(0xFFB42318) : LD.success, minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(sc, true),
              child: Text(bad ? L(app, 'Hand over anyway', 'फिर भी दें') : L(app, 'All counted – hand over', 'सब गिन लिए – दें')),
            ),
          ]);
        }));
    if (ok != true) return false;
    d.countOut(o, n, by: app.actorId);
    d.setStatus(o, 'delivered', by: app.actorId);
    return true;
  }

  d.setStatus(o, next, by: app.actorId);
  if (next == 'out' && (c?.phone ?? '').isNotEmpty && context.mounted) {
    final send = await confirm(context, L(app, 'Tell the customer?', 'ग्राहक को बताएँ?'), L(app, 'Send "out for delivery" on WhatsApp.', 'WhatsApp पर "डिलीवरी के लिए निकले" भेजें।'));
    if (send) wa();
  }
  return true;
}

List<String> _usedRacks(ShopData d) {
  final s = <String>{};
  for (final o in d.orders.reversed) {
    if (o.rack.isNotEmpty) s.add(o.rack);
    if (s.length >= 8) break;
  }
  return s.toList()..sort();
}

// ======================= work assign =======================

/// Owner / manager: who is doing what, what is not given to anyone, auto assign.
class WorkBoardScreen extends StatelessWidget {
  const WorkBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final scope = app.scopeBranch;
    final workers = d.workersIn(scope ?? '');
    final free = d.unassignedWork(scope);
    final n = DateTime.now();
    final day0 = DateTime(n.year, n.month, n.day);
    final month0 = DateTime(n.year, n.month, 1);
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Work board', 'काम का बोर्ड')), actions: const [BranchSwitch()]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 60), children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L(app, 'Auto-assign new orders', 'नए ऑर्डर अपने-आप बाँटें')),
          subtitle: Text(L(app, 'By each washer\'s services (skills), least busy first.', 'हर वॉशर की सर्विस (स्किल) के हिसाब से, जिसके पास कम काम उसे पहले।')),
          value: d.autoAssign,
          onChanged: app.isOwner
              ? (v) {
                  d.autoAssign = v;
                  d.changed();
                }
              : null,
        ),
        const SizedBox(height: 6),
        for (final w in workers)
          Builder(builder: (_) {
            final open = d.openWork(w.id);
            final doing = open.where((x) => x.$1.lines[x.$2].work == 'doing').length;
            final today = d.workDone(w.id, day0, n.add(const Duration(days: 1)));
            final month = d.workDone(w.id, month0, n.add(const Duration(days: 1)));
            return Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LD.line)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Avatar(w.initials, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(w.name, style: heading(15, weight: FontWeight.w700)),
                        Text(w.skills.isEmpty ? L(app, 'All services', 'सब सर्विस') : w.skills.map((x) => hiName(app, x)).join(', '),
                            style: const TextStyle(fontSize: 12, color: LD.slate)),
                      ]),
                    ),
                    if (app.isOwner)
                      IconButton(tooltip: L(app, 'Skills', 'स्किल'), onPressed: () => _skills(context, app, w), icon: const Icon(Icons.tune_rounded)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _stat(L(app, 'To do', 'बाकी'), '${open.length - doing}', const Color(0xFF8A5A00)),
                    _stat(L(app, 'Doing', 'चल रहा'), '$doing', LD.primary),
                    _stat(L(app, 'Done today', 'आज किया'), '${today.$1} pc${today.$2 > 0 ? ' + ${_q(today.$2)} kg' : ''}', LD.success),
                    _stat(L(app, 'This month', 'इस महीने'), '${month.$1}${month.$2 > 0 ? '+${_q(month.$2)}kg' : ''}', LD.navy),
                  ]),
                  for (final x in open.take(4))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          '${x.$1.lines[x.$2].work == 'doing' ? '▶' : '•'} ${x.$1.code} ${x.$1.lines[x.$2].garment} ${ShopData.qtyLabel(x.$1.lines[x.$2])} – ${hiName(app, x.$1.lines[x.$2].service)}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  if (open.length > 4) Text('+${open.length - 4} ${L(app, 'more', 'और')}', style: const TextStyle(fontSize: 12, color: LD.slate)),
                ]),
              ),
            );
          }),
        if (workers.isEmpty)
          EmptyState(icon: Icons.person_add_alt_outlined, text: L(app, 'Add staff with the Washer role first (Staff → Add).', 'पहले वॉशर रोल वाला स्टाफ जोड़ें (Staff → Add)।')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('${L(app, 'Not given to anyone', 'किसी को नहीं दिया')} (${free.length})', style: heading(16, weight: FontWeight.w700))),
          if (free.isNotEmpty && workers.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                var n = 0;
                for (final o in {for (final f in free) f.$1}) {
                  n += d.autoAssignWork(o);
                }
                d.changed();
                toast(context, '$n ${L(app, 'given out', 'बाँट दिए')}');
              },
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(L(app, 'Auto assign', 'अपने-आप बाँटें')),
            ),
        ]),
        for (final f in free)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${f.$1.code} · ${f.$1.lines[f.$2].garment} ${ShopData.qtyLabel(f.$1.lines[f.$2])}'),
            subtitle: Text('${hiName(app, f.$1.lines[f.$2].service)} · ${app.t('dueBy')} ${whenText(f.$1.dueAt)}'),
            trailing: TextButton(onPressed: () => assignLineSheet(context, app, f.$1, f.$2), child: Text(L(app, 'Give', 'दें'))),
          ),
      ]),
    );
  }

  Widget _stat(String k, String v, Color c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 15)),
          Text(k, style: const TextStyle(fontSize: 11, color: LD.slate)),
        ]),
      );

  void _skills(BuildContext context, AppState app, Staff w) {
    final d = app.data!;
    final chosen = {...w.skills};
    sheet(context, '${w.name} – ${L(app, 'skills', 'स्किल')}', (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(L(app, 'Which services does this person do? (none = all)', 'ये कौन सी सर्विस करते हैं? (कुछ नहीं = सब)'), style: const TextStyle(color: LD.slate)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final sv in app.shop!.services)
                Pill(label: hiName(app, sv), on: chosen.contains(sv), onTap: () => set(() => chosen.contains(sv) ? chosen.remove(sv) : chosen.add(sv))),
            ]),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                w.skills = chosen.toList();
                d.changed();
                Navigator.pop(c);
              },
              child: Text(app.t('save')),
            ),
          ]);
        }));
  }
}

/// Pick who does one line of an order.
void assignLineSheet(BuildContext context, AppState app, LaundryOrder o, int i) {
  final d = app.data!;
  final l = o.lines[i];
  final ws = d.workersIn(o.branchId);
  sheet(context, '${l.garment} ${ShopData.qtyLabel(l)} – ${hiName(app, l.service)}', (c) => Column(children: [
        for (final w in ws)
          ListTile(
            leading: Avatar(w.initials, size: 34),
            title: Text(w.name),
            subtitle: Text('${d.openPieces(w.id)} ${L(app, 'pieces pending', 'कपड़े बाकी')}${w.skills.contains(l.service) ? ' · ✓ ${hiName(app, l.service)}' : ''}'),
            trailing: l.worker == w.id ? const Icon(Icons.check_circle, color: LD.success) : null,
            onTap: () {
              d.assignLine(o, i, w.id, by: app.actorId);
              Navigator.pop(c);
            },
          ),
        if (l.worker.isNotEmpty)
          TextButton(
            onPressed: () {
              d.assignLine(o, i, '', by: app.actorId);
              Navigator.pop(c);
            },
            child: Text(L(app, 'Remove person', 'व्यक्ति हटाएँ')),
          ),
      ]));
}

/// Order page card: each line with its person and progress.
class OrderWorkCard extends StatelessWidget {
  const OrderWorkCard({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final o = d.order(orderId);
    if (o == null || o.status == 'pickup' || o.status == 'cancelled') return const SizedBox.shrink();
    final canAssign = app.canManage || app.role == Role.counter;
    return SectionCard(
      title: L(app, 'Who is doing it', 'कौन कर रहा है'),
      child: Column(children: [
        for (var i = 0; i < o.lines.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              o.lines[i].work == 'done' ? Icons.check_circle : (o.lines[i].work == 'doing' ? Icons.play_circle_fill : Icons.radio_button_unchecked),
              color: o.lines[i].work == 'done' ? LD.success : (o.lines[i].work == 'doing' ? LD.primary : LD.slate),
            ),
            title: Text('${o.lines[i].garment} ${ShopData.qtyLabel(o.lines[i])} – ${hiName(app, o.lines[i].service)}'),
            subtitle: Text(o.lines[i].worker.isEmpty
                ? L(app, 'Not given to anyone', 'किसी को नहीं दिया')
                : '${d.nameOf(o.lines[i].worker)}${o.lines[i].workAt == null ? '' : ' · ${whenText(o.lines[i].workAt!)}'}'),
            trailing: canAssign && o.open && o.lines[i].work != 'done'
                ? TextButton(onPressed: () => assignLineSheet(context, app, o, i), child: Text(o.lines[i].worker.isEmpty ? L(app, 'Give', 'दें') : L(app, 'Change', 'बदलें')))
                : null,
          ),
      ]),
    );
  }
}

/// Washer: only my work, with Start / Done. Can also take work nobody has.
class MyWorkScreen extends StatelessWidget {
  const MyWorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final me = app.actorId;
    final mine = d.openWork(me)..sort((a, b) => a.$1.express == b.$1.express ? a.$1.dueAt.compareTo(b.$1.dueAt) : (a.$1.express ? -1 : 1));
    final free = d.unassignedWork(app.staffUser?.branchId ?? app.scopeBranch);
    final n = DateTime.now();
    final today = d.workDone(me, DateTime(n.year, n.month, n.day), n.add(const Duration(days: 1)));
    final byOrder = <LaundryOrder, List<int>>{};
    for (final w in mine) {
      byOrder.putIfAbsent(w.$1, () => []).add(w.$2);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(0, 0, 0, 20), shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), children: [
      Row(children: [
        Expanded(child: Text('${L(app, 'My work', 'मेरा काम')} (${mine.length})', style: heading(17, weight: FontWeight.w700))),
        Text('${L(app, 'Done today', 'आज किया')}: ${today.$1} pc${today.$2 > 0 ? ' + ${_q(today.$2)} kg' : ''}',
            style: const TextStyle(color: LD.success, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      if (mine.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(L(app, 'Nothing given to you right now.', 'अभी आपको कोई काम नहीं दिया गया।'), style: const TextStyle(color: LD.slate)),
        ),
      for (final e in byOrder.entries)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: e.key.late ? const Color(0xFFB42318) : LD.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(e.key.code, style: heading(15, weight: FontWeight.w700)),
              if (e.key.express) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.bolt_rounded, color: Color(0xFFE8742A), size: 18)),
              const Spacer(),
              Text('${app.t('dueBy')} ${whenText(e.key.dueAt)}', style: TextStyle(fontSize: 12, color: e.key.late ? const Color(0xFFB42318) : LD.slate)),
            ]),
            for (final i in e.value)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${e.key.lines[i].garment} ${ShopData.qtyLabel(e.key.lines[i])} – ${hiName(app, e.key.lines[i].service)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (e.key.lines[i].details.isNotEmpty || e.key.lines[i].note.isNotEmpty)
                        Text([e.key.lines[i].details, if (e.key.lines[i].note.isNotEmpty) '⚠ ${e.key.lines[i].note}'].where((x) => x.isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 12, color: Color(0xFFA8430F))),
                    ]),
                  ),
                  if (e.key.lines[i].work != 'doing')
                    OutlinedButton(onPressed: () => d.lineWork(e.key, i, 'doing', by: me), child: Text(L(app, 'Start', 'शुरू'))),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: LD.success),
                    onPressed: () => d.lineWork(e.key, i, 'done', by: me),
                    child: Text(L(app, 'Done', 'हो गया')),
                  ),
                ]),
              ),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: e.key.id))),
              child: Text(app.t('open2')),
            ),
          ]),
        ),
      if (free.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('${L(app, 'Nobody has these – take one', 'ये किसी के पास नहीं – ले लें')} (${free.length})', style: heading(15, weight: FontWeight.w700)),
        for (final f in free.take(15))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${f.$1.code} · ${f.$1.lines[f.$2].garment} ${ShopData.qtyLabel(f.$1.lines[f.$2])} – ${hiName(app, f.$1.lines[f.$2].service)}'),
            trailing: TextButton(onPressed: () => d.assignLine(f.$1, f.$2, me, by: me), child: Text(L(app, 'Take', 'लें'))),
          ),
      ],
    ]);
  }
}

// ======================= notice board =======================

class NoticeBoardScreen extends StatelessWidget {
  const NoticeBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final boss = app.canManage;
    final branch = app.staffUser?.branchId ?? app.scopeBranch ?? '';
    final list = boss
        ? (d.notices.where((n) => app.scopeBranch == null || n.branchId.isEmpty || n.branchId == app.scopeBranch).toList()..sort((a, b) => b.at.compareTo(a.at)))
        : d.noticesFor(app.actorId, branch);
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Notice board', 'नोटिस बोर्ड'))),
      floatingActionButton: boss
          ? FloatingActionButton.extended(onPressed: () => _new(context, app), icon: const Icon(Icons.campaign_outlined), label: Text(L(app, 'New notice', 'नया नोटिस')))
          : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
        if (list.isEmpty) EmptyState(icon: Icons.campaign_outlined, text: L(app, 'No notices yet.', 'अभी कोई नोटिस नहीं।')),
        for (final n in list)
          Builder(builder: (_) {
            final team = d.staff.where((s) => s.active && (n.branchId.isEmpty || s.branchId == n.branchId)).toList();
            final read = n.readBy.contains(app.actorId);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: !boss && !read ? const Color(0xFFFFF4D6) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LD.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(n.text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                    '${d.nameOf(n.by)} · ${whenText(n.at)}${n.branchId.isEmpty ? '' : ' · ${d.branch(n.branchId)?.name ?? ''}'}',
                    style: const TextStyle(fontSize: 12, color: LD.slate)),
                if (boss)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${L(app, 'Read', 'पढ़ा')}: ${team.where((s) => n.readBy.contains(s.id)).map((s) => s.name.split(' ').first).join(', ')}'
                      '${team.any((s) => !n.readBy.contains(s.id)) ? '  ·  ${L(app, 'Not yet', 'अभी नहीं')}: ${team.where((s) => !n.readBy.contains(s.id)).map((s) => s.name.split(' ').first).join(', ')}' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  )
                else if (!read)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(onPressed: () => d.readNotice(n, app.actorId), child: Text(L(app, 'OK, read it', 'ठीक है, पढ़ लिया'))),
                  ),
              ]),
            );
          }),
      ]),
    );
  }

  void _new(BuildContext context, AppState app) {
    final d = app.data!;
    final text = TextEditingController();
    String branch = app.staffUser?.branchId ?? app.scopeBranch ?? '';
    sheet(context, L(app, 'Notice to staff', 'स्टाफ के लिए नोटिस'), (c) => StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: text, maxLines: 4, autofocus: true, decoration: fieldDeco(L(app, 'Message', 'संदेश'))),
            if (app.isOwner && d.branches.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Pill(label: L(app, 'All branches', 'सभी ब्रांच'), on: branch.isEmpty, onTap: () => set(() => branch = '')),
                for (final b in d.branches) Pill(label: b.name, on: branch == b.id, onTap: () => set(() => branch = b.id)),
              ]),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                if (text.text.trim().length < 2) return;
                d.addNotice(text.text, by: app.actorId, branchId: branch);
                Navigator.pop(c);
              },
              child: Text(L(app, 'Send to staff', 'स्टाफ को भेजें')),
            ),
          ]);
        }));
  }
}

/// Staff home: unread notices on top.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    if (app.isOwner || app.staffUser == null) return const SizedBox.shrink();
    final unread = d.noticesFor(app.actorId, app.staffUser!.branchId).where((n) => !n.readBy.contains(app.actorId)).toList();
    if (unread.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: const Icon(Icons.campaign, color: Color(0xFF8A5A00)),
          title: Text(unread.first.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${unread.length} ${L(app, 'new notice(s) from the boss', 'बॉस का नया नोटिस')}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticeBoardScreen())),
        ),
      ),
    );
  }
}

// ======================= leave =======================

void leaveSheet(BuildContext context, AppState app) {
  final d = app.data!;
  DateTime? from;
  DateTime? to;
  final note = TextEditingController();
  sheet(context, L(app, 'Ask for leave', 'छुट्टी माँगें'), (c) => StatefulBuilder(builder: (c, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlinedButton.icon(
            onPressed: () async {
              final n = DateTime.now();
              final r = await showDateRangePicker(context: c, firstDate: n.subtract(const Duration(days: 1)), lastDate: n.add(const Duration(days: 120)));
              if (r != null) {
                set(() {
                  from = r.start;
                  to = r.end;
                });
              }
            },
            icon: const Icon(Icons.date_range_outlined),
            label: Text(from == null ? L(app, 'Pick dates', 'तारीख चुनें') : '${dmy(from!)} – ${dmy(to!)} (${to!.difference(from!).inDays + 1} ${L(app, 'days', 'दिन')})'),
          ),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: fieldDeco(L(app, 'Reason', 'वजह'))),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: from == null
                ? null
                : () {
                    d.addLeave(by: app.actorId, branchId: app.staffUser?.branchId ?? d.branches.first.id, from: from!, to: to!, note: note.text);
                    Navigator.pop(c);
                    toast(context, L(app, 'Leave request sent.', 'छुट्टी की रिक्वेस्ट भेज दी।'));
                  },
            child: Text(L(app, 'Send', 'भेजें')),
          ),
        ]);
      }));
}

// ======================= daily target =======================

class TargetCard extends StatelessWidget {
  const TargetCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    if (d.dailyTarget <= 0 && d.dailyOrderTarget <= 0) {
      if (!app.isOwner) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          onPressed: () => targetSheet(context, app),
          icon: const Icon(Icons.flag_outlined),
          label: Text(L(app, 'Set a daily target', 'रोज़ का टारगेट रखें')),
        ),
      );
    }
    final scope = app.scopeBranch;
    final n = DateTime.now();
    final k = dayKey(n);
    final today = d.ordersIn(scope).where((o) => o.status != 'cancelled' && dayKey(o.createdAt) == k).toList();
    final sales = today.fold<double>(0, (s, o) => s + o.total);
    // target is for the whole shop; one branch gets its share
    final share = scope == null || d.branches.length < 2 ? 1.0 : 1 / d.branches.length;
    final tSales = d.dailyTarget * share;
    final tOrders = (d.dailyOrderTarget * share).ceil();
    Widget bar(String label, double v, double t, String text) {
      final f = t <= 0 ? 0.0 : (v / t).clamp(0, 1).toDouble();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: f >= 1 ? LD.success : LD.navy)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: f, minHeight: 9, color: f >= 1 ? LD.success : LD.primary, backgroundColor: const Color(0xFFEDF0F4)),
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SectionCard(
        title: L(app, 'Today\'s target', 'आज का टारगेट'),
        action: app.isOwner ? TextButton(onPressed: () => targetSheet(context, app), child: Text(app.t('edit'))) : null,
        child: Column(children: [
          if (tSales > 0) bar(app.t('sales'), sales, tSales, '${money(sales, app.shop!.currency)} / ${money(tSales, app.shop!.currency)}'),
          if (tOrders > 0) bar(app.t('orders'), today.length.toDouble(), tOrders.toDouble(), '${today.length} / $tOrders'),
        ]),
      ),
    );
  }
}

void targetSheet(BuildContext context, AppState app) {
  final d = app.data!;
  final a = TextEditingController(text: d.dailyTarget <= 0 ? '' : d.dailyTarget.toStringAsFixed(0));
  final b = TextEditingController(text: d.dailyOrderTarget <= 0 ? '' : '${d.dailyOrderTarget}');
  sheet(context, L(app, 'Daily target (whole shop)', 'रोज़ का टारगेट (पूरी दुकान)'), (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: a, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Sales per day', 'रोज़ की बिक्री'), icon: Icons.currency_rupee)),
        const SizedBox(height: 10),
        TextField(controller: b, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Orders per day', 'रोज़ के ऑर्डर'))),
        const SizedBox(height: 6),
        Text(L(app, 'With several branches each branch sees its equal share.', 'कई ब्रांच हों तो हर ब्रांच को बराबर हिस्सा दिखेगा।'), style: const TextStyle(fontSize: 12, color: LD.slate)),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () {
            d.dailyTarget = double.tryParse(a.text) ?? 0;
            d.dailyOrderTarget = int.tryParse(b.text) ?? 0;
            d.changed();
            Navigator.pop(c);
          },
          child: Text(app.t('save')),
        ),
      ]));
}

// ======================= cash drawer =======================

class CashDrawerCard extends StatelessWidget {
  const CashDrawerCard({super.key, this.branchId});
  final String? branchId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final b = branchId ?? app.staffUser?.branchId ?? app.scopeBranch ?? (d.branches.length == 1 ? d.branches.first.id : null);
    if (b == null) {
      return SectionCard(
        title: L(app, 'Cash drawer', 'कैश ड्रॉअर'),
        child: Text(L(app, 'Pick one branch (top right) to open / close its drawer.', 'ड्रॉअर खोलने / बंद करने के लिए ऊपर से एक ब्रांच चुनें।'), style: const TextStyle(color: LD.slate)),
      );
    }
    final n = DateTime.now();
    final c = d.cashDay(b, n);
    final expected = d.expectedCash(b, n);
    final opened = c.openedAt != null;
    final closed = c.closing != null;
    final diff = closed ? c.closing! - expected : 0.0;
    return SectionCard(
      title: '${L(app, 'Cash drawer', 'कैश ड्रॉअर')}${d.branches.length > 1 ? ' · ${d.branch(b)?.name ?? ''}' : ''}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            opened
                ? '${L(app, 'Opened with', 'शुरुआत में')} ${money(c.opening, cur)} · ${d.nameOf(c.openedBy)} ${hm(c.openedAt!)}'
                : L(app, 'Not opened today. Count the cash in the drawer and start.', 'आज ड्रॉअर नहीं खुला। ड्रॉअर का कैश गिनकर शुरू करें।'),
            style: const TextStyle(color: LD.slate)),
        const SizedBox(height: 6),
        Text('${L(app, 'Should be in drawer now', 'अभी ड्रॉअर में होना चाहिए')}: ${money(expected, cur)}', style: heading(17, weight: FontWeight.w700)),
        Text(L(app, '= opening + cash taken − cash refunds − expenses today', '= शुरुआत + आया कैश − लौटाया कैश − आज के खर्चे'), style: const TextStyle(fontSize: 11, color: LD.slate)),
        if (closed)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: diff.abs() < 1 ? const Color(0xFFE7F6EE) : const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(10)),
            child: Text(
              '${L(app, 'Counted', 'गिना')} ${money(c.closing!, cur)} · ${d.nameOf(c.closedBy)} ${hm(c.closedAt!)} · '
              '${diff.abs() < 1 ? L(app, 'Matches ✓', 'बराबर ✓') : (diff < 0 ? '${L(app, 'Short', 'कम')} ${money(-diff, cur)}' : '${L(app, 'Extra', 'ज़्यादा')} ${money(diff, cur)}')}'
              '${c.note.isEmpty ? '' : ' · ${c.note}'}',
              style: TextStyle(fontWeight: FontWeight.w700, color: diff.abs() < 1 ? LD.success : const Color(0xFFB42318)),
            ),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _amount(context, app, L(app, 'Opening cash', 'शुरुआत का कैश'), (v, _) => d.openDrawer(b, v, by: app.actorId)),
              child: Text(opened ? L(app, 'Change opening', 'शुरुआत बदलें') : L(app, 'Open drawer', 'ड्रॉअर खोलें')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () => _amount(context, app, L(app, 'Count the cash now', 'अभी कैश गिनें'), (v, note) => d.closeDrawer(b, v, by: app.actorId, note: note),
                  withNote: true),
              child: Text(L(app, 'Close / count', 'बंद करें / गिनें')),
            ),
          ),
        ]),
      ]),
    );
  }

  void _amount(BuildContext context, AppState app, String title, void Function(double, String) done, {bool withNote = false}) {
    final a = TextEditingController();
    final note = TextEditingController();
    sheet(context, title, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: a, autofocus: true, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Amount', 'रकम'), icon: Icons.currency_rupee)),
          if (withNote) ...[
            const SizedBox(height: 10),
            TextField(controller: note, decoration: fieldDeco(L(app, 'Note (if not matching)', 'नोट (अगर बराबर नहीं)'))),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(a.text);
              if (v == null || v < 0) return;
              done(v, note.text);
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }
}

// ======================= audit log: who changed what =======================

const _auditKinds = {
  'order.new': ('New order', 'नया ऑर्डर'),
  'order.edit': ('Order edited', 'ऑर्डर बदला'),
  'order.move': ('Order moved branch', 'ऑर्डर ब्रांच बदली'),
  'status.cancelled': ('Order cancelled', 'ऑर्डर कैंसिल'),
  'pay': ('Payment', 'पेमेंट'),
  'refund': ('Refund', 'रिफंड'),
  'customer.delete': ('Customer deleted', 'ग्राहक हटाया'),
  'staff.move': ('Staff moved', 'स्टाफ ब्रांच बदली'),
  'count.mismatch': ('Piece count did not match', 'कपड़ों की गिनती गलत'),
  'cash.open': ('Cash drawer opened', 'ड्रॉअर खुला'),
  'cash.close': ('Cash drawer counted', 'ड्रॉअर गिना'),
  'work.assign': ('Work given', 'काम दिया'),
  'request.new': ('Staff request', 'स्टाफ की माँग'),
  'leave.new': ('Leave asked', 'छुट्टी माँगी'),
  'notice': ('Notice sent', 'नोटिस भेजा'),
  'issue.open': ('Complaint opened', 'शिकायत खुली'),
  'issue.reopened': ('Complaint re-opened', 'शिकायत फिर खुली'),
};

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String _who = '';
  bool _money = false;
  final _q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final q = _q.text.trim().toLowerCase();
    const moneyKinds = {'order.edit', 'pay', 'refund', 'status.cancelled', 'cash.open', 'cash.close', 'count.mismatch', 'customer.delete'};
    final list = d.activity
        .where((a) => _auditKinds.containsKey(a.kind) || a.kind.startsWith('request.') || a.kind.startsWith('work.'))
        .where((a) => _who.isEmpty || a.by == _who)
        .where((a) => !_money || moneyKinds.contains(a.kind))
        .where((a) => q.isEmpty || a.text.toLowerCase().contains(q) || d.nameOf(a.by).toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final people = {for (final a in d.activity) a.by};
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Who changed what', 'किसने क्या बदला'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(controller: _q, onChanged: (_) => setState(() {}), decoration: fieldDeco(L(app, 'Search order no. / name', 'ऑर्डर नंबर / नाम खोजें'), icon: Icons.search)),
        ),
        SizedBox(
          height: 50,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
            Pill(label: L(app, 'Money only', 'सिर्फ़ पैसा'), on: _money, onTap: () => setState(() => _money = !_money)),
            const SizedBox(width: 8),
            Pill(label: L(app, 'Everyone', 'सब'), on: _who.isEmpty, onTap: () => setState(() => _who = '')),
            for (final p in people) ...[
              const SizedBox(width: 8),
              Pill(label: d.nameOf(p).split(' ').first, on: _who == p, onTap: () => setState(() => _who = p)),
            ],
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(L(app, 'Nothing here.', 'यहाँ कुछ नहीं।')))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  itemCount: list.length.clamp(0, 400),
                  itemBuilder: (_, i) {
                    final a = list[i];
                    final k = _auditKinds[a.kind];
                    final label = k == null ? a.kind : L(app, k.$1, k.$2);
                    final red = {'refund', 'status.cancelled', 'customer.delete', 'count.mismatch', 'order.edit'}.contains(a.kind);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(red ? Icons.warning_amber_rounded : Icons.history, color: red ? const Color(0xFFB42318) : LD.slate),
                      title: Text('$label · ${d.nameOf(a.by)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${a.text}\n${whenText(a.at)}'),
                      isThreeLine: true,
                      onTap: a.orderId.isEmpty || d.order(a.orderId) == null
                          ? null
                          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: a.orderId))),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
