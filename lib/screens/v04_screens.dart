import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../services/tracking_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'order_detail_screen.dart';

// ---------------- offers: loyalty, coupons, packages ----------------

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final admin = app.isOwner;
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Offers & loyalty', 'ऑफ़र और लॉयल्टी'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: LD.navy, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L(app, 'Loyalty points', 'लॉयल्टी पॉइंट'), style: const TextStyle(color: Color(0xFFC9D6EA), fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              d.pointsPer100 <= 0
                  ? L(app, 'Off', 'बंद')
                  : '${d.pointsPer100.toStringAsFixed(0)} ${L(app, 'point per', 'पॉइंट हर')} ${money(100, cur)} · 1 ${L(app, 'point', 'पॉइंट')} = ${money(d.pointValue, cur)}',
              style: heading(16, color: Colors.white),
            ),
            Text('${L(app, 'Can use from', 'इस्तेमाल')} ${d.minRedeem.toStringAsFixed(0)} ${L(app, 'points', 'पॉइंट से')}', style: const TextStyle(color: Color(0xFFC9D6EA), fontSize: 12)),
            if (admin)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _loyalty(context, app),
                  child: Text(app.t('edit'), style: const TextStyle(color: LD.sun)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Coupons', 'कूपन'),
          action: admin ? TextButton(onPressed: () => _coupon(context, app), child: Text(L(app, '+ New', '+ नया'))) : null,
          child: Column(children: [
            if (d.coupons.isEmpty) Text(L(app, 'No coupons yet.', 'अभी कोई कूपन नहीं।'), style: const TextStyle(color: LD.slate)),
            for (final c in d.coupons)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: c.valid ? LD.primary : LD.slate, width: 1.5), borderRadius: BorderRadius.circular(8)),
                  child: Text(c.code, style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, color: c.valid ? LD.primary : LD.slate)),
                ),
                title: Text(c.kind == 'pct' ? '${c.value.toStringAsFixed(0)}% off' : '${money(c.value, cur)} off'),
                subtitle: Text([
                  if (c.minOrder > 0) '${L(app, 'Min', 'कम से कम')} ${money(c.minOrder, cur)}',
                  if (c.validTill != null) '${L(app, 'till', 'तक')} ${dmy(c.validTill!)}',
                  if (c.onlyNew) L(app, 'new customers', 'नए ग्राहक'),
                  '${d.couponUses(c.code)} ${L(app, 'used', 'बार')}',
                ].join(' · ')),
                trailing: admin
                    ? Switch(
                        value: c.active,
                        onChanged: (v) {
                          c.active = v;
                          d.changed();
                        },
                      )
                    : null,
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Monthly packages', 'मासिक पैकेज'),
          action: admin ? TextButton(onPressed: () => _package(context, app), child: Text(L(app, '+ New', '+ नया'))) : null,
          child: Column(children: [
            if (d.packagePlans.isEmpty) Text(L(app, 'No packages yet.', 'अभी कोई पैकेज नहीं।'), style: const TextStyle(color: LD.slate)),
            for (final p in d.packagePlans)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${hiName(app, p.service)} ${p.credits.toStringAsFixed(0)} ${p.unit} · ${p.days} ${L(app, 'days', 'दिन')} · ${d.customers.where((c) => c.packages.any((x) => x.name == p.name && x.remaining > 0 && x.end.isAfter(DateTime.now()))).length} ${L(app, 'active', 'चालू')}'),
                trailing: Text(money(p.price, cur), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            Text(L(app, 'Sell a package from the customer\'s page.', 'पैकेज ग्राहक के पेज से बेचें।'), style: const TextStyle(fontSize: 12, color: LD.slate)),
          ]),
        ),
      ]),
    );
  }

  void _loyalty(BuildContext context, AppState app) {
    final d = app.data!;
    final a = TextEditingController(text: d.pointsPer100.toStringAsFixed(0));
    final b = TextEditingController(text: d.pointValue.toString());
    final c = TextEditingController(text: d.minRedeem.toStringAsFixed(0));
    sheet(context, L(app, 'Loyalty points', 'लॉयल्टी पॉइंट'), (sc) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: a, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Points per ₹100 (0 = off)', 'हर ₹100 पर पॉइंट (0 = बंद)'))),
          const SizedBox(height: 10),
          TextField(controller: b, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDeco(L(app, 'Value of 1 point (₹)', '1 पॉइंट की कीमत (₹)'))),
          const SizedBox(height: 10),
          TextField(controller: c, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Minimum points to use', 'कम से कम कितने पॉइंट पर'))),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              d
                ..pointsPer100 = double.tryParse(a.text) ?? d.pointsPer100
                ..pointValue = double.tryParse(b.text) ?? d.pointValue
                ..minRedeem = double.tryParse(c.text) ?? d.minRedeem;
              d.changed();
              Navigator.pop(sc);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }

  void _coupon(BuildContext context, AppState app) {
    final d = app.data!;
    final code = TextEditingController();
    final val = TextEditingController();
    final min = TextEditingController();
    var kind = 'pct';
    var onlyNew = false;
    DateTime? till;
    sheet(context, L(app, 'New coupon', 'नया कूपन'), (sc) => StatefulBuilder(builder: (sc, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: fieldDeco(L(app, 'Code (e.g. DIWALI10)', 'कोड (जैसे DIWALI10)'))),
            const SizedBox(height: 10),
            Row(children: [
              Pill(label: '% off', on: kind == 'pct', onTap: () => set(() => kind = 'pct')),
              const SizedBox(width: 8),
              Pill(label: '₹ off', on: kind == 'flat', onTap: () => set(() => kind = 'flat')),
            ]),
            const SizedBox(height: 10),
            TextField(controller: val, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Value', 'कितना'))),
            const SizedBox(height: 10),
            TextField(controller: min, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Minimum order (optional)', 'कम से कम ऑर्डर (ज़रूरी नहीं)'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(L(app, 'Only for new customers', 'सिर्फ़ नए ग्राहकों के लिए')), value: onlyNew, onChanged: (v) => set(() => onlyNew = v)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L(app, 'Valid till', 'कब तक')),
              trailing: Text(till == null ? L(app, 'Always', 'हमेशा') : dmy(till!)),
              onTap: () async {
                final p = await showDatePicker(context: sc, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (p != null) set(() => till = DateTime(p.year, p.month, p.day, 23, 59));
              },
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(val.text) ?? 0;
                if (code.text.trim().length < 3 || v <= 0 || d.couponByCode(code.text) != null) return;
                d.coupons.add(Coupon(
                  id: d.newId('cp'),
                  code: code.text.trim().toUpperCase(),
                  kind: kind,
                  value: v,
                  minOrder: double.tryParse(min.text) ?? 0,
                  validTill: till,
                  onlyNew: onlyNew,
                ));
                d.changed();
                Navigator.pop(sc);
              },
              child: Text(app.t('save')),
            ),
          ]);
        }));
  }

  void _package(BuildContext context, AppState app) {
    final d = app.data!;
    final name = TextEditingController();
    final credits = TextEditingController();
    final price = TextEditingController();
    final days = TextEditingController(text: '30');
    var service = app.shop!.services.first;
    var unit = 'kg';
    sheet(context, L(app, 'New package', 'नया पैकेज'), (sc) => StatefulBuilder(builder: (sc, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, decoration: fieldDeco(L(app, 'Name (e.g. Family 30 kg)', 'नाम (जैसे Family 30 kg)'))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in app.shop!.services) Pill(label: hiName(app, s), on: service == s, onTap: () => set(() => service = s)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Pill(label: 'kg', on: unit == 'kg', onTap: () => set(() => unit = 'kg')),
              const SizedBox(width: 8),
              Pill(label: L(app, 'pieces', 'पीस'), on: unit == 'pc', onTap: () => set(() => unit = 'pc')),
            ]),
            const SizedBox(height: 10),
            TextField(controller: credits, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'How many (kg / pieces)', 'कितने (किलो / पीस)'))),
            const SizedBox(height: 10),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: fieldDeco(app.t('price'))),
            const SizedBox(height: 10),
            TextField(controller: days, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Valid for (days)', 'कितने दिन'))),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                final cr = double.tryParse(credits.text) ?? 0;
                final pr = double.tryParse(price.text) ?? 0;
                if (name.text.trim().length < 2 || cr <= 0 || pr <= 0) return;
                d.packagePlans.add(PackagePlan(
                  id: d.newId('pk'),
                  name: name.text.trim(),
                  service: service,
                  unit: unit,
                  credits: cr,
                  price: pr,
                  days: int.tryParse(days.text) ?? 30,
                ));
                d.changed();
                Navigator.pop(sc);
              },
              child: Text(app.t('save')),
            ),
          ]);
        }));
  }
}

/// Customer page card: points, packages, sell package, save location.
class CustomerExtrasCard extends StatelessWidget {
  const CustomerExtrasCard({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final c = d.customer(customerId);
    if (c == null) return const SizedBox.shrink();
    final cur = app.shop!.currency;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.stars_rounded, color: Color(0xFF8A5A00)),
          const SizedBox(width: 8),
          Expanded(child: Text('${c.points.toStringAsFixed(0)} ${L(app, 'loyalty points', 'लॉयल्टी पॉइंट')} = ${money(c.points * d.pointValue, cur)}')),
        ]),
        for (final p in c.packages.where((p) => p.end.isAfter(DateTime.now())))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.inventory_2_outlined, color: LD.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('${p.name}: ${p.remaining.toStringAsFixed(1)}/${p.credits.toStringAsFixed(0)} ${p.unit} · ${L(app, 'till', 'तक')} ${dmy(p.end)}')),
            ]),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (d.packagePlans.isNotEmpty && app.role != Role.washer && app.role != Role.delivery)
            OutlinedButton.icon(
              onPressed: () => _sell(context, app, c),
              icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
              label: Text(L(app, 'Sell package', 'पैकेज बेचें')),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              final p = await TrackingService.instance.current();
              if (p == null) {
                if (context.mounted) toast(context, app.t('trackingOff'));
                return;
              }
              d.setCustomerLocation(c.id, p.lat, p.lng);
              if (context.mounted) toast(context, L(app, 'Location saved for this customer.', 'इस ग्राहक की लोकेशन सेव हो गई।'));
            },
            icon: Icon(c.hasLocation ? Icons.where_to_vote_outlined : Icons.add_location_alt_outlined, size: 18),
            label: Text(c.hasLocation ? L(app, 'Update location', 'लोकेशन बदलें') : L(app, 'Save location here', 'यहाँ की लोकेशन सेव करें')),
          ),
        ]),
      ]),
    );
  }

  void _sell(BuildContext context, AppState app, Customer c) {
    final d = app.data!;
    var mode = 'cash';
    sheet(context, L(app, 'Sell package', 'पैकेज बेचें'), (sc) => StatefulBuilder(builder: (sc, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, children: [for (final m in payModes) Pill(label: app.t(m), on: mode == m, onTap: () => set(() => mode = m))]),
            const SizedBox(height: 8),
            for (final p in d.packagePlans)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                subtitle: Text('${hiName(app, p.service)} ${p.credits.toStringAsFixed(0)} ${p.unit} · ${p.days} ${L(app, 'days', 'दिन')}'),
                trailing: Text(money(p.price, app.shop!.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
                onTap: () {
                  final o = d.sellPackage(c, p, by: app.actorId, branchId: app.scopeBranch ?? d.branches.first.id, mode: mode);
                  Navigator.pop(sc);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id)));
                },
              ),
          ]);
        }));
  }
}

// ---------------- stock & suppliers ----------------

class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final low = d.lowStock;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L(app, 'Stock', 'स्टॉक')),
          bottom: TabBar(tabs: [Tab(text: L(app, 'Items', 'सामान')), Tab(text: L(app, 'Suppliers', 'सप्लायर'))]),
        ),
        floatingActionButton: app.isOwner
            ? Builder(
                builder: (ctx) => FloatingActionButton.extended(
                  onPressed: () => DefaultTabController.of(ctx).index == 0 ? _addItem(ctx, app) : _addSupplier(ctx, app),
                  icon: const Icon(Icons.add),
                  label: Text(L(app, 'Add', 'जोड़ें')),
                ),
              )
            : null,
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
            if (low.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(12)),
                child: Text('${L(app, 'Running low', 'खत्म होने वाले')}: ${low.map((s) => s.name).join(', ')}',
                    style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w700)),
              ),
            if (d.stock.isEmpty) EmptyState(icon: Icons.inventory_2_outlined, text: L(app, 'Add detergent, solvent, hangers, covers…', 'डिटर्जेंट, सॉल्वेंट, हैंगर, कवर… जोड़ें')),
            for (final it in d.stock)
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
                child: ListTile(
                  title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: it.minQty <= 0 ? 1 : (it.qty / (it.minQty * 3)).clamp(0, 1).toDouble(),
                          minHeight: 6,
                          color: it.low ? const Color(0xFFB42318) : LD.success,
                          backgroundColor: const Color(0xFFEDF0F4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${L(app, 'Min', 'कम से कम')} ${it.minQty.toStringAsFixed(0)} ${it.unit}'),
                    ]),
                  ),
                  trailing: Text('${it.qty.toStringAsFixed(it.qty == it.qty.roundToDouble() ? 0 : 1)} ${it.unit}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: it.low ? const Color(0xFFB42318) : LD.navy)),
                  onTap: app.canManage ? () => _move(context, app, it) : null,
                ),
              ),
          ]),
          ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
            if (d.suppliers.isEmpty) EmptyState(icon: Icons.local_shipping_outlined, text: L(app, 'No suppliers yet.', 'अभी कोई सप्लायर नहीं।')),
            for (final s in d.suppliers)
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
                child: ListTile(
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${s.items}\n+${s.phone}'),
                  isThreeLine: true,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: app.t('call'), onPressed: () => callPhone(s.phone), icon: const Icon(Icons.call_outlined)),
                    IconButton(tooltip: 'WhatsApp', onPressed: () => openWhatsApp(s.phone, 'Namaste, order from ${app.shop!.shopName}: '), icon: const Icon(Icons.chat_outlined)),
                  ]),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  void _addItem(BuildContext context, AppState app) {
    final name = TextEditingController();
    final unit = TextEditingController(text: 'pc');
    final qty = TextEditingController();
    final min = TextEditingController();
    sheet(context, L(app, 'Add stock item', 'स्टॉक आइटम जोड़ें'), (sc) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: name, decoration: fieldDeco(app.t('name'))),
          const SizedBox(height: 10),
          TextField(controller: unit, decoration: fieldDeco(L(app, 'Unit (L, kg, pc, roll)', 'यूनिट (L, kg, pc, roll)'))),
          const SizedBox(height: 10),
          TextField(controller: qty, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'In stock now', 'अभी कितना है'))),
          const SizedBox(height: 10),
          TextField(controller: min, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Alert below', 'इससे कम हो तो अलर्ट'))),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              if (name.text.trim().length < 2) return;
              app.data!.addStockItem(name.text, unit.text.trim().isEmpty ? 'pc' : unit.text.trim(),
                  qty: double.tryParse(qty.text) ?? 0, minQty: double.tryParse(min.text) ?? 0, branchId: app.scopeBranch ?? app.data!.branches.first.id);
              Navigator.pop(sc);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }

  void _addSupplier(BuildContext context, AppState app) {
    final name = TextEditingController();
    final phone = TextEditingController();
    final items = TextEditingController();
    sheet(context, L(app, 'Add supplier', 'सप्लायर जोड़ें'), (sc) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: name, decoration: fieldDeco(app.t('name'))),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: fieldDeco(app.t('phone'))),
          const SizedBox(height: 10),
          TextField(controller: items, decoration: fieldDeco(L(app, 'What they supply', 'क्या सप्लाई करते हैं'))),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              if (name.text.trim().length < 2) return;
              final d = app.data!;
              d.suppliers.add(Supplier(id: d.newId('su'), name: name.text.trim(), phone: phone.text.replaceAll(RegExp(r'[^0-9]'), ''), items: items.text.trim()));
              d.changed();
              Navigator.pop(sc);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }

  void _move(BuildContext context, AppState app, StockItem it) {
    final d = app.data!;
    final qty = TextEditingController();
    final cost = TextEditingController();
    var inMode = true;
    String sup = '';
    sheet(context, it.name, (sc) => StatefulBuilder(builder: (sc, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Pill(label: L(app, '+ Bought', '+ खरीदा'), on: inMode, onTap: () => set(() => inMode = true)),
              const SizedBox(width: 8),
              Pill(label: L(app, '− Used', '− इस्तेमाल'), on: !inMode, onTap: () => set(() => inMode = false)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDeco('${L(app, 'Quantity', 'मात्रा')} (${it.unit})')),
            if (inMode) ...[
              const SizedBox(height: 10),
              TextField(controller: cost, keyboardType: TextInputType.number, decoration: fieldDeco(L(app, 'Cost (adds to expenses)', 'कीमत (खर्चे में जुड़ेगी)'), icon: Icons.currency_rupee)),
              if (d.suppliers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in d.suppliers) Pill(label: s.name, on: sup == s.id, onTap: () => set(() => sup = s.id)),
                  ]),
                ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                final q = double.tryParse(qty.text) ?? 0;
                if (q <= 0) return;
                d.moveStock(it, inMode ? q : -q, by: app.actorId, supplierId: sup, cost: inMode ? (double.tryParse(cost.text) ?? 0) : 0);
                Navigator.pop(sc);
              },
              child: Text(app.t('save')),
            ),
          ]);
        }));
  }
}

// ---------------- route & live map ----------------

/// Nearest-first order of stops starting from [from] (simple, good enough for a city round).
List<(LaundryOrder, Customer)> orderStops(LatLng? from, List<(LaundryOrder, Customer)> stops) {
  final left = [...stops];
  final out = <(LaundryOrder, Customer)>[];
  var cur = from;
  const dist = Distance();
  while (left.isNotEmpty) {
    if (cur == null) {
      out.add(left.removeAt(0));
      final c = out.last.$2;
      cur = c.hasLocation ? LatLng(c.lat!, c.lng!) : null;
      continue;
    }
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < left.length; i++) {
      final c = left[i].$2;
      if (!c.hasLocation) continue;
      final m = dist.as(LengthUnit.Meter, cur, LatLng(c.lat!, c.lng!));
      if (m < bestD) {
        bestD = m;
        best = i;
      }
    }
    out.add(left.removeAt(best));
    final c = out.last.$2;
    if (c.hasLocation) cur = LatLng(c.lat!, c.lng!);
  }
  return out;
}

class RouteMapScreen extends StatelessWidget {
  const RouteMapScreen({super.key, this.agentId});
  final String? agentId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final cur = app.shop!.currency;
    final agents = d.staff.where((s) => s.active && s.role == Role.delivery && (agentId == null || s.id == agentId)).toList();
    final stopsRaw = <(LaundryOrder, Customer)>[];
    for (final o in d.ordersIn(app.scopeBranch)) {
      final mine = agentId == null || o.deliveryAgent == agentId || o.pickupAgent == agentId || (o.status == 'pickup' && o.pickupAgent.isEmpty);
      final active = o.status == 'pickup' || (o.homeDelivery && (o.status == 'out' || o.status == 'ready'));
      final c = d.customer(o.customerId);
      if (mine && active && c != null) stopsRaw.add((o, c));
    }
    final me = agentId == null ? null : d.lastPing(agentId!);
    final stops = orderStops(me == null ? null : LatLng(me.lat, me.lng), stopsRaw);
    final points = <LatLng>[
      for (final a in agents)
        if (d.lastPing(a.id) != null) LatLng(d.lastPing(a.id)!.lat, d.lastPing(a.id)!.lng),
      for (final s in stops)
        if (s.$2.hasLocation) LatLng(s.$2.lat!, s.$2.lng!),
    ];
    final center = points.isEmpty ? const LatLng(19.076, 72.8777) : points.first;
    final routeLine = <LatLng>[
      if (me != null) LatLng(me.lat, me.lng),
      for (final s in stops)
        if (s.$2.hasLocation) LatLng(s.$2.lat!, s.$2.lng!),
    ];

    String mapsUrl() {
      final pts = [for (final s in stops) if (s.$2.hasLocation) '${s.$2.lat},${s.$2.lng}' else s.$2.address].where((x) => x.isNotEmpty).toList();
      if (pts.isEmpty) return 'https://www.google.com/maps';
      final dest = pts.last;
      final way = pts.length > 1 ? pts.sublist(0, math.min(pts.length - 1, 9)).join('|') : '';
      return 'https://www.google.com/maps/dir/?api=1${me == null ? '' : '&origin=${me.lat},${me.lng}'}&destination=${Uri.encodeComponent(dest)}'
          '${way.isEmpty ? '' : '&waypoints=${Uri.encodeComponent(way)}'}&travelmode=driving';
    }

    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Route & map', 'रूट और मैप'))),
      body: Column(children: [
        SizedBox(
          height: 330,
          child: FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 13),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.brotrix.laundry'),
              if (routeLine.length > 1) PolylineLayer(polylines: [Polyline(points: routeLine, strokeWidth: 4, color: LD.primary)]),
              MarkerLayer(markers: [
                for (var i = 0; i < stops.length; i++)
                  if (stops[i].$2.hasLocation)
                    Marker(
                      point: LatLng(stops[i].$2.lat!, stops[i].$2.lng!),
                      width: 30,
                      height: 30,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: stops[i].$1.status == 'pickup' ? const Color(0xFFE8742A) : LD.navy,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    ),
                for (final a in agents)
                  if (d.lastPing(a.id) != null)
                    Marker(
                      point: LatLng(d.lastPing(a.id)!.lat, d.lastPing(a.id)!.lng),
                      width: 110,
                      height: 44,
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                          child: Text('${a.name.split(' ').first} · ${hm(d.lastPing(a.id)!.at)}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                        ),
                        Container(width: 16, height: 16, decoration: BoxDecoration(color: LD.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                      ]),
                    ),
              ]),
              const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(children: [
            Expanded(child: Text('${stops.length} ${L(app, 'stops · nearest first', 'स्टॉप · पास वाला पहले')}', style: heading(15, weight: FontWeight.w700))),
            FilledButton.icon(onPressed: () => openUrl(mapsUrl()), icon: const Icon(Icons.navigation_outlined, size: 18), label: const Text('Google Maps')),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
            for (var i = 0; i < stops.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: stops[i].$1.status == 'pickup' ? const Color(0xFFE8742A) : LD.navy,
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                title: Text('${stops[i].$2.name} · ${stops[i].$1.code}'),
                subtitle: Text([
                  stops[i].$1.status == 'pickup' ? L(app, 'Pickup', 'पिकअप') : L(app, 'Deliver', 'डिलीवर'),
                  if (stops[i].$1.slot.isNotEmpty) stops[i].$1.slot,
                  if (stops[i].$1.due > 0 && stops[i].$1.status != 'pickup') '${L(app, 'collect', 'लेना')} ${money(stops[i].$1.due, cur)}',
                  if (!stops[i].$2.hasLocation) L(app, 'no map pin yet', 'मैप पिन नहीं'),
                ].join(' · ')),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: stops[i].$1.id))),
              ),
          ]),
        ),
      ]),
    );
  }
}
