import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../data/shop_data.dart';
import '../data/shop_v13.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'new_order_screen.dart';
import 'order_detail_screen.dart';

// ======================= memberships =======================

class MembershipsScreen extends StatelessWidget {
  const MembershipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final due = d.membershipsToRenew;
    final active = d.activeMemberships;

    Widget tile((Customer, CustPackage) e, {required bool renew}) {
      final c = e.$1, p = e.$2;
      final plan = d.planOf(p);
      final ended = p.end.isBefore(DateTime.now());
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.name} · ${p.name}', style: heading(15, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                '${p.remaining.toStringAsFixed(p.unit == 'kg' ? 1 : 0)} / ${p.credits.toStringAsFixed(0)} ${p.unit} ${L(app, 'left', 'बाकी')} · ${ended ? L(app, 'ended', 'ख़त्म') : L(app, 'till', 'तक')} ${dmy(p.end)}',
                style: TextStyle(color: ended ? const Color(0xFFDC2626) : LD.slate)),
            if (renew) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (c.phone.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => openWhatsApp(c.phone,
                        'Namaste ${c.name}, your ${p.name} plan at ${app.shop!.shopName} ${ended ? 'has ended' : 'is ending on ${dmy(p.end)}'}${p.remaining > 0 ? ' (${p.remaining.toStringAsFixed(0)} ${p.unit} left)' : ''}. Renew to keep your savings!'),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: Text(L(app, 'Remind', 'याद दिलाएँ')),
                  ),
                if (plan != null)
                  FilledButton.icon(
                    onPressed: () async {
                      if (!await confirm(context, L(app, 'Renew plan', 'प्लान रिन्यू'), '${p.name} · ${money(plan.price, cur)} (${c.name})', ok: L(app, 'Renew', 'रिन्यू'))) return;
                      d.sellPackage(c, plan, by: app.actorId, branchId: app.scopeBranch ?? d.branches.first.id);
                      if (context.mounted) toast(context, L(app, 'Renewed', 'रिन्यू हो गया'));
                    },
                    icon: const Icon(Icons.autorenew, size: 18),
                    label: Text('${L(app, 'Renew', 'रिन्यू')} ${money(plan.price, cur)}'),
                  ),
              ]),
            ],
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Memberships', 'मेंबरशिप'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(L(app, 'To renew (ending soon / nearly used)', 'रिन्यू करने वाले (जल्दी ख़त्म / लगभग इस्तेमाल)'), style: heading(15, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (due.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(L(app, 'Nobody to renew now.', 'अभी कोई रिन्यू नहीं।'), style: const TextStyle(color: LD.slate))),
        for (final e in due) tile(e, renew: true),
        const SizedBox(height: 14),
        Text('${L(app, 'Active members', 'चालू सदस्य')} (${active.length})', style: heading(15, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final e in active) tile(e, renew: false),
      ]),
    );
  }
}

// ======================= repeat pickups =======================

class RepeatPickupsScreen extends StatelessWidget {
  const RepeatPickupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final due = d.repeatsDue;
    final all = d.customers.where((c) => c.repeat != null).toList();
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Regular pickups', 'नियमित पिकअप'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (app.isOwner)
          SectionCard(
            child: Row(children: [
              Expanded(child: Text('${L(app, 'Max pickups per slot', 'एक स्लॉट में अधिकतम पिकअप')}: ${d.slotLimit == 0 ? L(app, 'no limit', 'कोई सीमा नहीं') : d.slotLimit}', style: const TextStyle(fontWeight: FontWeight.w600))),
              IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: d.slotLimit == 0 ? null : () { d.slotLimit--; d.changed(); }),
              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () { d.slotLimit++; d.changed(); }),
            ]),
          ),
        const SizedBox(height: 12),
        Text(L(app, 'Due today / tomorrow', 'आज / कल के पिकअप'), style: heading(15, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (due.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(L(app, 'No regular pickup due.', 'कोई नियमित पिकअप बाकी नहीं।'), style: const TextStyle(color: LD.slate))),
        for (final c in due)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: heading(15, weight: FontWeight.w700)),
                Text('${dmy(d.repeatNext(c)!)} · ${c.repeat?['slot'] ?? ''} · ${L(app, 'every', 'हर')} ${c.repeat?['every']} ${L(app, 'days', 'दिन')}', style: const TextStyle(color: LD.slate)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (c.phone.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => openWhatsApp(c.phone, 'Namaste ${c.name}, your regular laundry pickup from ${app.shop!.shopName} is due on ${dmy(d.repeatNext(c)!)}. Reply if you want to change the time.'),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: Text(L(app, 'Remind', 'याद दिलाएँ')),
                    ),
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => NewOrderScreen(customerId: c.id)));
                      if (context.mounted && await confirm(context, L(app, 'Pickup done?', 'पिकअप हो गया?'), L(app, 'Set the next date.', 'अगली तारीख़ तय करें।'), ok: L(app, 'Yes', 'हाँ'))) d.repeatDone(c);
                    },
                    icon: const Icon(Icons.add_task, size: 18),
                    label: Text(L(app, 'Book order', 'ऑर्डर बनाएँ')),
                  ),
                  TextButton(onPressed: () => d.repeatDone(c), child: Text(L(app, 'Skip', 'छोड़ें'))),
                ]),
              ]),
            ),
          ),
        const SizedBox(height: 14),
        Text('${L(app, 'All regular customers', 'सभी नियमित ग्राहक')} (${all.length})', style: heading(15, weight: FontWeight.w700)),
        for (final c in all)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.name),
            subtitle: Text('${L(app, 'every', 'हर')} ${c.repeat?['every']} ${L(app, 'days', 'दिन')} · ${c.repeat?['slot'] ?? ''} · ${L(app, 'next', 'अगला')} ${dmy(d.repeatNext(c)!)}'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => d.clearRepeat(c)),
          ),
        const SizedBox(height: 10),
        Text(L(app, 'To add a customer: open the customer → "Regular pickup".', 'ग्राहक जोड़ने के लिए: ग्राहक खोलें → "नियमित पिकअप"।'), style: const TextStyle(color: LD.slate, fontSize: 12)),
      ]),
    );
  }
}

/// On the customer page: set a regular pickup.
class RepeatCard extends StatelessWidget {
  const RepeatCard({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final c = d.customer(customerId);
    if (c == null || app.role == Role.washer || app.role == Role.delivery) return const SizedBox.shrink();
    return SectionCard(
      title: L(app, 'Regular pickup', 'नियमित पिकअप'),
      child: c.repeat == null
          ? Row(children: [
              Expanded(child: Text(L(app, 'Not set', 'तय नहीं'), style: const TextStyle(color: LD.slate))),
              OutlinedButton(onPressed: () => _set(context, app, c), child: Text(L(app, 'Set', 'तय करें'))),
            ])
          : Row(children: [
              Expanded(child: Text('${L(app, 'Every', 'हर')} ${c.repeat!['every']} ${L(app, 'days', 'दिन')} · ${c.repeat!['slot'] ?? ''} · ${L(app, 'next', 'अगला')} ${dmy(d.repeatNext(c)!)}', style: const TextStyle(fontWeight: FontWeight.w600))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => d.clearRepeat(c)),
            ]),
    );
  }

  void _set(BuildContext context, AppState app, Customer c) {
    var every = 7;
    var slot = '12–3';
    sheet(context, '${c.name} · ${L(app, 'Regular pickup', 'नियमित पिकअप')}', (sc) => StatefulBuilder(builder: (sc, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, children: [
              for (final e in const [(7, 'Weekly'), (14, '2 weeks'), (30, 'Monthly')]) Pill(label: e.$2, on: every == e.$1, onTap: () => set(() => every = e.$1)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [for (final sl in const ['9–12', '12–3', '3–6', '6–9']) Pill(label: sl, on: slot == sl, onTap: () => set(() => slot = sl))]),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                app.data!.setRepeat(c, every: every, slot: slot);
                Navigator.pop(sc);
              },
              child: Text(L(app, 'Save', 'सेव')),
            ),
          ]);
        }));
  }
}

// ======================= smart rack =======================

class RackScreen extends StatelessWidget {
  const RackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final map = d.rackMap;
    final free = d.freeRacks;
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Racks', 'रैक'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
          child: Row(children: [
            Expanded(child: Text('${map.length} ${L(app, 'in use', 'भरे')} · ${free.length} ${L(app, 'free', 'खाली')}', style: heading(16, weight: FontWeight.w700))),
            if (app.isOwner)
              TextButton(
                  onPressed: () => sheet(context, L(app, 'How many racks / hangers?', 'कितने रैक / हैंगर?'), (sc) {
                        final ctrl = TextEditingController(text: '${d.rackCount}');
                        return Column(children: [
                          TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Total racks', 'कुल रैक'), icon: Icons.view_module_outlined)),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () {
                              d.rackCount = (int.tryParse(ctrl.text.trim()) ?? d.rackCount).clamp(1, 500);
                              d.changed();
                              Navigator.pop(sc);
                            },
                            child: Text(L(app, 'Save', 'सेव')),
                          ),
                        ]);
                      }),
                  child: Text(L(app, 'Change', 'बदलें'))),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 1; i <= d.rackCount; i++)
            InkWell(
              onTap: map[i] == null
                  ? null
                  : () => sheet(context, '${L(app, 'Rack', 'रैक')} $i', (sc) => Column(children: [
                        for (final o in map[i]!)
                          ListTile(
                            title: Text('${o.code} · ${d.customer(o.customerId)?.name ?? ''}'),
                            subtitle: Text('${o.pieces} ${L(app, 'pcs', 'पीस')} · ${o.rack}'),
                            onTap: () {
                              Navigator.pop(sc);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id)));
                            },
                          ),
                      ])),
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: map[i] == null ? const Color(0xFFDCF5E8) : const Color(0xFFFFE4D6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: map[i] == null ? LD.success : const Color(0xFFE8742A)),
                ),
                child: Text('$i', style: TextStyle(fontWeight: FontWeight.w800, color: map[i] == null ? const Color(0xFF146C43) : const Color(0xFFA8430F))),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Text(L(app, 'Green = free, orange = clothes kept. Rack names ending in a number (like A-4 or 4) are counted.', 'हरा = खाली, नारंगी = कपड़े रखे हैं। जिन रैक नामों के आख़िर में नंबर है (जैसे A-4 या 4) वही गिने जाते हैं।'),
            style: const TextStyle(color: LD.slate, fontSize: 12)),
      ]),
    );
  }
}

// ======================= order notes =======================

class OrderChatCard extends StatelessWidget {
  const OrderChatCard({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final o = d.orders.where((x) => x.id == orderId).firstOrNull;
    if (o == null || app.role == Role.delivery) return const SizedBox.shrink();
    final c = d.customer(o.customerId);
    final ctrl = TextEditingController();
    return SectionCard(
      title: L(app, 'Messages with customer', 'ग्राहक से बातचीत'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final m in o.chat)
          Align(
            alignment: m['from'] == 'shop' ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(color: m['from'] == 'shop' ? const Color(0xFFDCF8C6) : const Color(0xFFF1F4F8), borderRadius: BorderRadius.circular(12)),
              child: Text('${m['text']}'),
            ),
          ),
        Row(children: [
          Expanded(child: TextField(controller: ctrl, decoration: fieldDeco(L(app, 'Message / what customer said', 'संदेश / ग्राहक ने क्या कहा'), icon: Icons.chat_bubble_outline))),
          IconButton(
            tooltip: L(app, 'Save as customer said', 'ग्राहक ने कहा - सेव'),
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              d.addChat(o, from: 'customer', text: ctrl.text, by: app.actorId);
              ctrl.clear();
            },
          ),
          IconButton(
            tooltip: L(app, 'Send on WhatsApp', 'WhatsApp पर भेजें'),
            icon: const Icon(Icons.send_rounded, color: LD.success),
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) return;
              d.addChat(o, from: 'shop', text: t, by: app.actorId);
              if ((c?.phone ?? '').isNotEmpty) openWhatsApp(c!.phone, '${o.code}: $t');
              ctrl.clear();
            },
          ),
        ]),
      ]),
    );
  }
}
