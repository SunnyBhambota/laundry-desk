import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../data/rate_card.dart';
import '../data/shop_data.dart';
import '../data/shop_v12.dart';
import '../models/models.dart';
import '../services/export_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'order_detail_screen.dart';

// ======================= order: outsource, QC, wallet, claims =======================

class OrderOpsCard extends StatelessWidget {
  const OrderOpsCard({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final o = d.orders.where((x) => x.id == orderId).firstOrNull;
    if (o == null || o.status == 'cancelled') return const SizedBox.shrink();
    final cur = app.shop!.currency;
    final c = d.customer(o.customerId);
    final canEdit = app.role != Role.delivery;
    final needQc = !o.qcDone && (o.status == 'ready' || o.status == 'out');

    Widget line(IconData icon, Color color, String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (trailing != null) trailing,
          ]),
        );

    return SectionCard(
      title: L(app, 'Quality, outside work & claims', 'क्वालिटी, बाहर का काम और क्लेम'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // QC
        if (o.qcDone)
          line(Icons.verified_outlined, LD.success,
              '${L(app, 'QC passed', 'QC पास')} · ${d.nameOf(o.qcBy)} · ${whenText(o.qcAt!)}${o.qcNote.isEmpty ? '' : '\n${o.qcNote}'}',
              trailing: app.canManage
                  ? IconButton(tooltip: L(app, 'Undo', 'वापस'), icon: const Icon(Icons.undo, size: 18), onPressed: () => d.undoQc(o, by: app.actorId))
                  : null)
        else if (canEdit)
          line(Icons.fact_check_outlined, needQc ? const Color(0xFFD97706) : LD.slate,
              needQc ? L(app, 'QC pending - check before delivery', 'QC बाकी - डिलीवरी से पहले जाँचें') : L(app, 'Quality check', 'क्वालिटी चेक'),
              trailing: TextButton(onPressed: () => _qcSheet(context, app, o), child: Text(L(app, 'Do QC', 'QC करें')))),
        // outside
        if (o.outsideNow)
          line(Icons.north_east_rounded, const Color(0xFFD97706),
              '${L(app, 'Outside', 'बाहर')}: ${o.outTo} · ${dmy(o.outSentAt!)}${o.outCost > 0 ? ' · ${money(o.outCost, cur)}' : ''}',
              trailing: TextButton(
                  onPressed: () {
                    d.receiveOutside(o, by: app.actorId);
                    toast(context, L(app, 'Marked received back', 'वापस आ गया'));
                  },
                  child: Text(L(app, 'Received', 'मिल गया'))))
        else if (o.outTo.isNotEmpty)
          line(Icons.south_west_rounded, LD.success, '${L(app, 'Was outside', 'बाहर गया था')}: ${o.outTo} · ${L(app, 'back', 'वापस')} ${dmy(o.outBackAt!)}${o.outCost > 0 ? ' · ${money(o.outCost, cur)}' : ''}')
        else if (canEdit && o.open)
          line(Icons.north_east_rounded, LD.slate, L(app, 'Send to another dry cleaner / tailor', 'दूसरे ड्राई क्लीनर / दर्ज़ी को भेजें'),
              trailing: TextButton(onPressed: () => _outsideSheet(context, app, o), child: Text(L(app, 'Send', 'भेजें')))),
        // wallet
        if ((c?.wallet ?? 0) > 0 && o.due > 0 && canEdit)
          line(Icons.account_balance_wallet_outlined, LD.primary, '${L(app, 'Wallet balance', 'वॉलेट बैलेंस')}: ${money(c!.wallet, cur)}',
              trailing: TextButton(
                  onPressed: () {
                    final used = d.payFromWallet(o, by: app.actorId);
                    toast(context, '${L(app, 'Paid from wallet', 'वॉलेट से दिया')}: ${money(used, cur)}');
                  },
                  child: Text(L(app, 'Pay', 'चुकाएँ')))),
        // claims
        for (final cl in o.claims)
          line(cl['kind'] == 'lost' ? Icons.search_off_rounded : Icons.report_problem_outlined, const Color(0xFFDC2626),
              '${cl['kind'] == 'lost' ? L(app, 'Lost', 'खोया') : L(app, 'Damaged', 'ख़राब')}: ${cl['piece']} · ${money((cl['amount'] as num?)?.toDouble() ?? 0, cur)}${(cl['note'] as String? ?? '').isEmpty ? '' : '\n${cl['note']}'}'),
        if (canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _claimSheet(context, app, o),
              icon: const Icon(Icons.report_problem_outlined, size: 18),
              label: Text(L(app, 'Damage / loss claim', 'नुकसान / खोने का क्लेम')),
            ),
          ),
      ]),
    );
  }

  void _qcSheet(BuildContext context, AppState app, LaundryOrder o) {
    final d = app.data!;
    final checks = {
      L(app, 'Stains removed', 'दाग हटे'): true,
      L(app, 'Ironed / folded properly', 'प्रेस / तह ठीक'): true,
      L(app, 'Buttons & zips fine', 'बटन और ज़िप ठीक'): true,
      L(app, 'Piece count matches', 'पीस गिनती सही'): true,
    };
    final note = TextEditingController();
    sheet(context, '${o.code} · QC', (sc) => StatefulBuilder(builder: (sc, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final k in checks.keys.toList())
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(k),
                value: checks[k],
                onChanged: (v) => set(() => checks[k] = v ?? false),
              ),
            TextField(controller: note, decoration: fieldDeco(L(app, 'Note (optional)', 'नोट (ज़रूरी नहीं)'), icon: Icons.edit_note)),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: LD.success, minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                final bad = checks.entries.where((e) => !e.value).map((e) => e.key).toList();
                final n = [if (bad.isNotEmpty) '${L(app, 'Not ok', 'ठीक नहीं')}: ${bad.join(', ')}', if (note.text.trim().isNotEmpty) note.text.trim()].join(' · ');
                d.doQc(o, by: app.actorId, note: n);
                Navigator.pop(sc);
              },
              child: Text(L(app, 'Save QC', 'QC सेव करें')),
            ),
          ]);
        }));
  }

  void _outsideSheet(BuildContext context, AppState app, LaundryOrder o) {
    final d = app.data!;
    final to = TextEditingController();
    final cost = TextEditingController();
    final past = d.orders.where((x) => x.outTo.isNotEmpty).map((x) => x.outTo).toSet().toList();
    sheet(context, '${o.code} → ${L(app, 'outside', 'बाहर')}', (sc) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: to, autofocus: true, decoration: fieldDeco(L(app, 'Whom (dry cleaner / tailor name)', 'किसे (ड्राई क्लीनर / दर्ज़ी का नाम)'), icon: Icons.storefront_outlined)),
          if (past.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, children: [for (final p in past.take(6)) ActionChip(label: Text(p), onPressed: () => to.text = p)]),
            ),
          const SizedBox(height: 10),
          TextField(
              controller: cost,
              keyboardType: TextInputType.number,
              decoration: fieldDeco(L(app, 'Their charge (optional)', 'उनका चार्ज (ज़रूरी नहीं)'), icon: Icons.currency_rupee)),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () {
              if (to.text.trim().isEmpty) return;
              d.sendOutside(o, to.text, double.tryParse(cost.text.trim()) ?? 0, by: app.actorId);
              Navigator.pop(sc);
            },
            child: Text(L(app, 'Send outside', 'बाहर भेजें')),
          ),
        ]));
  }

  void _claimSheet(BuildContext context, AppState app, LaundryOrder o) {
    final d = app.data!;
    var kind = 'damaged';
    final piece = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    sheet(context, '${o.code} · ${L(app, 'Claim', 'क्लेम')}', (sc) => StatefulBuilder(builder: (sc, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, children: [
              Pill(label: L(app, 'Damaged', 'ख़राब हुआ'), on: kind == 'damaged', onTap: () => set(() => kind = 'damaged')),
              Pill(label: L(app, 'Lost', 'खो गया'), on: kind == 'lost', onTap: () => set(() => kind = 'lost')),
            ]),
            const SizedBox(height: 10),
            TextField(controller: piece, decoration: fieldDeco(L(app, 'Which piece (e.g. blue shirt)', 'कौन सा कपड़ा (जैसे नीली शर्ट)'), icon: Icons.checkroom_outlined)),
            const SizedBox(height: 10),
            TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: fieldDeco(L(app, 'Compensation amount', 'मुआवज़े की रकम'), icon: Icons.currency_rupee)),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: fieldDeco(L(app, 'What happened', 'क्या हुआ'), icon: Icons.edit_note)),
            const SizedBox(height: 6),
            Text(L(app, 'The amount is taken off this order\'s unpaid balance.', 'रकम इस ऑर्डर के बाकी बिल से कट जाएगी।'), style: const TextStyle(color: LD.slate, fontSize: 12)),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                if (piece.text.trim().isEmpty) return;
                d.addClaim(o, kind: kind, piece: piece.text, amount: double.tryParse(amount.text.trim()) ?? 0, note: note.text, by: app.actorId);
                Navigator.pop(sc);
              },
              child: Text(L(app, 'Save claim', 'क्लेम सेव करें')),
            ),
          ]);
        }));
  }
}

// ======================= customer wallet =======================

class WalletCard extends StatelessWidget {
  const WalletCard({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final c = d.customer(customerId);
    if (c == null || app.role == Role.washer || app.role == Role.delivery) return const SizedBox.shrink();
    final cur = app.shop!.currency;
    return SectionCard(
      title: L(app, 'Wallet / advance', 'वॉलेट / एडवांस'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(money(c.wallet, cur), style: heading(26))),
          FilledButton.icon(
            onPressed: () => _topUp(context, app, c),
            icon: const Icon(Icons.add, size: 18),
            label: Text(L(app, 'Add money', 'पैसे जोड़ें')),
          ),
        ]),
        if (c.walletLog.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final e in c.walletLog.reversed.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text('${dmy(DateTime.tryParse(e['at'] as String? ?? '') ?? DateTime.now())} · ${e['note']}', style: const TextStyle(color: LD.slate, fontSize: 13))),
                Text(money((e['amount'] as num).toDouble(), cur), style: TextStyle(fontWeight: FontWeight.w700, color: (e['amount'] as num) < 0 ? const Color(0xFFDC2626) : LD.success)),
              ]),
            ),
        ],
      ]),
    );
  }

  void _topUp(BuildContext context, AppState app, Customer c) {
    final amt = TextEditingController();
    var mode = 'cash';
    sheet(context, '${c.name} · ${L(app, 'Wallet', 'वॉलेट')}', (sc) => StatefulBuilder(builder: (sc, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: amt, autofocus: true, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Amount received', 'मिली रकम'), icon: Icons.currency_rupee)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [for (final m in payModes) Pill(label: app.t(m), on: mode == m, onTap: () => set(() => mode = m))]),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                final v = double.tryParse(amt.text.trim()) ?? 0;
                if (v <= 0) return;
                app.data!.walletTopUp(c, v, by: app.actorId, mode: mode);
                Navigator.pop(sc);
              },
              child: Text(L(app, 'Add to wallet', 'वॉलेट में जोड़ें')),
            ),
          ]);
        }));
  }
}

// ======================= outside work list =======================

class OutsideScreen extends StatelessWidget {
  const OutsideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final list = d.outsideOrders;
    final n = DateTime.now();
    final cost = d.outsideCostIn(DateTime(n.year, n.month, 1), DateTime(n.year, n.month + 1, 1));
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Outside work', 'बाहर का काम'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
          child: Row(children: [
            Expanded(child: Text('${list.length} ${L(app, 'orders outside now', 'ऑर्डर अभी बाहर')}', style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('${L(app, 'This month', 'इस महीने')}: ${money(cost, cur)}', style: const TextStyle(color: LD.slate)),
          ]),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Center(child: Text(L(app, 'Nothing is outside.', 'कुछ भी बाहर नहीं है।'), style: const TextStyle(color: LD.slate)))),
        for (final o in list)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id))),
              title: Text('${o.code} · ${d.customer(o.customerId)?.name ?? ''}'),
              subtitle: Text('${o.outTo} · ${L(app, 'sent', 'भेजा')} ${dmy(o.outSentAt ?? o.createdAt)}${o.outCost > 0 ? ' · ${money(o.outCost, cur)}' : ''}'),
              trailing: TextButton(onPressed: () => d.receiveOutside(o, by: app.actorId), child: Text(L(app, 'Received', 'मिल गया'))),
            ),
          ),
      ]),
    );
  }
}

// ======================= claims list =======================

class ClaimsScreen extends StatelessWidget {
  const ClaimsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final list = d.claimOrders;
    final total = list.fold<double>(0, (s, o) => s + o.claimTotal);
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Damage / loss claims', 'नुकसान / खोने के क्लेम'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(child: Text('${L(app, 'Total paid out', 'कुल मुआवज़ा')}: ${money(total, cur)}', style: heading(18))),
        const SizedBox(height: 12),
        if (list.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Center(child: Text(L(app, 'No claims. Good!', 'कोई क्लेम नहीं। बढ़िया!'), style: const TextStyle(color: LD.slate)))),
        for (final o in list)
          for (final cl in o.claims)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id))),
                leading: Icon(cl['kind'] == 'lost' ? Icons.search_off_rounded : Icons.report_problem_outlined, color: const Color(0xFFDC2626)),
                title: Text('${cl['piece']} · ${o.code}'),
                subtitle: Text('${d.customer(o.customerId)?.name ?? ''}${(cl['note'] as String? ?? '').isEmpty ? '' : ' · ${cl['note']}'}'),
                trailing: Text(money((cl['amount'] as num?)?.toDouble() ?? 0, cur), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
      ]),
    );
  }
}

// ======================= party (B2B) bills =======================

class PartyBillsScreen extends StatefulWidget {
  const PartyBillsScreen({super.key});
  @override
  State<PartyBillsScreen> createState() => _PartyBillsScreenState();
}

class _PartyBillsScreenState extends State<PartyBillsScreen> {
  int _back = 0; // 0 = this month, 1 = last month

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final n = DateTime.now();
    final from = DateTime(n.year, n.month - _back, 1);
    final to = DateTime(n.year, n.month - _back + 1, 1);
    final parties = d.partyCustomers;
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Party bills (hotel / company)', 'पार्टी बिल (होटल / कंपनी)'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, children: [
          Pill(label: L(app, 'This month', 'इस महीने'), on: _back == 0, onTap: () => setState(() => _back = 0)),
          Pill(label: L(app, 'Last month', 'पिछला महीना'), on: _back == 1, onTap: () => setState(() => _back = 1)),
        ]),
        const SizedBox(height: 12),
        if (parties.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(L(app, 'No business customers yet. Open a customer and set type "business" - they get one monthly bill with their own rates.', 'अभी कोई बिज़नेस ग्राहक नहीं। ग्राहक खोलकर टाइप "business" करें - उन्हें महीने का एक बिल मिलेगा।'),
                style: const TextStyle(color: LD.slate)),
          ),
        for (final c in parties)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: heading(16, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${L(app, 'Billed', 'बिल')}: ${money(d.billedIn(c.id, from, to), cur)}   ·   ${L(app, 'Total due', 'कुल बाकी')}: ${money(d.dueOf(c.id), cur)}',
                    style: const TextStyle(color: LD.slate)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  OutlinedButton.icon(
                    onPressed: () async => ExportService.sharePdf(
                        await ExportService.statementPdf(shop: app.shop!, data: d, c: c, from: from, to: to), 'party-bill-${c.name}-${dayKey(from)}.pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: Text(L(app, 'Share bill PDF', 'बिल PDF भेजें')),
                  ),
                  if (d.dueOf(c.id) > 0 && c.phone.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => openWhatsApp(c.phone,
                          'Namaste ${c.name}, your pending laundry balance at ${app.shop!.shopName} is $cur ${d.dueOf(c.id).toStringAsFixed(0)}. Please pay at your convenience. Thank you.'),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: Text(L(app, 'Remind', 'याद दिलाएँ')),
                    ),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ======================= alteration service switch =======================

Future<void> enableAlterationFlow(BuildContext context, AppState app) async {
  final d = app.data!;
  final s = app.shop!;
  d.enableAlteration(currencyFactor: DefaultRates.currencyFactor[s.currency] ?? 1);
  if (!s.services.contains('Alteration')) {
    final j = s.toJson();
    j['services'] = [...s.services, 'Alteration'];
    await app.saveShop(ShopProfile.fromJson(j));
  }
  if (context.mounted) toast(context, L(app, 'Alteration / tailoring added. Edit prices in Rate card.', 'अल्टरेशन / सिलाई जुड़ गई। रेट कार्ड में रेट बदलें।'));
}
