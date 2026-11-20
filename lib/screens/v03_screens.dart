import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/ops_models.dart';
import '../services/thermal_printer.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'order_detail_screen.dart';
import 'v08_screens.dart';

// ---------------- edit order + refund ----------------

class EditOrderScreen extends StatefulWidget {
  const EditOrderScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<EditOrderScreen> createState() => _EditOrderScreenState();
}

class _EditOrderScreenState extends State<EditOrderScreen> {
  late List<OrderLine> _lines;
  late double _discount;
  late bool _express;
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final o = d.order(widget.orderId)!;
    final cur = app.shop!.currency;
    if (!_init) {
      _init = true;
      _lines = o.lines.map((l) => OrderLine.fromJson(l.toJson())).toList();
      _discount = o.discount;
      _express = o.express;
    }
    final sub = _lines.fold<double>(0, (s, l) => s + l.amount);
    final exp = _express ? sub * o.expressPct / 100 : 0.0;
    final taxable = (sub + exp - _discount).clamp(0, double.infinity).toDouble();
    final total = (taxable + taxable * o.taxPct / 100).roundToDouble();
    final extra = o.paid - total;

    return Scaffold(
      appBar: AppBar(title: Text('${L(app, 'Edit', 'बदलें')} ${o.code}')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(12)),
          child: Text(L(app, 'Every change is saved in the order timeline: who, when, old total.', 'हर बदलाव टाइमलाइन में लिखा जाएगा: किसने, कब, पुराना टोटल।'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A00))),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Clothes', 'कपड़े'),
          child: Column(children: [
            for (final l in _lines)
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.garment, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${l.service} · ${money(l.rate, cur)}', style: const TextStyle(fontSize: 12, color: LD.slate)),
                  ]),
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
                IconButton(tooltip: '+', onPressed: () => setState(() => l.qty += l.unit == 'kg' ? .5 : 1), icon: const Icon(Icons.add_circle_outline)),
                SizedBox(width: 62, child: Text(money(l.amount, cur), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            TextButton.icon(onPressed: () => _addLine(context, app, o), icon: const Icon(Icons.add), label: Text(L(app, 'Add item', 'आइटम जोड़ें'))),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${app.t('express')} (+${o.expressPct.toStringAsFixed(0)}%)'),
              value: _express,
              onChanged: (v) => setState(() => _express = v),
            ),
            TextFormField(
              initialValue: _discount.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: fieldDeco(app.t('discount'), icon: Icons.local_offer_outlined),
              onChanged: (v) => setState(() => _discount = double.tryParse(v) ?? 0),
            ),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: Text(L(app, 'New total', 'नया टोटल'))), Text(money(total, cur), style: heading(20))]),
            Row(children: [
              Expanded(child: Text(L(app, 'Was', 'पहले था'), style: const TextStyle(color: LD.slate))),
              Text(money(o.total, cur), style: const TextStyle(color: LD.slate, decoration: TextDecoration.lineThrough)),
            ]),
            Row(children: [Expanded(child: Text(app.t('paid'))), Text(money(o.paid, cur))]),
            if (extra > 0.5)
              Row(children: [
                Expanded(child: Text(L(app, 'To give back (refund)', 'वापस देना है (रिफ़ंड)'), style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w700))),
                Text(money(extra, cur), style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w800)),
              ]),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LD.navy, minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
            onPressed: _lines.isEmpty
                ? null
                : () async {
                    d.editOrder(o, _lines, by: app.actorId, discount: _discount, express: _express);
                    final over = d.overpaid(o);
                    if (over > 0 && context.mounted) await refundSheet(context, o, over);
                    if (context.mounted) Navigator.pop(context);
                  },
            child: Text(L(app, 'Save changes', 'बदलाव सेव करें')),
          ),
        ),
      ),
    );
  }

  void _addLine(BuildContext context, AppState app, LaundryOrder o) {
    final d = app.data!;
    final c = d.customer(o.customerId);
    final opts = <(String, String, String, double)>[
      for (final g in d.garments)
        for (final s in app.shop!.services)
          if (d.rateFor(g.id, s, c) != null) (g.name, s, g.unit, d.rateFor(g.id, s, c)!),
    ];
    var q = '';
    sheet(context, L(app, 'Add item', 'आइटम जोड़ें'), (sc) => StatefulBuilder(builder: (sc, set) {
          final f = opts.where((x) => q.isEmpty || '${x.$1} ${x.$2}'.toLowerCase().contains(q.toLowerCase())).take(40);
          return Column(children: [
            TextField(decoration: fieldDeco(app.t('search'), icon: Icons.search), onChanged: (v) => set(() => q = v)),
            for (final x in f)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(x.$1),
                subtitle: Text(x.$2),
                trailing: Text(money(x.$4, app.shop!.currency)),
                onTap: () {
                  setState(() => _lines.add(OrderLine(garment: x.$1, service: x.$2, qty: 1, rate: x.$4, unit: x.$3)));
                  Navigator.pop(sc);
                },
              ),
          ]);
        }));
  }
}

Future<void> refundSheet(BuildContext context, LaundryOrder o, double amount) {
  final app = context.read<AppState>();
  final ctrl = TextEditingController(text: amount.toStringAsFixed(0));
  final note = TextEditingController();
  var mode = 'cash';
  return sheet(context, L(app, 'Refund', 'रिफ़ंड'), (c) => StatefulBuilder(builder: (c, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: fieldDeco(app.t('amount'), icon: Icons.currency_rupee_rounded)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Pill(label: app.t('cash'), on: mode == 'cash', onTap: () => set(() => mode = 'cash')),
            Pill(label: 'UPI', on: mode == 'upi', onTap: () => set(() => mode = 'upi')),
            Pill(label: L(app, 'Keep for next order', 'अगले ऑर्डर में'), on: mode == 'credit', onTap: () => set(() => mode = 'credit')),
          ]),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: fieldDeco(L(app, 'Reason', 'वजह'))),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              final a = double.tryParse(ctrl.text.trim()) ?? 0;
              if (mode == 'credit') {
                // leave the extra on the order as customer credit (shown as negative balance)
                o.notes = '${o.notes}${o.notes.isEmpty ? '' : ' · '}Credit ${a.toStringAsFixed(0)} for next order';
                app.data!.changed();
              } else {
                app.data!.refund(o, a, mode, by: app.actorId, note: note.text.trim());
              }
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(L(app, 'Later', 'बाद में'))),
        ]);
      }));
}

// ---------------- QR tag scan ----------------

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ctrl = MobileScannerController();
  String? _code;
  LaundryOrder? _order;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _found(AppState app, String raw) {
    final m = RegExp(r'LD-(\d{1,6})').firstMatch(raw);
    if (m == null) return;
    final n = int.parse(m.group(1)!);
    final o = app.data!.orders.where((x) => x.number == n).firstOrNull;
    if (o == null || o.id == _order?.id) return;
    setState(() {
      _code = raw;
      _order = o;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final o = _order == null ? null : d.order(_order!.id);
    final next = o == null ? null : nextStatus(o.status, homeDelivery: o.homeDelivery);
    final canMove = next != null &&
        (app.canManage ||
            app.role == Role.counter ||
            (app.role == Role.washer && (o!.status == 'received' || o.status == 'washing')) ||
            (app.role == Role.delivery && (o!.status == 'pickup' || o.status == 'out' || o.status == 'ready')));
    return Scaffold(
      backgroundColor: const Color(0xFF0B1626),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1626),
        foregroundColor: Colors.white,
        title: Text(L(app, 'Scan tag / bill QR', 'टैग / बिल QR स्कैन')),
        actions: [IconButton(tooltip: 'Flash', onPressed: () => _ctrl.toggleTorch(), icon: const Icon(Icons.flashlight_on_outlined))],
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 280,
                height: 280,
                child: MobileScanner(
                  controller: _ctrl,
                  onDetect: (cap) {
                    for (final b in cap.barcodes) {
                      final v = b.rawValue;
                      if (v != null) _found(app, v);
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          child: o == null
              ? Text(L(app, 'Hold the garment tag or bill QR in front of the camera.', 'कपड़े का टैग या बिल का QR कैमरे के सामने रखें।'),
                  textAlign: TextAlign.center, style: const TextStyle(color: LD.slate))
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    StatusChip(o.status),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_code ?? o.code, style: heading(16, weight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 6),
                  Text('${d.customer(o.customerId)?.name ?? ''} · ${o.pieces} ${app.t('pcs')} · ${o.lines.map((l) => l.garment).toSet().join(', ')}'),
                  Text('${app.t('dueBy')} ${whenText(o.dueAt)}${o.rack.isEmpty ? '' : ' · ${app.t('rack')} ${o.rack}'}', style: const TextStyle(fontSize: 12, color: LD.slate)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id))),
                        child: Text(L(app, 'Open order', 'ऑर्डर खोलें')),
                      ),
                    ),
                    if (canMove) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: LD.success, minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                          onPressed: () async {
                            if (next == 'delivered' && o.due > 0) {
                              final paid = await payDialog(context, o);
                              if (paid == null) return;
                            }
                            if (!context.mounted) return;
                            await changeStatusFlow(context, app, o, next!);
                          },
                          child: Text('→ ${app.t(next!)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ]),
                ]),
        ),
      ]),
    );
  }
}

// ---------------- printer settings ----------------

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});
  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  final p = ThermalPrinter.instance;
  List<BluetoothInfo> _devices = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    p.load().then((_) => mounted ? setState(() {}) : null);
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    final l = await p.paired();
    if (mounted) {
      setState(() {
        _devices = l;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final upi = TextEditingController(text: d.upiId);
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Printer & UPI', 'प्रिंटर और UPI'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        SectionCard(
          title: L(app, 'Bluetooth thermal printer', 'ब्लूटूथ थर्मल प्रिंटर'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              p.mac.isEmpty ? L(app, 'No printer chosen yet.', 'अभी कोई प्रिंटर नहीं चुना।') : '${p.name} · ${p.mac}',
              style: TextStyle(fontWeight: FontWeight.w700, color: p.mac.isEmpty ? LD.slate : LD.success),
            ),
            const SizedBox(height: 6),
            Text(L(app, 'First pair the printer in phone Bluetooth settings, then tap Find.', 'पहले फ़ोन की Bluetooth सेटिंग में प्रिंटर pair करें, फिर ढूँढें दबाएँ।'),
                style: const TextStyle(fontSize: 12, color: LD.slate)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(L(app, 'Find paired printers', 'pair किए प्रिंटर ढूँढें')),
            ),
            for (final dv in _devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.print_outlined),
                title: Text(dv.name),
                subtitle: Text(dv.macAdress),
                trailing: p.mac == dv.macAdress ? const Icon(Icons.check_circle, color: LD.success) : null,
                onTap: () async {
                  p
                    ..mac = dv.macAdress
                    ..name = dv.name;
                  await p.save();
                  setState(() {});
                },
              ),
            const SizedBox(height: 6),
            Row(children: [
              Text(L(app, 'Paper', 'कागज़')),
              const Spacer(),
              Pill(label: '58 mm', on: p.width == 32, onTap: () async {
                p.width = 32;
                await p.save();
                setState(() {});
              }),
              const SizedBox(width: 8),
              Pill(label: '80 mm', on: p.width == 48, onTap: () async {
                p.width = 48;
                await p.save();
                setState(() {});
              }),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L(app, 'Print bill when an order is created', 'ऑर्डर बनते ही बिल प्रिंट')),
              value: p.autoBill,
              onChanged: (v) async {
                p.autoBill = v;
                await p.save();
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L(app, 'Also print a tag for every piece', 'हर पीस का टैग भी प्रिंट')),
              value: p.autoTags,
              onChanged: (v) async {
                p.autoTags = v;
                await p.save();
                setState(() {});
              },
            ),
            FilledButton.tonal(
              onPressed: () async {
                final e = Esc(p.width)
                  ..align(1)
                  ..bold(true)
                  ..text(app.shop!.shopName)
                  ..bold(false)
                  ..text('Printer test OK')
                  ..qr('LD-0000')
                  ..feed(3)
                  ..cut();
                final err = await p.send(e.b);
                if (context.mounted) toast(context, err ?? L(app, 'Printed', 'प्रिंट हो गया'));
              },
              child: Text(L(app, 'Test print', 'टेस्ट प्रिंट')),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'UPI payments', 'UPI पेमेंट'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: upi,
              enabled: app.isOwner,
              decoration: fieldDeco(L(app, 'Shop UPI ID (e.g. shop@okhdfc)', 'दुकान की UPI ID (जैसे shop@okhdfc)'), icon: Icons.qr_code_2),
              onSubmitted: (v) {
                d.upiId = v.trim();
                d.changed();
                toast(context, app.t('save'));
              },
            ),
            const SizedBox(height: 6),
            Text(L(app, 'Bills then show a UPI QR with the amount filled in.', 'तब बिल पर रकम के साथ UPI QR आएगा।'), style: const TextStyle(fontSize: 12, color: LD.slate)),
            if (app.isOwner)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    d.upiId = upi.text.trim();
                    d.changed();
                    toast(context, app.t('save'));
                  },
                  child: Text(app.t('save')),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Show a UPI QR for the amount due (customer scans with any UPI app).
void upiSheet(BuildContext context, LaundryOrder o) {
  final app = context.read<AppState>();
  final link = app.data!.upiLink(o, app.shop!.shopName);
  if (link == null) {
    toast(context, L(app, 'Add the shop UPI ID in More → Printer & UPI.', 'और → प्रिंटर और UPI में दुकान की UPI ID डालें।'));
    return;
  }
  sheet(context, '${L(app, 'Pay by UPI', 'UPI से पेमेंट')} · ${money(o.due, app.shop!.currency)}', (c) => Column(children: [
        Center(child: QrImageView(data: link, size: 240, backgroundColor: Colors.white)),
        const SizedBox(height: 8),
        Text(app.data!.upiId, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () {
            app.data!.addPayment(o, o.due, 'upi', by: app.actorId, note: 'UPI QR');
            Navigator.pop(c);
          },
          child: Text(L(app, 'Payment received', 'पेमेंट मिल गया')),
        ),
      ]));
}

// ---------------- backup / restore ----------------

class BackupCard extends StatelessWidget {
  const BackupCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    return SectionCard(
      title: L(app, 'Backup & restore', 'बैकअप और रिस्टोर'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          d.cloudOn ? L(app, 'Cloud backup is on (Firebase).', 'क्लाउड बैकअप चालू है (Firebase)।') : L(app, 'Data is only on this phone.', 'डेटा सिर्फ़ इसी फ़ोन में है।'),
          style: TextStyle(fontWeight: FontWeight.w700, color: d.cloudOn ? LD.success : const Color(0xFF8A5A00)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final raw = const JsonEncoder.withIndent(' ').convert({'app': 'laundry-desk', 'shop': app.shop!.toJson(), 'data': d.toJson()});
            final now = DateTime.now();
            await Share.shareXFiles(
              [XFile.fromData(Uint8List.fromList(utf8.encode(raw)), name: 'laundry-desk-backup-${dayKey(now)}.json', mimeType: 'application/json')],
              subject: 'LaundryCase backup',
            );
          },
          icon: const Icon(Icons.download_outlined),
          label: Text(L(app, 'Save full backup file', 'पूरा बैकअप फ़ाइल में सेव')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
            final f = r?.files.single;
            if (f == null) return;
            final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
            if (bytes == null) return;
            Map<String, dynamic> j;
            try {
              j = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
              if (j['app'] != 'laundry-desk' || j['data'] is! Map) throw const FormatException();
            } catch (_) {
              if (context.mounted) toast(context, L(app, 'This is not a LaundryCase backup file.', 'यह Laundry Desk की बैकअप फ़ाइल नहीं है।'));
              return;
            }
            if (!context.mounted) return;
            final ok = await confirm(context, L(app, 'Restore backup?', 'बैकअप वापस लाएँ?'),
                L(app, 'All current data will be replaced by the file.', 'अभी का सारा डेटा फ़ाइल वाले डेटा से बदल जाएगा।'), danger: true);
            if (!ok) return;
            d.restoreFrom(Map<String, dynamic>.from(j['data'] as Map));
            if (context.mounted) toast(context, L(app, 'Backup restored.', 'बैकअप वापस आ गया।'));
          },
          icon: const Icon(Icons.upload_outlined),
          label: Text(L(app, 'Restore from file', 'फ़ाइल से रिस्टोर')),
        ),
      ]),
    );
  }
}
