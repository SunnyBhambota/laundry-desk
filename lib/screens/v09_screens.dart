import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../data/ops_models.dart';
import '../data/shop_data.dart';
import '../services/export_service.dart';
import '../services/license_service.dart';
import '../services/photo_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'customers_screen.dart';
import 'order_detail_screen.dart';

// ======================= garment photos =======================

class OrderPhotosCard extends StatefulWidget {
  const OrderPhotosCard({super.key, required this.orderId});
  final String orderId;
  @override
  State<OrderPhotosCard> createState() => _OrderPhotosCardState();
}

class _OrderPhotosCardState extends State<OrderPhotosCard> {
  List<GarmentPhoto>? _photos;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = context.read<AppState>().data!;
    final l = await PhotoService.instance.list(d, widget.orderId);
    if (mounted) setState(() => _photos = l);
  }

  Future<void> _add(bool camera) async {
    final app = context.read<AppState>();
    final bytes = await PhotoService.instance.take(camera: camera);
    if (bytes == null || !mounted) return;
    final note = await _askNote(app);
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await PhotoService.instance.add(app.data!, widget.orderId, bytes, by: app.actorId, note: note ?? '');
      await _load();
    } catch (_) {
      if (mounted) toast(context, L(app, 'Photo not saved – check internet.', 'फोटो सेव नहीं हुई – इंटरनेट देखें।'));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<String?> _askNote(AppState app) {
    final c = TextEditingController();
    return sheet<String>(context, L(app, 'What is in the photo?', 'फोटो में क्या है?'), (sc) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, children: [
            for (final x in ['Stain', 'Torn', 'Button missing', 'Colour fade', 'Burn mark', 'Shrink'])
              ActionChip(label: Text(x), onPressed: () => c.text = c.text.isEmpty ? x : '${c.text}, $x'),
          ]),
          const SizedBox(height: 8),
          TextField(controller: c, decoration: fieldDeco(L(app, 'Note (shirt collar stain…)', 'नोट (शर्ट कॉलर पर दाग…)'))),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(sc, c.text.trim()), child: Text(app.t('save'))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final l = _photos;
    return SectionCard(
      title: '${L(app, 'Photos (damage / stains)', 'फोटो (नुकसान / दाग)')}${l == null ? '' : ' · ${l.length}'}',
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: L(app, 'Camera', 'कैमरा'), onPressed: _busy ? null : () => _add(true), icon: const Icon(Icons.photo_camera_outlined)),
        IconButton(tooltip: L(app, 'Gallery', 'गैलरी'), onPressed: _busy ? null : () => _add(false), icon: const Icon(Icons.photo_library_outlined)),
      ]),
      child: l == null || _busy
          ? const LinearProgressIndicator(minHeight: 2)
          : l.isEmpty
              ? Text(L(app, 'Take a photo of any stain or damage when you receive the clothes – it stops arguments later.',
                  'कपड़े लेते समय दाग या नुकसान की फोटो लें – बाद में बहस नहीं होगी।'), style: const TextStyle(color: LD.slate, fontSize: 12))
              : SizedBox(
                  height: 96,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final p in l)
                      GestureDetector(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (c) => Dialog(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Image.memory(p.bytes, fit: BoxFit.contain),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text('${p.note.isEmpty ? '' : '${p.note} · '}${d.nameOf(p.by)} · ${whenText(p.at)}'),
                              ),
                              if (app.canManage)
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(c);
                                    await PhotoService.instance.remove(d, p);
                                    _load();
                                  },
                                  child: Text(L(app, 'Delete photo', 'फोटो हटाएँ'), style: const TextStyle(color: Color(0xFFB42318))),
                                ),
                            ]),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(p.bytes, width: 96, height: 96, fit: BoxFit.cover)),
                        ),
                      ),
                  ]),
                ),
    );
  }
}

// ======================= customer feedback =======================

class OrderRatingCard extends StatelessWidget {
  const OrderRatingCard({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final o = d.order(orderId);
    if (o == null || o.status != 'delivered') return const SizedBox.shrink();
    final c = d.customer(o.customerId);
    return SectionCard(
      title: L(app, 'Customer feedback', 'ग्राहक की राय'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              iconSize: 34,
              onPressed: () => _rate(context, app, o, i),
              icon: Icon(i <= o.rating ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFE8A317)),
            ),
        ]),
        if (o.ratingNote.isNotEmpty) Text('“${o.ratingNote}”', textAlign: TextAlign.center),
        if (o.rating == 0 && (c?.phone ?? '').isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => openWhatsApp(
                c!.phone,
                'Namaste ${c.name}, thank you for choosing ${app.shop!.shopName}! How was our service for order ${o.code}? '
                'Please reply with 1 to 5 ⭐ (5 = excellent) and any suggestion. 🙏'),
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: Text(L(app, 'Ask feedback on WhatsApp', 'WhatsApp पर राय पूछें')),
          ),
      ]),
    );
  }

  void _rate(BuildContext context, AppState app, LaundryOrder o, int stars) {
    final note = TextEditingController(text: o.ratingNote);
    sheet(context, '$stars ★', (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: note, decoration: fieldDeco(L(app, 'What did the customer say? (optional)', 'ग्राहक ने क्या कहा? (ज़रूरी नहीं)'))),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              app.data!.rateOrder(o, stars, by: app.actorId, note: note.text);
              Navigator.pop(c);
            },
            child: Text(app.t('save')),
          ),
        ]));
  }
}

/// Reports: average rating, how many, low ratings to call back.
class RatingsCard extends StatelessWidget {
  const RatingsCard({super.key, required this.from, required this.to});
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final rated = d.ordersIn(app.scopeBranch).where((o) => o.rating > 0 && !o.createdAt.isBefore(from) && o.createdAt.isBefore(to)).toList();
    if (rated.isEmpty) return const SizedBox.shrink();
    final avg = rated.fold<int>(0, (s, o) => s + o.rating) / rated.length;
    final low = rated.where((o) => o.rating <= 2).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        title: L(app, 'Customer ratings', 'ग्राहक रेटिंग'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(avg.toStringAsFixed(1), style: heading(28, color: const Color(0xFFE8A317))),
            const Icon(Icons.star_rounded, color: Color(0xFFE8A317)),
            const SizedBox(width: 10),
            Text('${rated.length} ${L(app, 'ratings', 'रेटिंग')}', style: const TextStyle(color: LD.slate)),
          ]),
          for (var st = 5; st >= 1; st--)
            Row(children: [
              SizedBox(width: 22, child: Text('$st★', style: const TextStyle(fontSize: 12))),
              Expanded(
                child: LinearProgressIndicator(
                  value: rated.where((o) => o.rating == st).length / rated.length,
                  minHeight: 6,
                  color: st >= 4 ? LD.success : (st == 3 ? const Color(0xFFE8A317) : const Color(0xFFB42318)),
                  backgroundColor: const Color(0xFFEDF0F4),
                ),
              ),
              SizedBox(width: 30, child: Text(' ${rated.where((o) => o.rating == st).length}', style: const TextStyle(fontSize: 12))),
            ]),
          if (low.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(L(app, 'Unhappy customers – call them:', 'नाराज़ ग्राहक – फ़ोन करें:'), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB42318))),
            for (final o in low)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${d.customer(o.customerId)?.name ?? ''} · ${o.code} · ${o.rating}★'),
                subtitle: o.ratingNote.isEmpty ? null : Text(o.ratingNote),
                trailing: IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => callPhone(d.customer(o.customerId)?.phone ?? '')),
              ),
          ],
        ]),
      ),
    );
  }
}

// ======================= customer groups (WhatsApp one by one) =======================

class CustomerGroupsScreen extends StatefulWidget {
  const CustomerGroupsScreen({super.key});
  @override
  State<CustomerGroupsScreen> createState() => _CustomerGroupsScreenState();
}

class _CustomerGroupsScreenState extends State<CustomerGroupsScreen> {
  String _g = 'away30';
  final _sent = <String>{};
  final _msg = TextEditingController();

  static const groups = {
    'away30': ('Not came in 30 days', '30 दिन से नहीं आए'),
    'away60': ('Not came in 60 days', '60 दिन से नहीं आए'),
    'dues': ('Money pending', 'पैसे बाकी'),
    'birthday': ('Birthday this month', 'इस महीने जन्मदिन'),
    'vip': ('VIP', 'VIP'),
    'business': ('Business', 'बिज़नेस'),
    'top': ('Top 20 spenders', 'सबसे ज़्यादा खर्च वाले 20'),
    'new': ('New (30 days)', 'नए (30 दिन)'),
    'low_rating': ('Gave low rating', 'कम रेटिंग दी'),
    'all': ('All customers', 'सभी ग्राहक'),
  };

  String _template(AppState app, String g) {
    final shop = app.shop!.shopName;
    return switch (g) {
      'away30' || 'away60' => 'Namaste {name}, we miss you at $shop! Get 10% off on your next order this week. Free pickup – just reply here.',
      'dues' => 'Namaste {name}, a friendly reminder: {due} is pending with $shop. You can pay by UPI or cash. Thank you!',
      'birthday' => 'Happy Birthday {name}! 🎂 A gift from $shop: 20% off on your next order this month.',
      'low_rating' => 'Namaste {name}, sorry your last experience with $shop was not good. We would love to fix it – this time the service is on us.',
      _ => 'Namaste {name}, greetings from $shop! ',
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _msg.text = _template(context.read<AppState>(), _g)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final list = d.customerGroup(_g);
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'Customer groups', 'ग्राहक ग्रुप'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in groups.entries)
            Pill(
              label: '${L(app, e.value.$1, e.value.$2)} (${d.customerGroup(e.key).length})',
              on: _g == e.key,
              onTap: () => setState(() {
                _g = e.key;
                _sent.clear();
                _msg.text = _template(app, e.key);
              }),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _msg, maxLines: 3, decoration: fieldDeco(L(app, 'Message ({name}, {due} are filled in)', 'संदेश ({name}, {due} अपने-आप भरेंगे)'))),
        const SizedBox(height: 6),
        Text('${L(app, 'Tap WhatsApp for each – it opens with the message ready.', 'हर एक के लिए WhatsApp दबाएँ – संदेश तैयार खुलेगा।')} ${_sent.length}/${list.length} ${L(app, 'sent', 'भेजे')}',
            style: const TextStyle(fontSize: 12, color: LD.slate)),
        const SizedBox(height: 6),
        for (final c in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.name, style: TextStyle(fontWeight: FontWeight.w600, decoration: _sent.contains(c.id) ? TextDecoration.lineThrough : null)),
            subtitle: Text([
              '+${c.phone}',
              if (d.lastVisit(c.id) != null) '${L(app, 'last', 'आख़िरी')} ${dmy(d.lastVisit(c.id)!)}',
              if (d.dueOf(c.id) > 0.5) '${L(app, 'due', 'बाकी')} ${money(d.dueOf(c.id), app.shop!.currency)}',
              if (c.dob != null) '🎂 ${dmy(c.dob!).substring(0, 6)}',
            ].join(' · ')),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id))),
            trailing: IconButton(
              icon: Icon(_sent.contains(c.id) ? Icons.check_circle : Icons.chat_outlined, color: _sent.contains(c.id) ? LD.success : LD.primary),
              onPressed: () {
                openWhatsApp(c.phone, _msg.text.replaceAll('{name}', c.name).replaceAll('{due}', money(d.dueOf(c.id), app.shop!.currency)));
                setState(() => _sent.add(c.id));
              },
            ),
          ),
      ]),
    );
  }
}

// ======================= customer page extras =======================

class CustomerMoreCard extends StatelessWidget {
  const CustomerMoreCard({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final c = d.customer(customerId);
    if (c == null) return const SizedBox.shrink();
    final hist = d.clothesHistory(c.id);
    final rated = d.orders.where((o) => o.customerId == c.id && o.rating > 0).toList();
    final ref = c.referredBy.isEmpty ? null : d.customer(c.referredBy);
    final brought = d.customers.where((x) => x.referredBy == c.id).toList();
    // last service/rate per garment
    final last = <String, (LaundryOrder, OrderLine)>{};
    for (final h in hist) {
      last.putIfAbsent('${h.$2.garment}|${h.$2.service}', () => h);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 16, runSpacing: 6, children: [
            Text('${L(app, 'Spent', 'कुल खर्च')}: ${money(d.spendOf(c.id), app.shop!.currency)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (d.lastVisit(c.id) != null) Text('${L(app, 'Last visit', 'आख़िरी बार')}: ${dmy(d.lastVisit(c.id)!)}'),
            if (rated.isNotEmpty) Text('${(rated.fold<int>(0, (s, o) => s + o.rating) / rated.length).toStringAsFixed(1)} ★ (${rated.length})'),
            if (c.dob != null) Text('🎂 ${dmy(c.dob!)}'),
          ]),
          if (ref != null) Text('${L(app, 'Referred by', 'किसने भेजा')}: ${ref.name}${c.referralPaid ? ' ✓' : ''}', style: const TextStyle(color: LD.slate)),
          if (brought.isNotEmpty) Text('${L(app, 'Brought', 'इन्होंने भेजे')}: ${brought.map((x) => x.name).join(', ')}', style: const TextStyle(color: LD.slate)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _statement(context, app, c),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(L(app, 'Monthly bill / statement', 'महीने का बिल / स्टेटमेंट')),
            ),
          ]),
        ]),
      ),
      if (last.isNotEmpty) ...[
        const SizedBox(height: 12),
        SectionCard(
          title: L(app, 'Clothes history (last time)', 'कपड़ों का इतिहास (पिछली बार)'),
          child: Column(children: [
            for (final h in last.values.take(15))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${h.$2.garment} – ${hiName(app, h.$2.service)}'),
                subtitle: Text([dmy(h.$1.createdAt), h.$1.code, if (h.$2.details.isNotEmpty) h.$2.details, if (h.$2.note.isNotEmpty) '⚠ ${h.$2.note}'].join(' · ')),
                trailing: Text(money(h.$2.rate, app.shop!.currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: h.$1.id))),
              ),
          ]),
        ),
      ],
    ]);
  }

  void _statement(BuildContext context, AppState app, Customer c) {
    final n = DateTime.now();
    sheet(context, L(app, 'Statement for which month?', 'किस महीने का स्टेटमेंट?'), (sc) => Column(children: [
          for (var i = 0; i < 4; i++)
            Builder(builder: (_) {
              final from = DateTime(n.year, n.month - i, 1);
              final to = DateTime(n.year, n.month - i + 1, 1);
              return ListTile(
                title: Text('${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][from.month - 1]} ${from.year}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Print',
                    icon: const Icon(Icons.print_outlined),
                    onPressed: () async =>
                        ExportService.printPdf(await ExportService.statementPdf(shop: app.shop!, data: app.data!, c: c, from: from, to: to), 'Statement ${c.name}'),
                  ),
                  IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () async => ExportService.sharePdf(
                        await ExportService.statementPdf(shop: app.shop!, data: app.data!, c: c, from: from, to: to), 'statement-${c.name}-${dayKey(from)}.pdf'),
                  ),
                ]),
              );
            }),
        ]));
  }
}

// ======================= scan piece tags to count =======================

/// Scan every tag of an order before handing over: shows which pieces are missing.
class PieceScanScreen extends StatefulWidget {
  const PieceScanScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<PieceScanScreen> createState() => _PieceScanScreenState();
}

class _PieceScanScreenState extends State<PieceScanScreen> {
  final _ctrl = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  final _got = <int>{};
  String _warn = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _found(LaundryOrder o, String raw) {
    final m = RegExp(r'LD-(\d{1,6})\D+(\d+)\s*/\s*(\d+)').firstMatch(raw);
    if (m == null) return;
    final n = int.parse(m.group(1)!);
    final i = int.parse(m.group(2)!);
    if (n != o.number) {
      setState(() => _warn = 'LD-${m.group(1)} ≠ ${o.code}!');
      HapticFeedback.heavyImpact();
      return;
    }
    if (_got.add(i)) {
      HapticFeedback.selectionClick();
      setState(() => _warn = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final o = app.data!.order(widget.orderId);
    if (o == null) return const Scaffold();
    final total = o.pieces;
    final missing = [for (var i = 1; i <= total; i++) if (!_got.contains(i)) i];
    return Scaffold(
      appBar: AppBar(title: Text('${o.code} · ${_got.length}/$total')),
      body: Column(children: [
        SizedBox(
          height: 300,
          child: MobileScanner(
            controller: _ctrl,
            onDetect: (cap) {
              for (final b in cap.barcodes) {
                if (b.rawValue != null) _found(o, b.rawValue!);
              }
            },
          ),
        ),
        if (_warn.isNotEmpty)
          Container(
            width: double.infinity,
            color: const Color(0xFFFDE8E8),
            padding: const EdgeInsets.all(10),
            child: Text('${L(app, 'Wrong order tag', 'गलत ऑर्डर का टैग')}: $_warn', style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w800)),
          ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            LinearProgressIndicator(value: total == 0 ? 0 : _got.length / total, minHeight: 10, color: LD.success, backgroundColor: const Color(0xFFEDF0F4)),
            const SizedBox(height: 10),
            Text(missing.isEmpty ? L(app, 'All pieces scanned ✓', 'सारे कपड़े स्कैन हो गए ✓') : '${L(app, 'Still missing', 'अभी बाकी')}: ${missing.join(', ')}',
                style: heading(16, weight: FontWeight.w700, color: missing.isEmpty ? LD.success : const Color(0xFF8A5A00))),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(context, _got.length),
              child: Text('${L(app, 'Use count', 'गिनती लें')}: ${_got.length}'),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ======================= app admin: all shops' plans =======================

Future<void> openAppAdmin(BuildContext context) async {
  final app = context.read<AppState>();
  final ok = await LicenseService.instance.isAdmin();
  if (!context.mounted) return;
  if (ok) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLicensesScreen()));
    return;
  }
  final uid = app.shopOwnerUid;
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('App admin'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(L(app, 'This account is not the app admin. To make it admin (one time):', 'ये अकाउंट ऐप एडमिन नहीं है। एडमिन बनाने के लिए (एक बार):')),
        const SizedBox(height: 8),
        const Text('Firebase → Firestore → + Start collection → "admins" → Document ID = this ID → Save'),
        const SizedBox(height: 8),
        SelectableText(uid, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
      ]),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: uid));
            Navigator.pop(c);
            toast(context, L(app, 'ID copied', 'ID कॉपी हो गई'));
          },
          child: Text(L(app, 'Copy ID', 'ID कॉपी करें')),
        ),
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
      ],
    ),
  );
}

class AdminLicensesScreen extends StatefulWidget {
  const AdminLicensesScreen({super.key});
  @override
  State<AdminLicensesScreen> createState() => _AdminLicensesScreenState();
}

class _AdminLicensesScreenState extends State<AdminLicensesScreen> {
  List<(String, Map<String, dynamic>)>? _list;
  String _err = '';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await LicenseService.instance.all();
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final n = DateTime.now();
    final l = (_list ?? []).where((x) => _q.isEmpty || '${x.$2['shopName']} ${x.$2['phone']} ${x.$2['code']}'.toLowerCase().contains(_q)).toList();
    final paid = (_list ?? []).where((x) => x.$2['plan'] == 'pro' || x.$2['plan'] == 'business').length;
    return Scaffold(
      appBar: AppBar(title: Text(L(app, 'All shops', 'सभी दुकानें')), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _list == null
          ? Center(child: _err.isEmpty ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(20), child: Text(_err)))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              Text('${_list!.length} ${L(app, 'shops', 'दुकानें')} · $paid ${L(app, 'paid', 'पेड')}', style: heading(16, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(onChanged: (v) => setState(() => _q = v.trim().toLowerCase()), decoration: fieldDeco(L(app, 'Search shop / phone / code', 'दुकान / फ़ोन / कोड खोजें'), icon: Icons.search)),
              const SizedBox(height: 8),
              for (final x in l)
                Builder(builder: (_) {
                  final until = DateTime.tryParse('${x.$2['until'] ?? ''}');
                  final expired = until != null && until.isBefore(n);
                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: expired ? const Color(0xFFB42318) : LD.line)),
                    child: ListTile(
                      title: Text('${x.$2['shopName'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${x.$2['plan']} · ${until == null ? '∞' : '${L(app, 'till', 'तक')} ${dmy(until)}'}${expired ? ' · EXPIRED' : ''}\n'
                          '${x.$2['phone'] ?? ''} · ${x.$2['code'] ?? ''}'),
                      isThreeLine: true,
                      onTap: () => _edit(app, x.$1, x.$2),
                    ),
                  );
                }),
            ]),
    );
  }

  void _edit(AppState app, String uid, Map<String, dynamic> j) {
    var plan = '${j['plan'] ?? 'trial'}';
    var until = DateTime.tryParse('${j['until'] ?? ''}');
    final disabled = ((j['disabled'] as List?) ?? []).map((e) => '$e').toSet();
    final modules = [...AppConfig.freeModules, ...AppConfig.premiumModules];
    sheet(context, '${j['shopName'] ?? ''}', (c) => StatefulBuilder(builder: (c, set) {
          DateTime base() => until == null || until!.isBefore(DateTime.now()) ? DateTime.now() : until!;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in ['trial', 'free', 'pro', 'business', 'blocked']) Pill(label: p, on: plan == p, onTap: () => set(() => plan = p)),
            ]),
            const SizedBox(height: 10),
            Text('${L(app, 'Valid till', 'कब तक')}: ${until == null ? '∞' : dmy(until!)}', style: heading(15, weight: FontWeight.w700)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: () => set(() => until = base().add(const Duration(days: 30))), child: const Text('+1 month')),
              OutlinedButton(onPressed: () => set(() => until = base().add(const Duration(days: 182))), child: const Text('+6 months')),
              OutlinedButton(onPressed: () => set(() => until = base().add(const Duration(days: 365))), child: const Text('+1 year')),
              TextButton(onPressed: () => set(() => until = null), child: const Text('No end')),
            ]),
            const SizedBox(height: 8),
            for (final m in modules)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(app.t('m.$m')),
                value: !disabled.contains(m),
                onChanged: (v) => set(() => v ? disabled.remove(m) : disabled.add(m)),
              ),
            FilledButton(
              onPressed: () async {
                try {
                  await LicenseService.instance.update(uid, {'plan': plan, 'until': until?.toIso8601String(), 'disabled': disabled.toList()});
                  if (c.mounted) Navigator.pop(c);
                  _load();
                } catch (e) {
                  if (c.mounted) toast(c, '$e');
                }
              },
              child: Text(app.t('save')),
            ),
          ]);
        }));
  }
}
