import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../logic/messages.dart';
import '../services/export_service.dart';
import 'issue_screens.dart';
import 'v03_screens.dart';
import '../services/thermal_printer.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'live_map_screen.dart';
import 'v08_screens.dart';
import 'new_order_screen.dart';
import 'v09_screens.dart';

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final o = d.order(orderId);
    if (o == null) return Scaffold(appBar: AppBar());
    final cur = app.shop!.currency;
    final c = d.customer(o.customerId);
    final next = nextStatus(o.status, homeDelivery: o.homeDelivery);
    final canMove = next != null &&
        (app.canManage ||
            app.role == Role.counter ||
            (app.role == Role.washer && (o.status == 'received' || o.status == 'washing')) ||
            (app.role == Role.delivery && (o.status == 'pickup' || o.status == 'out')));
    final deliveryOn = app.module('delivery');
    final waOn = app.module('whatsapp');

    Widget row(String a, String b, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(color: color ?? LD.slate, fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? LD.navy, fontSize: bold ? 16 : 14)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(o.code),
        actions: [
          IconButton(
            tooltip: t('printBill'),
            icon: const Icon(Icons.print_outlined),
            onPressed: () async => ExportService.printPdf(await ExportService.billPdf(shop: app.shop!, data: d, o: o), 'Bill ${o.code}'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => EditOrderScreen(orderId: o.id)));
              } else if (v == 'bt' || v == 'bttags') {
                final p = ThermalPrinter.instance;
                await p.load();
                final err = await p.send(v == 'bt' ? p.billBytes(shop: app.shop!, d: d, o: o) : p.tagBytes(d: d, o: o));
                if (context.mounted) toast(context, err ?? L(app, 'Printed', 'प्रिंट हो गया'));
              } else if (v == 'upi') {
                upiSheet(context, o);
              } else if (v == 'refund') {
                refundSheet(context, o, d.overpaid(o) > 0 ? d.overpaid(o) : 0);
              } else if (v == 'share') {
                ExportService.sharePdf(await ExportService.billPdf(shop: app.shop!, data: d, o: o, roll: false), 'bill-${o.code}.pdf');
              } else if (v == 'a5') {
                ExportService.printPdf(await ExportService.billPdf(shop: app.shop!, data: d, o: o, roll: false), 'Bill ${o.code}');
              } else if (v == 'tags') {
                ExportService.printPdf(await ExportService.tagsPdf(shop: app.shop!, data: d, o: o), 'Tags ${o.code}');
              } else if (v == 'repeat' && context.mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => NewOrderScreen(repeatOf: o.id)));
              } else if (v == 'move' && context.mounted) {
                sheet(context, L(app, 'Move order to branch', 'ऑर्डर दूसरी ब्रांच में भेजें'), (c) => Column(children: [
                      for (final b in d.branches.where((b) => b.id != o.branchId))
                        ListTile(
                          leading: const Icon(Icons.store_mall_directory_outlined),
                          title: Text(b.name),
                          subtitle: b.address.isEmpty ? null : Text(b.address),
                          onTap: () {
                            final from = d.branch(o.branchId)?.name ?? '';
                            o.branchId = b.id;
                            o.history.add(StatusEvent(status: 'moved', at: DateTime.now(), by: app.actorId, note: '$from → ${b.name}'));
                            d.log(app.actorId, 'order.move', orderId: o.id, text: '${o.code} $from → ${b.name}');
                            d.changed();
                            Navigator.pop(c);
                            toast(context, '${o.code} → ${b.name}');
                          },
                        ),
                    ]));
              } else if (v == 'cancel' && context.mounted &&
                  await confirm(context, t('cancelOrder'), t('cancelSure'), ok: t('cancelOrder'), danger: true)) {
                d.setStatus(o, 'cancelled', by: app.actorId);
              }
            },
            itemBuilder: (_) => [
              if (o.status != 'cancelled' && app.can('editOrder') && (app.canManage || (app.role == Role.counter && (o.status == 'received' || o.status == 'pickup'))))
                PopupMenuItem(value: 'edit', child: Text(L(app, 'Edit order', 'ऑर्डर बदलें'))),
              PopupMenuItem(value: 'bt', child: Text(L(app, 'Print on Bluetooth printer', 'ब्लूटूथ प्रिंटर पर प्रिंट'))),
              if (app.module('barcode')) PopupMenuItem(value: 'bttags', child: Text(L(app, 'Print tags on Bluetooth printer', 'ब्लूटूथ प्रिंटर पर टैग'))),
              if (o.due > 0) PopupMenuItem(value: 'upi', child: Text(L(app, 'Show UPI QR', 'UPI QR दिखाएँ'))),
              if ((app.canManage || app.role == Role.counter) && app.can('refund') && o.paid > 0) PopupMenuItem(value: 'refund', child: Text(L(app, 'Refund', 'रिफ़ंड'))),
              PopupMenuItem(value: 'share', child: Text(t('shareBillPdf'))),
              PopupMenuItem(value: 'a5', child: Text(t('printA5'))),
              if (app.module('barcode')) PopupMenuItem(value: 'tags', child: Text(t('printTags'))),
              if (app.role != Role.washer && app.role != Role.delivery)
                PopupMenuItem(value: 'repeat', child: Text(L(app, 'Repeat this order', 'यही ऑर्डर फिर से'))),
              if (app.canManage && o.open && d.branches.length > 1)
                PopupMenuItem(value: 'move', child: Text(L(app, 'Move to another branch', 'दूसरी ब्रांच में भेजें'))),
              if ((app.canManage || app.role == Role.counter) && app.can('cancel') && o.open) PopupMenuItem(value: 'cancel', child: Text(t('cancelOrder'))),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
        // customer
        SectionCard(
          child: Row(children: [
            Avatar(initialsOf(c?.name ?? '?'), color: avatarColor(o.customerId), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c?.name ?? '—', style: heading(16, weight: FontWeight.w700)),
                Text('+${c?.phone ?? ''}', style: const TextStyle(color: LD.slate)),
                if ((c?.address ?? '').isNotEmpty)
                  Text(c!.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: LD.slate, fontSize: 12)),
              ]),
            ),
            StatusChip(o.status),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _ActionBtn(icon: Icons.call_outlined, label: t('call'), onTap: () => callPhone(c?.phone ?? ''))),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionBtn(
              icon: Icons.chat_outlined,
              label: t('sendUpdate'),
              onTap: waOn
                  ? () => openWhatsApp(c?.phone ?? '',
                      Messages.statusUpdate(o, shopName: app.shop!.shopName, customerName: c?.name ?? '', currency: cur))
                  : () => toast(context, t('moduleOff')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionBtn(
              icon: Icons.receipt_outlined,
              label: t('sendBill'),
              onTap: () => openWhatsApp(c?.phone ?? '', Messages.bill(o, shopName: app.shop!.shopName, customerName: c?.name ?? '', currency: cur)),
            ),
          ),
          if (c != null && (c.address.isNotEmpty || c.hasLocation)) ...[
            const SizedBox(width: 8),
            Expanded(child: _ActionBtn(icon: Icons.map_outlined, label: t('map'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveMapScreen(customerId: c.id, orderId: o.id))))),
          ],
        ]),
        for (final iss in d.issuesOf(o.id)) ...[
          const SizedBox(height: 10),
          IssueTile(issue: iss),
        ],
        const SizedBox(height: 12),
        // items
        SectionCard(
          title: '${o.pieces} ${t('pcs')} · ${o.lines.length} ${t('items')}',
          action: TextButton.icon(
            onPressed: () => _tags(context, o, t),
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: Text(t('tags')),
          ),
          child: Column(children: [
            for (final l in o.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${hiName(app, l.garment)} ${qtyText(l.qty, l.unit)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${hiName(app, l.service)} · ${money(l.rate, cur)}/${l.unit}', style: const TextStyle(fontSize: 12, color: LD.slate)),
                      if (l.note.isNotEmpty)
                        Text('⚠ ${l.note}', style: const TextStyle(fontSize: 12, color: Color(0xFFA8430F))),
                    ]),
                  ),
                  Text(money(l.amount, cur), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            const Divider(color: LD.line),
            row(t('subtotal'), money(o.subtotal, cur)),
            if (o.express) row('${t('express')} +${o.expressPct.toStringAsFixed(0)}%', money(o.expressCharge, cur)),
            if (o.discount > 0) row(t('discount'), '-${money(o.discount, cur)}'),
            if (o.couponAmount > 0) row('${L(app, 'Coupon', 'कूपन')} ${o.couponCode}', '-${money(o.couponAmount, cur)}'),
            if (o.pointsUsed > 0) row(L(app, 'Loyalty points', 'लॉयल्टी पॉइंट'), '-${money(o.pointsUsed, cur)}'),
            if (o.packageValue > 0) row('${L(app, 'Package', 'पैकेज')} · ${o.packageNote}', '-${money(o.packageValue, cur)}'),
            if (o.tax > 0) row('${t('tax')} ${o.taxPct.toStringAsFixed(0)}%', money(o.tax, cur)),
            row(t('total'), money(o.total, cur), bold: true),
            row(t('paid'), money(o.paid, cur), color: const Color(0xFF146C43)),
            if (o.due > 0 && o.status != 'cancelled') row(t('balance'), money(o.due, cur), bold: true, color: const Color(0xFF8A5A00)),
          ]),
        ),
        const SizedBox(height: 12),
        OrderWorkCard(orderId: o.id),
        const SizedBox(height: 12),
        OrderRatingCard(orderId: o.id),
        if (o.status == 'delivered') const SizedBox(height: 12),
        OrderPhotosCard(orderId: o.id),
        const SizedBox(height: 12),
        // details
        SectionCard(
          child: Column(children: [
            _kv(Icons.schedule_rounded, t('dueBy'), whenText(o.dueAt)),
            if (o.slot.isNotEmpty) _kv(Icons.access_time, L(app, 'Pickup slot', 'पिकअप का समय'), o.slot),
            _kv(o.homeDelivery ? Icons.delivery_dining_outlined : Icons.storefront_outlined, t('delivery'),
                o.homeDelivery ? t('homeDelivery') : t('atStore')),
            if (d.branches.length > 1) _kv(Icons.store_mall_directory_outlined, t('branch'), d.branch(o.branchId)?.name ?? ''),
            _kv(Icons.view_module_outlined, t('rack'), o.rack.isEmpty ? '—' : o.rack, onTap: () => _rack(context, o, t)),
            if (o.homeDelivery && deliveryOn) ...[
              if (o.status == 'pickup')
                _kv(Icons.directions_bike_outlined, t('pickupBy'), o.pickupAgent.isEmpty ? t('notAssigned') : d.nameOf(o.pickupAgent),
                    onTap: app.canManage || app.role == Role.counter ? () => _assign(context, o, pickup: true) : null),
              _kv(Icons.delivery_dining_outlined, t('deliveryBy'), o.deliveryAgent.isEmpty ? t('notAssigned') : d.nameOf(o.deliveryAgent),
                  onTap: app.canManage || app.role == Role.counter ? () => _assign(context, o, pickup: false) : null),
            ],
            if (o.proof != null)
              _kv(Icons.verified_outlined, t('proof'), '${whenText(o.proof!.at)} · ${t('map')}', onTap: () => openUrl(o.proof!.mapUrl)),
            if (o.notes.isNotEmpty) _kv(Icons.sticky_note_2_outlined, t('notes'), o.notes),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: t('timeline'),
          child: Column(children: [
            for (final e in o.history.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  StatusChip(e.status, small: true),
                  const SizedBox(width: 10),
                  Expanded(child: Text(d.nameOf(e.by), style: const TextStyle(fontSize: 13))),
                  Text(whenText(e.at), style: const TextStyle(fontSize: 12, color: LD.slate)),
                ]),
              ),
          ]),
        ),
        if (o.payments.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: t('payments'),
            child: Column(children: [
              for (final p in o.payments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Icon(p.mode == 'cash' ? Icons.payments_outlined : (p.mode == 'upi' ? Icons.qr_code_2_rounded : Icons.credit_card),
                        size: 18, color: LD.slate),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${t(p.mode)} · ${d.nameOf(p.by)}', style: const TextStyle(fontSize: 13))),
                    Text(whenText(p.at), style: const TextStyle(fontSize: 12, color: LD.slate)),
                    const SizedBox(width: 10),
                    Text(money(p.amount, cur), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ),
        ],
      ]),
      bottomNavigationBar: o.status == 'cancelled'
          ? null
          : o.status == 'delivered'
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Row(children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE8742A), minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ComplaintScreen(orderId: o.id))),
                          child: Text(L(app, 'Complaint / re-wash', 'शिकायत / दोबारा धुलाई'), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB42318),
                            side: const BorderSide(color: Color(0xFFB42318), width: 1.5),
                            minimumSize: const Size.fromHeight(52),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WrongDeliveryScreen(orderId: o.id))),
                          child: Text(L(app, 'Wrong delivery', 'गलत डिलीवरी'), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ]),
                  ),
                )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(children: [
                  if (o.due > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                        onPressed: () => payDialog(context, o),
                        icon: const Icon(Icons.currency_rupee_rounded, size: 18),
                        label: Text(t('recordPayment')),
                      ),
                    ),
                  if (o.due > 0 && canMove) const SizedBox(width: 10),
                  if (canMove)
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: LD.navy, minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                        onPressed: () async {
                          if (next == 'delivered' && o.due > 0) {
                            final paid = await payDialog(context, o);
                            if (paid == null) return;
                          }
                          if (!context.mounted) return;
                          await changeStatusFlow(context, app, o, next!);
                        },
                        child: Text(t('nextStep').replaceAll('{s}', t(next ?? '')), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ]),
              ),
            ),
    );
  }

  Widget _kv(IconData icon, String k, String v, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(icon, size: 19, color: LD.slate),
            const SizedBox(width: 10),
            Text(k, style: const TextStyle(color: LD.slate)),
            const SizedBox(width: 10),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, color: LD.slate),
          ]),
        ),
      );

  void _tags(BuildContext context, LaundryOrder o, String Function(String) t) {
    sheet(context, t('tags'), (c) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('tagsSub'), style: const TextStyle(color: LD.slate)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final tag in o.tags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: LD.navy, width: 1.5)),
              child: Text(tag, style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace')),
            ),
        ]),
      ]);
    });
  }

  void _rack(BuildContext context, LaundryOrder o, String Function(String) t) {
    final ctrl = TextEditingController(text: o.rack);
    final d = context.read<AppState>().data!;
    sheet(context, t('setRack'), (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: ctrl, autofocus: true, decoration: fieldDeco(t('rack'), icon: Icons.view_module_outlined)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              o.rack = ctrl.text.trim();
              d.changed();
              Navigator.pop(c);
            },
            child: Text(t('save')),
          ),
        ]));
  }

  void _assign(BuildContext context, LaundryOrder o, {required bool pickup}) {
    final app = context.read<AppState>();
    final d = app.data!;
    final t = app.t;
    final agents = d.agentsFor(o.branchId);
    sheet(context, t('assignAgent'), (c) => Column(children: [
          if (agents.isEmpty) Text(t('noStaff'), style: const TextStyle(color: LD.slate)),
          for (final s in agents)
            ListTile(
              leading: Avatar(s.initials, color: avatarColor(s.id)),
              title: Text(s.name),
              subtitle: Text(d.branch(s.branchId)?.name ?? ''),
              trailing: (pickup ? o.pickupAgent : o.deliveryAgent) == s.id ? const Icon(Icons.check_circle, color: LD.success) : null,
              onTap: () {
                pickup ? d.assign(o, pickupAgent: s.id, by: app.actorId) : d.assign(o, deliveryAgent: s.id, by: app.actorId);
                Navigator.pop(c);
              },
            ),
        ]));
  }
}

/// Record a payment. Returns the amount, or null if closed.
Future<double?> payDialog(BuildContext context, LaundryOrder o) {
  final app = context.read<AppState>();
  final t = app.t;
  final ctrl = TextEditingController(text: o.due.toStringAsFixed(0));
  var mode = 'cash';
  return sheet<double>(context, t('recordPayment'), (c) {
    return StatefulBuilder(builder: (c, set) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldDeco(t('amount'), icon: Icons.currency_rupee_rounded),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final m in payModes) Pill(label: t(m), on: mode == m, onTap: () => set(() => mode = m)),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: LD.navy, minimumSize: const Size.fromHeight(50)),
          onPressed: () {
            final a = double.tryParse(ctrl.text.trim()) ?? 0;
            if (a > 0) app.data!.addPayment(o, a, mode, by: app.actorId);
            Navigator.pop(c, a);
          },
          child: Text(t('save')),
        ),
      ]);
    });
  });
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: LD.primary),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
