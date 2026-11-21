import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../data/shop_v12.dart';
import '../data/shop_v13.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../data/shop_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'order_detail_screen.dart';
import '../services/thermal_printer.dart';

class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key, this.customerId, this.repeatOf});
  final String? customerId;
  final String? repeatOf; // copy clothes of this order (repeat order)

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  Customer? _customer;
  String? _service;
  String? _branchId;
  final List<OrderLine> _lines = [];
  bool _express = false;
  bool _home = false;
  bool _pickup = false;
  DateTime? _due;
  String _mode = 'cash';
  final _discount = TextEditingController();
  final _advance = TextEditingController();
  final _notes = TextEditingController();
  final _coupon = TextEditingController();
  bool _usePoints = false;
  bool _usePackage = true;
  String _slot = '';
  String _cat = 'All';

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    if (widget.customerId != null) _customer = app.data!.customer(widget.customerId!);
    final old = widget.repeatOf == null ? null : app.data!.order(widget.repeatOf!);
    if (old != null) {
      _customer = app.data!.customer(old.customerId);
      _branchId = old.branchId;
      _home = old.homeDelivery;
      for (final l in old.lines) {
        final c = l.copy();
        _lines.add(c);
      }
    }
  }

  @override
  void dispose() {
    _discount.dispose();
    _advance.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _customer = null;
      _lines.clear();
      _express = false;
      _home = false;
      _pickup = false;
      _due = null;
      _discount.clear();
      _advance.clear();
      _notes.clear();
      _coupon.clear();
      _usePoints = false;
      _slot = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final shop = app.shop!;
    final cur = shop.currency;
    final services = shop.services;
    _service ??= services.isNotEmpty ? services.first : null;
    final branches = app.isOwner ? d.branches : d.branches.where((b) => b.id == app.staffUser!.branchId).toList();
    _branchId ??= app.scopeBranch ?? (branches.isNotEmpty ? branches.first.id : null);
    final cats = ['All', ...{for (final g in d.garments) g.category}];
    final garments = d.garments.where((g) => d.rateFor(g.id, _service ?? '', _customer) != null && (_cat == 'All' || g.category == _cat)).toList();

    final subtotal = _lines.fold<double>(0, (s, l) => s + l.amount);
    final expressAmt = _express ? subtotal * d.expressPct / 100 : 0.0;
    final disc = double.tryParse(_discount.text.trim()) ?? 0;
    final couponAmt = _coupon.text.trim().isEmpty ? 0.0 : d.couponDiscount(_coupon.text, _customer, subtotal);
    final pkg = _packageUse(d);
    final pkgValue = _usePackage && pkg != null ? pkg.$3 : 0.0;
    final room = (subtotal + expressAmt - disc - couponAmt - pkgValue).clamp(0, double.infinity).toDouble();
    final pointsMoney = d.pointsMoney(_customer);
    final pointsAmt = _usePoints ? (pointsMoney < room ? pointsMoney : room) : 0.0;
    final taxable = (room - pointsAmt).clamp(0, double.infinity).toDouble();
    final tax = taxable * d.taxPct / 100;
    final total = (taxable + tax).roundToDouble();
    final due = _due ?? DateTime.now().add(Duration(days: _express ? 1 : d.dueDays));
    final pieces = _lines.fold<int>(0, (s, l) => s + l.pieces);

    return Scaffold(
      appBar: AppBar(title: Text(t('newOrder'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 140), children: [
        // customer
        SectionCard(
          title: t('customer'),
          child: _customer == null
              ? OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => _pickCustomer(context),
                  icon: const Icon(Icons.person_search_outlined),
                  label: Text(t('pickCustomer')),
                )
              : ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(initialsOf(_customer!.name), color: avatarColor(_customer!.id)),
                  title: Text(_customer!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '+${_customer!.phone}${(d.typeDiscount[_customer!.type] ?? 0) > 0 ? ' · ${t('type.${_customer!.type}')} −${d.typeDiscount[_customer!.type]!.toStringAsFixed(0)}%' : ''}${d.dueOf(_customer!.id) > 0 ? ' · ${t('due')} ${money(d.dueOf(_customer!.id), cur)}' : ''}',
                  ),
                  trailing: TextButton(onPressed: () => _pickCustomer(context), child: Text(t('edit'))),
                ),
        ),
        const SizedBox(height: 12),
        // service + garments
        SectionCard(
          title: t('service'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: services.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Pill(label: hiName(app, services[i]), on: _service == services[i], onTap: () => setState(() => _service = services[i])),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cats.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ChoiceChip(
                  label: Text(hiName(app, cats[i])),
                  selected: _cat == cats[i],
                  onSelected: (_) => setState(() => _cat = cats[i]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(t('addItems'), style: const TextStyle(fontSize: 12, color: LD.slate)),
            const SizedBox(height: 8),
            if (garments.isEmpty)
              Text(t('noRate'), style: const TextStyle(color: LD.slate))
            else
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.25,
                children: [
                  for (final g in garments)
                    _GarmentTile(
                      name: hiName(app, g.name),
                      price: '${money(d.rateFor(g.id, _service!, _customer)!, cur)}/${g.unit}',
                      count: _lines.where((l) => l.garment == g.name && l.service == _service).fold<double>(0, (s, l) => s + l.qty),
                      onTap: () => _add(g, d.rateFor(g.id, _service!, _customer)!),
                    ),
                ],
              ),
          ]),
        ),
        if (_lines.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: '$pieces ${t('pcs')}',
            child: Column(children: [
              for (final l in _lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _noteFor(l),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(hiName(app, l.garment), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${hiName(app, l.service)} · ${money(l.rate, cur)}', style: const TextStyle(fontSize: 12, color: LD.slate)),
                          Text(l.note.isEmpty && l.details.isEmpty ? '+ ${t('itemNote')}' : [if (l.details.isNotEmpty) l.details, if (l.note.isNotEmpty) '⚠ ${l.note}'].join(' · '),
                              style: TextStyle(fontSize: 11, color: l.note.isEmpty && l.details.isEmpty ? LD.primary : const Color(0xFFA8430F))),
                        ]),
                      ),
                    ),
                    IconButton(
                      tooltip: '-',
                      onPressed: () => setState(() {
                        l.qty -= l.unit == 'kg' ? .5 : 1;
                        if (l.qty <= 0) _lines.remove(l);
                      }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(qtyText(l.qty, l.unit), style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(
                      tooltip: '+',
                      onPressed: () => setState(() => l.qty += l.unit == 'kg' ? .5 : (l.unit == 'sqft' ? 5 : 1)),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    SizedBox(width: 64, child: Text(money(l.amount, cur), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Offers', 'ऑफ़र'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _coupon,
              textCapitalization: TextCapitalization.characters,
              decoration: fieldDeco(L(app, 'Coupon code', 'कूपन कोड'), icon: Icons.confirmation_number_outlined).copyWith(
                suffixText: _coupon.text.trim().isEmpty ? null : (couponAmt > 0 ? '−${money(couponAmt, cur)}' : L(app, 'not valid', 'मान्य नहीं')),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (pointsMoney > 0)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${L(app, 'Use loyalty points', 'लॉयल्टी पॉइंट इस्तेमाल करें')} (${_customer!.points.toStringAsFixed(0)})'),
                subtitle: Text('−${money(_usePoints ? pointsAmt : pointsMoney, cur)}'),
                value: _usePoints,
                onChanged: (v) => setState(() => _usePoints = v),
              ),
            if (pkg != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${L(app, 'Use package', 'पैकेज इस्तेमाल करें')}: ${pkg.$1.name}'),
                subtitle: Text('${pkg.$2.toStringAsFixed(1)} ${pkg.$1.unit} · −${money(pkg.$3, cur)} · ${L(app, 'left', 'बाकी')} ${pkg.$1.remaining.toStringAsFixed(1)}'),
                value: _usePackage,
                onChanged: (v) => setState(() => _usePackage = v),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: t('orderOptions'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (branches.length > 1)
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                decoration: fieldDeco(t('branch'), icon: Icons.store_mall_directory_outlined),
                items: [for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
                onChanged: (v) => setState(() => _branchId = v),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${t('express')} (+${d.expressPct.toStringAsFixed(0)}%)'),
              value: _express,
              onChanged: (v) => setState(() => _express = v),
            ),
            if (app.module('delivery')) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('bookPickup')),
                value: _pickup,
                onChanged: (v) => setState(() {
                  _pickup = v;
                  if (v) _home = true;
                }),
              ),
              if (_pickup)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final sl in const ['9–12', '12–3', '3–6', '6–9'])
                    Pill(
                      label: d.slotLimit > 0 ? '$sl (${d.slotBooked(sl)}/${d.slotLimit})' : sl,
                      on: _slot == sl,
                      onTap: () {
                        if (d.slotFull(sl) && !app.isOwner) {
                          toast(context, L(app, 'This slot is full. Pick another.', 'ये स्लॉट भरा है। दूसरा चुनें।'));
                          return;
                        }
                        setState(() => _slot = sl);
                      }),
                ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('homeDelivery')),
                value: _home,
                onChanged: (v) => setState(() => _home = v),
              ),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(t('dueBy')),
              trailing: Text(whenText(due), style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: due,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 60)),
                );
                if (p != null) setState(() => _due = DateTime(p.year, p.month, p.day, 18));
              },
            ),
            const SizedBox(height: 6),
            if (app.can('discount'))
              TextField(
                controller: _discount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDeco(t('discount'), icon: Icons.local_offer_outlined),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 10),
            TextField(controller: _notes, decoration: fieldDeco(t('notes'), icon: Icons.sticky_note_2_outlined)),
            const SizedBox(height: 10),
            TextField(
              controller: _advance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: fieldDeco(t('advance'), icon: Icons.currency_rupee_rounded),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [for (final m in payModes) Pill(label: t(m), on: _mode == m, onTap: () => setState(() => _mode = m))]),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: LD.line))),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('total'), style: const TextStyle(fontSize: 12, color: LD.slate)),
                Text(money(total, cur), style: heading(22)),
                if (tax > 0) Text('${t('tax')} ${money(tax, cur)}', style: const TextStyle(fontSize: 11, color: LD.slate)),
              ]),
            ),
            if (_lines.isNotEmpty)
              IconButton(
                tooltip: L(app, 'Share estimate (quote)', 'अनुमान (कोटेशन) भेजें'),
                icon: const Icon(Icons.request_quote_outlined, color: LD.primary),
                onPressed: () {
                  final text = d.estimateText(
                      shopName: app.shop!.shopName, currency: cur, lines: _lines, subtotal: subtotal, express: expressAmt, tax: tax, total: total, due: due);
                  if ((_customer?.phone ?? '').isNotEmpty) {
                    openWhatsApp(_customer!.phone, text);
                  } else {
                    Share.share(text);
                  }
                },
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: LD.navy, minimumSize: const Size(150, 52), shape: const StadiumBorder()),
              onPressed: () => _create(context),
              icon: const Icon(Icons.check_rounded),
              label: Text(t('createOrder')),
            ),
          ]),
        ),
      ),
    );
  }

  /// (package, qty covered, value) for the selected customer's active package.
  (CustPackage, double, double)? _packageUse(ShopData d) {
    final c = _customer;
    if (c == null) return null;
    for (final p in c.packages) {
      if (p.remaining <= 0 || p.end.isBefore(DateTime.now())) continue;
      final match = _lines.where((l) => l.service == p.service && l.unit == p.unit).toList();
      if (match.isEmpty) continue;
      final qty = match.fold<double>(0, (s, l) => s + l.qty);
      final covered = qty < p.remaining ? qty : p.remaining;
      final rate = match.first.rate;
      return (p, covered, (covered * rate).roundToDouble());
    }
    return null;
  }

  void _add(Garment g, double rate) {
    setState(() {
      final ex = _lines.where((l) => l.garment == g.name && l.service == _service);
      if (ex.isNotEmpty) {
        ex.first.qty += g.unit == 'kg' ? 1 : (g.unit == 'sqft' ? 10 : 1);
      } else {
        _lines.add(OrderLine(garment: g.name, service: _service!, qty: g.unit == 'sqft' ? 20 : 1, rate: rate, unit: g.unit));
      }
    });
  }

  void _noteFor(OrderLine l) {
    final t = context.read<AppState>().t;
    final ctrl = TextEditingController(text: l.note);
    final color = TextEditingController(text: l.color);
    final brand = TextEditingController(text: l.brand);
    final care = TextEditingController(text: l.care);
    final app = context.read<AppState>();
    sheet(context, l.garment, (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: TextField(controller: color, decoration: fieldDeco(L(app, 'Colour', 'रंग')))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: brand, decoration: fieldDeco(L(app, 'Brand', 'ब्रांड')))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final x in ['White', 'Black', 'Blue', 'Red', 'Cream'])
              ActionChip(label: Text(x), onPressed: () => color.text = x),
          ]),
          const SizedBox(height: 8),
          TextField(controller: care, decoration: fieldDeco(L(app, 'Special care', 'खास ध्यान'))),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final x in ['No dryer', 'Hand wash', 'Dry in shade', 'Low heat iron', 'Wash separately'])
              ActionChip(label: Text(x), onPressed: () => care.text = care.text.isEmpty ? x : '${care.text}, $x'),
          ]),
          const SizedBox(height: 10),
          TextField(controller: ctrl, decoration: fieldDeco(t('itemNote'))),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final s in ['Stain', 'Colour bleeds', 'Torn', 'Button missing', 'Delicate'])
              ActionChip(label: Text(s), onPressed: () => ctrl.text = ctrl.text.isEmpty ? s : '${ctrl.text}, $s'),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              setState(() {
                l.note = ctrl.text.trim();
                l.color = color.text.trim();
                l.brand = brand.text.trim();
                l.care = care.text.trim();
              });
              Navigator.pop(c);
            },
            child: Text(t('save')),
          ),
        ]));
  }

  Future<void> _pickCustomer(BuildContext context) async {
    final app = context.read<AppState>();
    final picked = await pickCustomer(context, app);
    if (picked != null) {
      setState(() {
        _customer = picked;
        // VIP / business price list
        for (final l in _lines) {
          final g = app.data!.garments.where((g) => g.name == l.garment).firstOrNull;
          final r = g == null ? null : app.data!.rateFor(g.id, l.service, picked);
          if (r != null) l.rate = r;
        }
      });
    }
  }

  void _create(BuildContext context) {
    final app = context.read<AppState>();
    final t = app.t;
    if (_customer == null) {
      toast(context, t('needCustomer'));
      return;
    }
    if (_lines.isEmpty) {
      toast(context, t('needItems'));
      return;
    }
    final lim = app.limit('order');
    if (lim != null) {
      toast(context, t(lim));
      return;
    }
    final d = app.data!;
    // offers (same maths as the screen)
    final sub = _lines.fold<double>(0, (s, l) => s + l.amount);
    final exp = _express ? sub * d.expressPct / 100 : 0.0;
    final disc0 = double.tryParse(_discount.text.trim()) ?? 0;
    final couponAmt = _coupon.text.trim().isEmpty ? 0.0 : d.couponDiscount(_coupon.text, _customer, sub);
    final couponOk = couponAmt > 0;
    final pkg = _packageUse(d);
    final room = (sub + exp - disc0 - couponAmt - (_usePackage && pkg != null ? pkg.$3 : 0)).clamp(0, double.infinity).toDouble();
    final pm = d.pointsMoney(_customer);
    final pointsAmt = _usePoints ? (pm < room ? pm : room) : 0.0;
    final o = d.createOrder(
      customerId: _customer!.id,
      branchId: _branchId ?? d.branches.first.id,
      lines: _lines.map((l) => OrderLine.fromJson(l.toJson())).toList(),
      by: app.actorId,
      express: _express,
      homeDelivery: _home,
      pickup: _pickup,
      discount: double.tryParse(_discount.text.trim()) ?? 0,
      dueAt: _due,
      advance: double.tryParse(_advance.text.trim()) ?? 0,
      advanceMode: _mode,
      notes: _notes.text.trim(),
      couponCode: couponOk ? _coupon.text.trim().toUpperCase() : '',
      couponAmount: couponOk ? couponAmt : 0,
      pointsUsed: pointsAmt,
      package: _usePackage ? pkg?.$1 : null,
      packageQty: _usePackage && pkg != null ? pkg.$2 : 0,
      packageValue: _usePackage && pkg != null ? pkg.$3 : 0,
      slot: _pickup ? _slot : '',
    );
    toast(context, t('orderCreated').replaceAll('{c}', o.code));
    final pr = ThermalPrinter.instance;
    pr.load().then((_) async {
      if (pr.mac.isEmpty) return;
      if (pr.autoBill) await pr.send(pr.billBytes(shop: app.shop!, d: d, o: o));
      if (pr.autoTags) await pr.send(pr.tagBytes(d: d, o: o));
    });
    _reset();
    Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id)));
  }
}

class _GarmentTile extends StatelessWidget {
  const _GarmentTile({required this.name, required this.price, required this.count, required this.onTap});
  final String name;
  final String price;
  final double count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: count > 0 ? const Color(0xFFE6EEFC) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: count > 0 ? LD.primary : LD.line, width: count > 0 ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(price, style: const TextStyle(fontSize: 11, color: LD.slate)),
              ]),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: LD.primary, borderRadius: BorderRadius.circular(99)),
                  child: Text(count == count.roundToDouble() ? count.toStringAsFixed(0) : count.toStringAsFixed(1),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      );
}

/// Search existing customers or add a new one.
Future<Customer?> pickCustomer(BuildContext context, AppState app) {
  final d = app.data!;
  final t = app.t;
  var q = '';
  return sheet<Customer>(context, t('customer'), (c) {
    return StatefulBuilder(builder: (c, set) {
      final ql = q.toLowerCase();
      final list = d.customers.where((x) => q.isEmpty || x.name.toLowerCase().contains(ql) || x.phone.contains(q)).take(30).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          autofocus: true,
          decoration: fieldDeco(t('search'), icon: Icons.search_rounded),
          onChanged: (v) => set(() => q = v),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () async {
            final added = await customerForm(context, app, prefill: q);
            if (added != null && c.mounted) Navigator.pop(c, added);
          },
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: Text(t('addCustomer')),
        ),
        const SizedBox(height: 6),
        for (final x in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Avatar(initialsOf(x.name), color: avatarColor(x.id)),
            title: Text(x.name),
            subtitle: Text('+${x.phone}'),
            onTap: () => Navigator.pop(c, x),
          ),
      ]);
    });
  });
}

Future<Customer?> customerForm(BuildContext context, AppState app, {String prefill = '', Customer? edit}) {
  final t = app.t;
  final isNum = RegExp(r'^[0-9 +]+$').hasMatch(prefill);
  final name = TextEditingController(text: edit?.name ?? (isNum ? '' : prefill));
  final phone = TextEditingController(text: edit?.phone ?? (isNum ? prefill : ''));
  final addr = TextEditingController(text: edit?.address ?? '');
  var type = edit?.type ?? 'regular';
  DateTime? dob = edit?.dob;
  String referredBy = edit?.referredBy ?? '';
  final d = app.data!;
  return sheet<Customer>(context, edit == null ? t('addCustomer') : t('edit'), (c) {
    return StatefulBuilder(builder: (c, set) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, decoration: fieldDeco(t('name'), icon: Icons.person_outline)),
        const SizedBox(height: 10),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: fieldDeco(t('phone'), icon: Icons.phone_outlined)),
        const SizedBox(height: 10),
        TextField(controller: addr, decoration: fieldDeco(t('addressOpt'), icon: Icons.place_outlined)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final ty in ['regular', 'vip', 'business']) Pill(label: t('type.$ty'), on: type == ty, onTap: () => set(() => type = ty)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () async {
                final p = await showDatePicker(context: c, initialDate: dob ?? DateTime(1990, 1, 1), firstDate: DateTime(1930), lastDate: DateTime.now());
                if (p != null) set(() => dob = p);
              },
              icon: const Icon(Icons.cake_outlined, size: 18),
              label: Text(dob == null ? L(app, 'Birthday (optional)', 'जन्मदिन (ज़रूरी नहीं)') : dmy(dob!)),
            ),
          ),
          if (edit == null || edit.referredBy.isEmpty)
            Expanded(
              child: TextButton.icon(
                onPressed: () async {
                  final p = await pickCustomer(c, app);
                  if (p != null && p.id != edit?.id) set(() => referredBy = p.id);
                },
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: Text(referredBy.isEmpty ? L(app, 'Referred by…', 'किसने भेजा…') : (d.customer(referredBy)?.name ?? ''), overflow: TextOverflow.ellipsis),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () {
            final digits = phone.text.replaceAll(RegExp(r'[^0-9]'), '');
            if (name.text.trim().length < 2 || digits.length < 7) return;
            if (edit != null) {
              edit
                ..name = name.text.trim()
                ..phone = digits
                ..address = addr.text.trim()
                ..type = type
                ..dob = dob
                ..referredBy = edit.referredBy.isEmpty ? referredBy : edit.referredBy;
              app.data!.updateCustomer(edit);
              Navigator.pop(c, edit);
            } else {
              final nc = app.data!.addCustomer(name: name.text, phone: digits, address: addr.text, type: type);
              if (dob != null || referredBy.isNotEmpty) {
                nc
                  ..dob = dob
                  ..referredBy = referredBy;
                app.data!.updateCustomer(nc);
              }
              Navigator.pop(c, nc);
            }
          },
          child: Text(t('save')),
        ),
      ]);
    });
  });
}
