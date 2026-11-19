import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/issue_models.dart';
import '../data/ops_models.dart';
import '../data/reports.dart';
import '../services/export_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'order_detail_screen.dart';

const _red = Color(0xFFB42318);
const _orange = Color(0xFFA8430F);

String reasonText(AppState app, String r) {
  const hi = {
    'Stain left': 'दाग रह गया',
    'Not ironed well': 'प्रेस ठीक नहीं',
    'Colour faded': 'रंग छूट गया',
    'Torn / damaged': 'कपड़ा फटा',
    'Smell': 'बदबू',
    'Other': 'कुछ और',
    'Wrong delivery': 'गलत डिलीवरी',
  };
  return app.lang == 'hi' ? (hi[r] ?? r) : r;
}

String stageText(AppState app, String s) {
  const en = {
    'open': 'Opened',
    'pickup': 'Pickup for re-wash',
    'received': 'Back in shop',
    'washing': 'Re-washing',
    'ready': 'Re-wash ready',
    'returned': 'Given back',
    'closed': 'Closed',
    'reopened': 'Re-opened',
    'task': 'Task done',
  };
  const hi = {
    'open': 'खुला',
    'pickup': 'दोबारा धुलाई के लिए पिकअप',
    'received': 'दुकान में वापस',
    'washing': 'दोबारा धुलाई',
    'ready': 'दोबारा तैयार',
    'returned': 'वापस दिया',
    'closed': 'बंद',
    'reopened': 'दोबारा खुला',
    'task': 'काम पूरा',
  };
  return (app.lang == 'hi' ? hi[s] : en[s]) ?? s;
}

class IssueChip extends StatelessWidget {
  const IssueChip(this.i, {super.key});
  final Issue i;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final (bg, fg, label) = i.closed
        ? (const Color(0xFFEDF0F4), const Color(0xFF475569), L(app, 'Closed', 'बंद'))
        : i.reopenCount > 0
            ? (const Color(0xFFFDE8E8), _red, L(app, 'Re-opened', 'दोबारा खुला'))
            : (i.kind == 'wrong'
                ? (const Color(0xFFFDE8E8), _red, L(app, 'Wrong delivery', 'गलत डिलीवरी'))
                : (const Color(0xFFFFEBDD), _orange, L(app, 'Re-wash', 'दोबारा धुलाई')));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

// ---------------- list ----------------

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key});
  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  String _f = 'open';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final scope = app.scopeBranch;
    final all = d.issues.where((i) => scope == null || i.branchId == scope).toList()..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    final list = all.where((i) => _f == 'all' || (_f == 'open' ? i.open : i.closed)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(L(app, 'Complaints & issues', 'शिकायतें और इश्यू')),
        actions: [
          if (app.canManage)
            IconButton(
              tooltip: L(app, 'Issue reports', 'इश्यू रिपोर्ट'),
              icon: const Icon(Icons.insights_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IssueReportsScreen())),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Pill(label: '${L(app, 'Open', 'खुले')} · ${all.where((i) => i.open).length}', on: _f == 'open', onTap: () => setState(() => _f = 'open')),
            const SizedBox(width: 8),
            Pill(label: '${L(app, 'Closed', 'बंद')} · ${all.where((i) => i.closed).length}', on: _f == 'closed', onTap: () => setState(() => _f = 'closed')),
            const SizedBox(width: 8),
            Pill(label: L(app, 'All', 'सभी'), on: _f == 'all', onTap: () => setState(() => _f = 'all')),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? ListView(children: [EmptyState(icon: Icons.verified_outlined, text: L(app, 'No issues here. Great work!', 'यहाँ कोई इश्यू नहीं। बढ़िया!'))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, k) => IssueTile(issue: list[k]),
                ),
        ),
      ]),
    );
  }
}

class IssueTile extends StatelessWidget {
  const IssueTile({super.key, required this.issue});
  final Issue issue;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final i = issue;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssueDetailScreen(issueId: i.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(i.code, style: heading(14, weight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  IssueChip(i),
                ]),
                const SizedBox(height: 4),
                Text('${d.customer(i.customerId)?.name ?? '—'} · ${d.order(i.orderId)?.code ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${reasonText(app, i.reason)} · ${i.fault.where((f) => f != 'none').map(d.nameOf).join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: LD.slate),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(whenText(i.openedAt), style: const TextStyle(fontSize: 11, color: LD.slate)),
              const SizedBox(height: 4),
              Text(
                i.open ? stageText(app, i.stage) : '${i.hoursOpen.toStringAsFixed(1)} h',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i.open ? _orange : LD.slate),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ---------------- complaint / re-wash ----------------

class ComplaintScreen extends StatefulWidget {
  const ComplaintScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<ComplaintScreen> createState() => _ComplaintScreenState();
}

class _ComplaintScreenState extends State<ComplaintScreen> {
  final Set<String> _pieces = {};
  String _reason = complaintReasons.first;
  final Set<String> _fault = {};
  final _note = TextEditingController();
  final _comp = TextEditingController();
  bool _pickup = false;
  bool _wa = true;
  String _agent = '';
  DateTime _due = DateTime.now().add(const Duration(days: 1));
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final o = d.order(widget.orderId)!;
    final c = d.customer(o.customerId);
    final sus = d.suspects(o);
    if (!_init) {
      _init = true;
      _pickup = o.homeDelivery;
      final w = sus.entries.where((e) => e.value == 'washing');
      if (w.isNotEmpty) _fault.add(w.first.key);
      _agent = o.deliveryAgent;
    }
    // piece labels: tag + garment
    final labels = <String>[];
    var n = 0;
    for (final l in o.lines) {
      for (var k = 0; k < l.pieces; k++) {
        n++;
        labels.add('${l.garment} · ${l.service}|${o.code} · $n/${o.pieces}');
      }
    }
    final agents = d.staff.where((s) => s.active && s.role == Role.delivery).toList();

    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Complaint · Re-wash', 'शिकायत · दोबारा धुलाई'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: [
        Text('${o.code} · ${c?.name ?? ''}', style: const TextStyle(color: LD.slate)),
        const SizedBox(height: 10),
        SectionCard(
          title: L(app, 'Which pieces came back?', 'कौन से कपड़े वापस आए?'),
          child: Column(children: [
            for (final p in labels)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _pieces.contains(p),
                onChanged: (v) => setState(() => v == true ? _pieces.add(p) : _pieces.remove(p)),
                title: Text(p.split('|').first),
                secondary: Text(p.split('|').last, style: const TextStyle(fontSize: 11, color: LD.slate, fontFamily: 'monospace')),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'What is the problem?', 'क्या दिक्कत है?'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in complaintReasons) Pill(label: reasonText(app, r), on: _reason == r, onTap: () => setState(() => _reason = r)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _note, decoration: fieldDeco(L(app, 'Note', 'नोट'))),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Whose mistake?', 'गलती किसकी?'),
          child: Column(children: [
            for (final e in sus.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _fault.contains(e.key),
                onChanged: (v) => setState(() => v == true ? _fault.add(e.key) : _fault.remove(e.key)),
                title: Text(d.nameOf(e.key)),
                subtitle: Text(e.value),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _fault.contains('none'),
              onChanged: (v) => setState(() {
                _fault.clear();
                if (v == true) _fault.add('none');
              }),
              title: Text(L(app, 'Nobody (cloth was already like this)', 'किसी की नहीं (कपड़ा पहले से ऐसा था)')),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(L(app, 'Ready again by', 'दोबारा तैयार')),
              trailing: Text(whenText(_due), style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                final p = await showDatePicker(context: context, initialDate: _due, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
                if (p != null) setState(() => _due = DateTime(p.year, p.month, p.day, 18));
              },
            ),
            TextField(
              controller: _comp,
              keyboardType: TextInputType.number,
              decoration: fieldDeco(L(app, 'Compensation / discount (optional)', 'मुआवज़ा / छूट (ज़रूरी नहीं)'), icon: Icons.currency_rupee_rounded),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L(app, 'Pick up from home', 'घर से पिकअप')),
              value: _pickup,
              onChanged: (v) => setState(() => _pickup = v),
            ),
            if (_pickup && agents.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: agents.any((a) => a.id == _agent) ? _agent : null,
                decoration: fieldDeco(L(app, 'Pickup by', 'पिकअप कौन करेगा')),
                items: [for (final a in agents) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => _agent = v ?? ''),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L(app, 'Tell customer on WhatsApp', 'ग्राहक को WhatsApp पर बताएँ')),
              value: _wa,
              onChanged: (v) => setState(() => _wa = v),
            ),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LD.navy, minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
            onPressed: () {
              if (_pieces.isEmpty) {
                toast(context, L(app, 'Choose at least one piece.', 'कम से कम एक कपड़ा चुनें।'));
                return;
              }
              final i = d.openComplaint(
                o: o,
                pieces: _pieces.map((p) => p.split('|').last).toList(),
                reason: _reason,
                by: app.actorId,
                note: _note.text.trim(),
                fault: _fault.toList(),
                compensation: double.tryParse(_comp.text.trim()) ?? 0,
                pickupFromHome: _pickup,
                agent: _agent,
                dueAt: _due,
              );
              if (_wa && c != null) {
                openWhatsApp(c.phone,
                    'Namaste ${c.name}, sorry for the trouble with order ${o.code}. We will clean ${_pieces.length} piece(s) again free of charge and return them by ${whenText(_due)}. – ${app.shop!.shopName}');
              }
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => IssueDetailScreen(issueId: i.id)));
            },
            child: Text('${L(app, 'Open issue · re-wash', 'इश्यू खोलें · दोबारा धुलाई')} (${_pieces.length})'),
          ),
        ),
      ),
    );
  }
}

// ---------------- wrong delivery ----------------

class WrongDeliveryScreen extends StatefulWidget {
  const WrongDeliveryScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<WrongDeliveryScreen> createState() => _WrongDeliveryScreenState();
}

class _WrongDeliveryScreenState extends State<WrongDeliveryScreen> {
  String _sub = 'swap';
  LaundryOrder? _other;
  final Set<String> _fault = {};
  String _agent = '';
  final _note = TextEditingController();
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final o = d.order(widget.orderId)!;
    final sus = d.suspects(o);
    final agents = d.staff.where((s) => s.active && s.role == Role.delivery).toList();
    if (!_init) {
      _init = true;
      _agent = o.deliveryAgent;
      if (o.deliveryAgent.isNotEmpty) _fault.add(o.deliveryAgent);
    }
    final subs = {
      'swap': L(app, 'Two customers\' clothes got swapped', 'दो ग्राहकों के कपड़े आपस में बदल गए'),
      'wrongaddr': L(app, 'Whole order went to the wrong house', 'पूरा ऑर्डर गलत घर पहुँच गया'),
      'missing': L(app, 'Some pieces missing', 'कुछ कपड़े कम पहुँचे'),
    };
    final recent = d.orders
        .where((x) => x.id != o.id && (x.status == 'delivered' || x.status == 'out') && x.createdAt.isAfter(DateTime.now().subtract(const Duration(days: 10))))
        .toList()
      ..sort((a, b) => (b.timeOf('delivered') ?? b.createdAt).compareTo(a.timeOf('delivered') ?? a.createdAt));

    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Wrong delivery', 'गलत डिलीवरी'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: [
        Text('${o.code} · ${d.customer(o.customerId)?.name ?? ''}', style: const TextStyle(color: LD.slate)),
        const SizedBox(height: 10),
        SectionCard(
          title: L(app, 'What happened?', 'क्या हुआ?'),
          child: Column(children: [
            for (final e in subs.entries)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: e.key,
                groupValue: _sub,
                onChanged: (v) => setState(() => _sub = v ?? 'swap'),
                title: Text(e.value),
              ),
          ]),
        ),
        if (_sub == 'swap') ...[
          const SizedBox(height: 12),
          SectionCard(
            title: L(app, 'Swapped with which order?', 'किस ऑर्डर से बदले?'),
            child: Column(children: [
              for (final x in recent.take(12))
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: x.id,
                  groupValue: _other?.id,
                  onChanged: (_) => setState(() => _other = x),
                  title: Text('${d.customer(x.customerId)?.name ?? ''} · ${x.code}'),
                  subtitle: Text(whenText(x.timeOf('delivered') ?? x.createdAt)),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Whose mistake?', 'गलती किसकी?'),
          child: Column(children: [
            for (final e in sus.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _fault.contains(e.key),
                onChanged: (v) => setState(() => v == true ? _fault.add(e.key) : _fault.remove(e.key)),
                title: Text(d.nameOf(e.key)),
                subtitle: Text(e.value),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(children: [
            if (agents.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: agents.any((a) => a.id == _agent) ? _agent : null,
                decoration: fieldDeco(L(app, 'Who will fix it (delivery)', 'कौन ठीक करेगा (डिलीवरी)')),
                items: [for (final a in agents) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => _agent = v ?? ''),
              ),
            const SizedBox(height: 10),
            TextField(controller: _note, decoration: fieldDeco(L(app, 'Note', 'नोट'))),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red, minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
            onPressed: () {
              if (_sub == 'swap' && _other == null) {
                toast(context, L(app, 'Choose the other order.', 'दूसरा ऑर्डर चुनें।'));
                return;
              }
              final i = d.openWrongDelivery(o: o, subKind: _sub, by: app.actorId, other: _other, note: _note.text.trim(), fault: _fault.toList(), agent: _agent);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => IssueDetailScreen(issueId: i.id)));
            },
            child: Text(L(app, 'Open wrong-delivery issue', 'गलत डिलीवरी इश्यू खोलें')),
          ),
        ),
      ),
    );
  }
}

// ---------------- detail ----------------

class IssueDetailScreen extends StatelessWidget {
  const IssueDetailScreen({super.key, required this.issueId});
  final String issueId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final i = d.issue(issueId);
    if (i == null) return Scaffold(appBar: AppBar());
    final o = d.order(i.orderId);
    final c = d.customer(i.customerId);
    final cur = app.shop!.currency;
    final nextStage = const {'open': 'received', 'pickup': 'received', 'received': 'washing', 'washing': 'ready', 'ready': 'returned'}[i.stage];

    Widget kv(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(color: LD.slate, fontSize: 13))),
            Expanded(child: Text(v, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color))),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(i.code), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: IssueChip(i)))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
        SectionCard(
          child: Column(children: [
            kv(L(app, 'Type', 'प्रकार'), i.kind == 'wrong' ? L(app, 'Wrong delivery', 'गलत डिलीवरी') : L(app, 'Complaint · re-wash', 'शिकायत · दोबारा धुलाई')),
            kv(L(app, 'Order', 'ऑर्डर'), '${o?.code ?? ''}${i.otherOrderId.isEmpty ? '' : ' ⇄ ${d.order(i.otherOrderId)?.code ?? ''}'}'),
            kv(L(app, 'Customer', 'ग्राहक'), c?.name ?? ''),
            if (i.pieces.isNotEmpty) kv(L(app, 'Pieces', 'कपड़े'), i.pieces.join(', ')),
            kv(L(app, 'Reason', 'वजह'), '${reasonText(app, i.reason)}${i.note.isEmpty ? '' : ' – ${i.note}'}'),
            kv(L(app, 'Mistake by', 'गलती'), i.fault.isEmpty ? '—' : i.fault.map((f) => f == 'none' ? L(app, 'Nobody', 'किसी की नहीं') : d.nameOf(f)).join(', '), color: _red),
            if (d.branches.length > 1) kv(L(app, 'Branch', 'ब्रांच'), d.branch(i.branchId)?.name ?? ''),
            if (i.compensation > 0) kv(L(app, 'Compensation', 'मुआवज़ा'), money(i.compensation, cur)),
            kv(L(app, 'Opened', 'खुला'), '${whenText(i.openedAt)} · ${d.nameOf(i.openedBy)}'),
            kv(L(app, i.closed ? 'Took' : 'Open for', i.closed ? 'लगा समय' : 'कब से खुला'), '${i.hoursOpen.toStringAsFixed(1)} h'),
            if (i.reopenCount > 0) kv(L(app, 'Re-opened', 'दोबारा खुला'), '${i.reopenCount}×', color: _red),
            if (i.open) kv(L(app, 'Stage', 'अभी'), stageText(app, i.stage)),
            if (i.open) kv(L(app, 'Due', 'तक'), whenText(i.dueAt), color: DateTime.now().isAfter(i.dueAt) ? _red : null),
          ]),
        ),
        if (i.tasks.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: L(app, 'Tasks', 'काम'),
            child: Column(children: [
              for (final tk in i.tasks)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: tk.done,
                  onChanged: tk.done || i.closed ? null : (_) => d.taskDone(i, tk, by: app.actorId),
                  title: Text(tk.text, style: TextStyle(decoration: tk.done ? TextDecoration.lineThrough : null)),
                  subtitle: Text(tk.done
                      ? '${d.nameOf(tk.doneBy)} · ${whenText(tk.doneAt!)}'
                      : (tk.agent.isEmpty ? L(app, 'Not assigned', 'कोई नहीं') : d.nameOf(tk.agent))),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Timeline', 'टाइमलाइन'),
          child: Column(children: [
            for (final h in i.history.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    h.status == 'reopened' || h.status == 'open' ? Icons.error_outline : (h.status == 'closed' ? Icons.check_circle_outline : Icons.radio_button_checked),
                    size: 18,
                    color: h.status == 'reopened' || h.status == 'open' ? _red : (h.status == 'closed' ? LD.success : LD.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(stageText(app, h.status), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('${d.nameOf(h.by)}${h.note.isEmpty ? '' : ' · ${h.note}'}', style: const TextStyle(fontSize: 12, color: LD.slate)),
                    ]),
                  ),
                  Text(whenText(h.at), style: const TextStyle(fontSize: 11, color: LD.slate)),
                ]),
              ),
          ]),
        ),
        if (o != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id))),
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text('${L(app, 'Open order', 'ऑर्डर खोलें')} ${o.code}'),
          ),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                onPressed: () => openWhatsApp(c?.phone ?? '', 'Namaste ${c?.name ?? ''}, update on your complaint ${i.code}: ${stageText(app, i.closed ? 'closed' : i.stage)}. – ${app.shop!.shopName}'),
                child: const Text('WhatsApp'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: i.closed
                  ? FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _red, minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                      onPressed: app.canManage || app.role == Role.counter ? () => _reopen(context, app, i) : null,
                      child: Text(L(app, 'Re-open', 'दोबारा खोलें')),
                    )
                  : (i.kind == 'complaint' && nextStage != null && i.stage != 'returned')
                      ? FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: LD.navy, minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                          onPressed: () => d.issueStage(i, nextStage, by: app.actorId),
                          child: Text('→ ${stageText(app, nextStage)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        )
                      : FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: LD.success, minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                          onPressed: i.tasks.every((x) => x.done) || app.canManage ? () => d.closeIssue(i, by: app.actorId) : null,
                          child: Text(L(app, 'Close issue', 'इश्यू बंद करें')),
                        ),
            ),
          ]),
        ),
      ),
    );
  }

  void _reopen(BuildContext context, AppState app, Issue i) {
    final ctrl = TextEditingController();
    sheet(context, L(app, 'Re-open – why?', 'दोबारा क्यों खोलें?'), (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: ctrl, autofocus: true, decoration: fieldDeco(L(app, 'Reason', 'वजह'))),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              app.data!.reopenIssue(i, by: app.actorId, note: ctrl.text.trim());
              Navigator.pop(c);
            },
            child: Text(L(app, 'Re-open', 'दोबारा खोलें')),
          ),
        ]));
  }
}

// ---------------- reports ----------------

class IssueReportsScreen extends StatefulWidget {
  const IssueReportsScreen({super.key});
  @override
  State<IssueReportsScreen> createState() => _IssueReportsScreenState();
}

class _IssueReportsScreenState extends State<IssueReportsScreen> {
  Period _p = Period.month;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final range = DateRange.of(_p);
    final scope = app.scopeBranch;
    final list = d.issues.where((i) => range.has(i.openedAt) && (scope == null || i.branchId == scope)).toList();
    final ordersN = d.ordersIn(scope).where((o) => range.has(o.createdAt) && o.status != 'cancelled').length;
    final complaints = list.where((i) => i.kind == 'complaint').length;
    final wrongs = list.where((i) => i.kind == 'wrong').length;
    final open = d.issues.where((i) => i.open && (scope == null || i.branchId == scope)).toList()..sort((a, b) => a.openedAt.compareTo(b.openedAt));
    final reopened = list.where((i) => i.reopenCount > 0).length;
    final closed = list.where((i) => i.closed).toList();
    final avgH = closed.isEmpty ? 0.0 : closed.fold<double>(0, (s, i) => s + i.hoursOpen) / closed.length;
    final comp = list.fold<double>(0, (s, i) => s + i.compensation);
    final byReason = <String, double>{};
    final byStaffC = <String, int>{}, byStaffW = <String, int>{};
    final byBranch = <String, int>{};
    final byCustomer = <String, int>{};
    for (final i in list) {
      byReason[i.reason] = (byReason[i.reason] ?? 0) + 1;
      for (final f in i.fault.where((f) => f != 'none')) {
        if (i.kind == 'wrong') {
          byStaffW[f] = (byStaffW[f] ?? 0) + 1;
        } else {
          byStaffC[f] = (byStaffC[f] ?? 0) + 1;
        }
      }
      byBranch[i.branchId] = (byBranch[i.branchId] ?? 0) + 1;
      byCustomer[i.customerId] = (byCustomer[i.customerId] ?? 0) + 1;
    }
    final rMax = byReason.values.fold<double>(0, (a, b) => b > a ? b : a);
    final staffIds = {...byStaffC.keys, ...byStaffW.keys}.toList()
      ..sort((a, b) => ((byStaffC[b] ?? 0) + (byStaffW[b] ?? 0)).compareTo((byStaffC[a] ?? 0) + (byStaffW[a] ?? 0)));
    final repeat = byCustomer.entries.where((e) => e.value > 1).toList()..sort((a, b) => b.value.compareTo(a.value));

    Widget kpi(String label, String value, [Color? color]) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: LD.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: LD.slate, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: heading(19, color: color ?? LD.navy))),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(L(app, 'Issue reports', 'इश्यू रिपोर्ट')),
        actions: [
          IconButton(
            tooltip: 'Excel (CSV)',
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => ExportService.shareCsv(ExportService.issuesCsv(d, list), 'issues.csv'),
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
          childAspectRatio: 2.1,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            kpi(L(app, 'Total issues', 'कुल इश्यू'), '${list.length}'),
            kpi(L(app, 'Open now', 'अभी खुले'), '${open.length}', _red),
            kpi(L(app, 'Complaints / re-wash', 'शिकायत / दोबारा धुलाई'), '$complaints', _orange),
            kpi(L(app, 'Wrong deliveries', 'गलत डिलीवरी'), '$wrongs', _red),
            kpi(L(app, 'Re-opened', 'दोबारा खुले'), '$reopened · ${list.isEmpty ? 0 : (reopened * 100 / list.length).round()}%', const Color(0xFF8A5A00)),
            kpi(L(app, 'Avg time to fix', 'ठीक करने का औसत समय'), '${avgH.toStringAsFixed(1)} h'),
            kpi(L(app, 'Compensation', 'मुआवज़ा'), money(comp, cur), const Color(0xFF8A5A00)),
            kpi(L(app, 'Issue rate', 'इश्यू दर'), '${ordersN == 0 ? 0 : (list.length * 100 / ordersN).toStringAsFixed(1)}%', LD.success),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'By reason', 'वजह के हिसाब से'),
          child: Column(children: [
            for (final e in byReason.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              ShareRow(label: reasonText(app, e.key), value: e.value, max: rMax, text: e.value.toStringAsFixed(0), color: const Color(0xFFE8742A)),
            if (byReason.isEmpty) Text(L(app, 'No issues in this period.', 'इस समय में कोई इश्यू नहीं।'), style: const TextStyle(color: LD.slate)),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'By staff (whose mistake)', 'स्टाफ़ के हिसाब से (गलती किसकी)'),
          child: Column(children: [
            Row(children: [
              const Expanded(child: SizedBox()),
              SizedBox(width: 70, child: Text(L(app, 'Complaint', 'शिकायत'), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: LD.slate))),
              SizedBox(width: 60, child: Text(L(app, 'Wrong', 'गलत'), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: LD.slate))),
            ]),
            for (final id in staffIds)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(
                    child: Text('${d.nameOf(id)} · ${d.staffBy(id) == null ? '' : roleLabel(d.staffBy(id)!.role, t)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(width: 70, child: Text('${byStaffC[id] ?? 0}', textAlign: TextAlign.right)),
                  SizedBox(width: 60, child: Text('${byStaffW[id] ?? 0}', textAlign: TextAlign.right)),
                ]),
              ),
          ]),
        ),
        if (d.branches.length > 1 && scope == null) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: L(app, 'By branch', 'ब्रांच के हिसाब से'),
            child: Column(children: [
              for (final b in d.branches)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [Expanded(child: Text(b.name)), Text('${byBranch[b.id] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700))]),
                ),
            ]),
          ),
        ],
        if (repeat.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: L(app, 'Customers with repeat complaints', 'बार-बार शिकायत वाले ग्राहक'),
            child: Column(children: [
              for (final e in repeat.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [Expanded(child: Text(d.customer(e.key)?.name ?? '—')), Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w700))]),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: '${L(app, 'Open issues', 'खुले इश्यू')} (${open.length})',
          child: Column(children: [
            for (final i in open) ...[IssueTile(issue: i), const SizedBox(height: 8)],
          ]),
        ),
      ]),
    );
  }
}
