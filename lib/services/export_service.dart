import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../data/issue_models.dart';
import '../data/ops_models.dart';
import '../data/reports.dart';
import '../data/shop_data.dart';
import '../logic/payroll.dart';
import '../models/models.dart';
import '../widgets/ui.dart' show money, qtyText, dmy, hm;

/// PDF bills (thermal roll + A4), QR garment tags, report PDF and CSV exports.
class ExportService {
  ExportService._();

  /// Built-in PDF fonts have no ₹ sign.
  static String _m(num v, String cur) => money(v, cur).replaceAll('₹', 'Rs. ');

  static const _navy = PdfColor.fromInt(0xFF0F2340);
  static const _slate = PdfColor.fromInt(0xFF5B6B82);

  // ---------------- bill ----------------

  static Future<Uint8List> billPdf({
    required ShopProfile shop,
    required ShopData data,
    required LaundryOrder o,
    bool roll = true,
  }) async {
    final cur = shop.currency;
    final c = data.customer(o.customerId);
    final b = data.branch(o.branchId);
    final doc = pw.Document(title: 'Bill ${o.code}', author: shop.shopName);
    pw.Widget row(String a, String v, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(a, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null))),
            pw.Text(v, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null)),
          ]),
        );
    doc.addPage(pw.Page(
      pageFormat: roll ? PdfPageFormat.roll80 : PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(14),
      build: (_) => pw.DefaultTextStyle(
        style: const pw.TextStyle(fontSize: 9),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text(shop.shopName, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _navy)),
          if ((b?.address ?? shop.address).isNotEmpty)
            pw.Text(b?.address.isNotEmpty == true ? b!.address : shop.address, textAlign: pw.TextAlign.center, style: const pw.TextStyle(color: _slate)),
          if ((b?.phone ?? '').isNotEmpty) pw.Text('Ph: ${b!.phone}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(color: _slate)),
          pw.SizedBox(height: 6),
          pw.Divider(thickness: .6),
          row('Bill', o.code, bold: true),
          row('Date', '${dmy(o.createdAt)} ${hm(o.createdAt)}'),
          row('Customer', c?.name ?? ''),
          row('Phone', '+${c?.phone ?? ''}'),
          row('Ready by', '${dmy(o.dueAt)} ${hm(o.dueAt)}'),
          if (o.rack.isNotEmpty) row('Rack', o.rack),
          pw.Divider(thickness: .6),
          for (final l in o.lines) ...[
            pw.Text('${l.garment} (${l.service})', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            row('  ${qtyText(l.qty, l.unit)} x ${_m(l.rate, cur)}', _m(l.amount, cur)),
            if (l.note.isNotEmpty) pw.Text('  Note: ${l.note}', style: const pw.TextStyle(color: _slate)),
          ],
          pw.Divider(thickness: .6),
          row('Subtotal', _m(o.subtotal, cur)),
          if (o.express) row('Express +${o.expressPct.toStringAsFixed(0)}%', _m(o.expressCharge, cur)),
          if (o.discount > 0) row('Discount', '-${_m(o.discount, cur)}'),
          if (o.couponAmount > 0) row('Coupon ${o.couponCode}', '-${_m(o.couponAmount, cur)}'),
          if (o.pointsUsed > 0) row('Loyalty points', '-${_m(o.pointsUsed, cur)}'),
          if (o.packageValue > 0) row('Package (${o.packageNote})', '-${_m(o.packageValue, cur)}'),
          if (o.tax > 0) row('GST ${o.taxPct.toStringAsFixed(0)}%', _m(o.tax, cur)),
          row('TOTAL', _m(o.total, cur), bold: true),
          row('Paid', _m(o.paid, cur)),
          row('Balance', _m(o.due, cur), bold: true),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: o.code, width: 60, height: 60)),
          pw.SizedBox(height: 6),
          pw.Text('${o.pieces} pieces. Please bring this bill when collecting.', textAlign: pw.TextAlign.center, style: const pw.TextStyle(color: _slate)),
          pw.Text('Thank you!', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('LaundryCase by BrotriX Technologies', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7, color: _slate)),
        ]),
      ),
    ));
    return doc.save();
  }

  // ---------------- tags ----------------

  /// One small label per piece with a QR code (order + piece number).
  static Future<Uint8List> tagsPdf({required ShopProfile shop, required ShopData data, required LaundryOrder o}) async {
    final c = data.customer(o.customerId);
    final doc = pw.Document(title: 'Tags ${o.code}');
    final pieces = <List<String>>[];
    var n = 0;
    final total = o.pieces;
    for (final l in o.lines) {
      for (var i = 0; i < l.pieces; i++) {
        n++;
        pieces.add(['${o.code} $n/$total', l.garment, l.service, l.note]);
      }
    }
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      build: (_) => [
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in pieces)
            pw.Container(
              width: 175,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _navy, width: 1), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Row(children: [
                pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: p[0], width: 46, height: 46),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(p[0], style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(c?.name ?? '', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('${p[1]} - ${p[2]}', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Due ${dmy(o.dueAt)}${o.express ? '  EXPRESS' : ''}', style: const pw.TextStyle(fontSize: 7, color: _slate)),
                    if (p[3].isNotEmpty) pw.Text(p[3], style: const pw.TextStyle(fontSize: 7, color: PdfColors.deepOrange)),
                  ]),
                ),
              ]),
            ),
        ]),
      ],
    ));
    return doc.save();
  }

  // ---------------- report ----------------

  static Future<Uint8List> reportPdf({
    required ShopProfile shop,
    required ShopData data,
    required Report r,
    required String periodLabel,
    String? branchId,
  }) async {
    final cur = shop.currency;
    final doc = pw.Document(title: 'Report $periodLabel', author: shop.shopName);
    pw.Widget table(String title, List<List<String>> rows) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(height: 10),
          pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _navy)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE6EEFC)),
            cellAlignments: {1: pw.Alignment.centerRight},
          ),
        ]);
    final stats = StaffStats.build(activity: data.activity, orders: data.orders, attendance: data.attendance, range: r.range);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Row(children: [
        pw.Text(shop.shopName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _navy)),
        pw.Spacer(),
        pw.Text('$periodLabel${branchId == null ? '' : ' - ${data.branch(branchId)?.name ?? ''}'}', style: const pw.TextStyle(color: _slate)),
      ]),
      footer: (ctx) => pw.Row(children: [
        pw.Text('LaundryCase by BrotriX Technologies', style: const pw.TextStyle(fontSize: 8, color: _slate)),
        pw.Spacer(),
        pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _slate)),
      ]),
      build: (_) => [
        table('Summary', [
          ['Item', 'Value'],
          ['Orders', '${r.orderCount} (${r.pieces} pcs)'],
          ['Sales (booked)', _m(r.sales, cur)],
          ['Collected', _m(r.collected, cur)],
          ['Average order', _m(r.avgOrder, cur)],
          ['Expenses', _m(r.expense, cur)],
          ['Profit (collected - expenses)', _m(r.profit, cur)],
          ['Pending dues (all time)', _m(r.pendingDues, cur)],
          ['Cancelled orders', '${r.cancelled}'],
        ]),
        table('Collection by mode', [
          ['Mode', 'Amount'],
          for (final m in payModes) [m.toUpperCase(), _m(r.byMode[m] ?? 0, cur)],
        ]),
        table('Services', [
          ['Service', 'Sales'],
          for (final e in r.top(r.services, 20)) [e.key, _m(e.value, cur)],
        ]),
        table('Top customers', [
          ['Customer', 'Sales'],
          for (final e in r.top(r.customerSpend, 10)) [data.customer(e.key)?.name ?? '-', _m(e.value, cur)],
        ]),
        if (data.branches.length > 1 && branchId == null)
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(height: 10),
            pw.Text('Branch comparison', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              data: [
                ['Branch', 'Orders', 'Sales', 'Collected', 'Expenses', 'Profit', 'Dues', 'Complaints'],
                for (final b in data.branches)
                  () {
                    final br = Report(orders: data.orders, expenses: data.expenses, range: r.range, branchId: b.id);
                    return [
                      b.name,
                      '${br.orderCount}',
                      _m(br.sales, cur),
                      _m(br.collected, cur),
                      _m(br.expense, cur),
                      _m(br.profit, cur),
                      _m(br.pendingDues, cur),
                      '${data.issues.where((i) => i.branchId == b.id && r.range.has(i.openedAt)).length}',
                    ];
                  }(),
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE6EEFC)),
            ),
          ]),
        table('Expenses', [
          ['Type', 'Amount'],
          for (final e in r.top(r.expenseByCat, 20)) [e.key, _m(e.value, cur)],
        ]),
        if (data.staff.isNotEmpty)
          table('Staff', [
            ['Name', 'Booked / Updates / Deliveries / Collected / Days'],
            for (final s in data.staff.where((s) => s.active && (branchId == null || s.branchId == branchId)))
              [
                '${s.name} (${s.role.name})',
                '${stats[s.id]?.ordersBooked ?? 0} / ${stats[s.id]?.statusUpdates ?? 0} / ${(stats[s.id]?.deliveries ?? 0) + (stats[s.id]?.pickups ?? 0)} / ${_m(stats[s.id]?.cashCollected ?? 0, cur)} / ${stats[s.id]?.daysPresent ?? 0}',
              ],
          ]),
      ],
    ));
    return doc.save();
  }

  // ---------------- CSV ----------------

  static String _csv(List<List<Object?>> rows) => rows
      .map((r) => r.map((v) {
            final s = '${v ?? ''}';
            return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
          }).join(','))
      .join('\n');

  static String ordersCsv(ShopData d, Iterable<LaundryOrder> orders) => _csv([
        ['Order', 'Date', 'Customer', 'Phone', 'Branch', 'Status', 'Pieces', 'Services', 'Total', 'Paid', 'Due', 'Express', 'Home delivery', 'Delivered by'],
        for (final o in orders)
          [
            o.code,
            o.createdAt.toIso8601String().substring(0, 16).replaceAll('T', ' '),
            d.customer(o.customerId)?.name,
            d.customer(o.customerId)?.phone,
            d.branch(o.branchId)?.name,
            o.status,
            o.pieces,
            o.lines.map((l) => l.service).toSet().join(' / '),
            o.total.toStringAsFixed(2),
            o.paid.toStringAsFixed(2),
            o.due.toStringAsFixed(2),
            o.express ? 'yes' : '',
            o.homeDelivery ? 'yes' : '',
            o.deliveryAgent.isEmpty ? '' : d.nameOf(o.deliveryAgent),
          ],
      ]);

  static String issuesCsv(ShopData d, Iterable<Issue> issues) => _csv([
        ['Issue', 'Type', 'Order', 'Customer', 'Branch', 'Reason', 'Pieces', 'Mistake by', 'Opened', 'Opened by', 'Closed', 'Hours', 'Re-opened', 'Compensation', 'Status'],
        for (final i in issues)
          [
            i.code,
            i.kind == 'wrong' ? 'Wrong delivery (${i.subKind})' : 'Complaint / re-wash',
            d.order(i.orderId)?.code,
            d.customer(i.customerId)?.name,
            d.branch(i.branchId)?.name,
            i.reason,
            i.pieces.join(' / '),
            i.fault.map((f) => f == 'none' ? 'Nobody' : d.nameOf(f)).join(' / '),
            i.openedAt.toIso8601String().substring(0, 16).replaceAll('T', ' '),
            d.nameOf(i.openedBy),
            i.closedAt?.toIso8601String().substring(0, 16).replaceAll('T', ' '),
            i.hoursOpen.toStringAsFixed(1),
            i.reopenCount,
            i.compensation.toStringAsFixed(2),
            i.closed ? 'closed' : i.stage,
          ],
      ]);

  static String payrollCsv(List<Payslip> slips) => _csv([
        ['Staff', 'Role', 'Month', 'Days', 'Orders', 'Sales', 'Pieces', 'Kg', 'Deliveries', 'Pickups', 'Collected', 'Complaints', 'Wrong deliveries', 'Salary', 'Incentive', 'Advances', 'Net', 'Paid', 'Balance'],
        for (final p in slips)
          [
            p.staff.name,
            p.staff.role.name,
            p.month,
            p.days,
            p.orders,
            p.sales.toStringAsFixed(2),
            p.pieces,
            p.kg,
            p.drops,
            p.pickups,
            p.collected.toStringAsFixed(2),
            p.complaints,
            p.wrongs,
            p.staff.salary.toStringAsFixed(2),
            p.incentive.toStringAsFixed(2),
            p.advances.toStringAsFixed(2),
            p.net.toStringAsFixed(2),
            p.paid.toStringAsFixed(2),
            p.balance.toStringAsFixed(2),
          ],
      ]);

  static Future<Uint8List> payslipPdf({required ShopProfile shop, required ShopData data, required Payslip p}) async {
    final cur = shop.currency;
    final doc = pw.Document(title: 'Salary slip ${p.staff.name} ${p.month}', author: shop.shopName);
    pw.Widget row(String a, String b, String v, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(a, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null)),
                if (b.isNotEmpty) pw.Text(b, style: const pw.TextStyle(fontSize: 8, color: _slate)),
              ]),
            ),
            pw.Text(v, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null)),
          ]),
        );
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(shop.shopName, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _navy)),
        pw.Text('Salary slip - ${p.month}', style: const pw.TextStyle(color: _slate)),
        pw.SizedBox(height: 10),
        row('Name', '', p.staff.name, bold: true),
        row('Role', '', p.staff.role.name),
        row('Branch', '', data.branch(p.staff.branchId)?.name ?? ''),
        row('Days present', '', '${p.days}'),
        pw.Divider(),
        for (final l in p.lines) row(l.label, l.calc, _m(l.amount, cur)),
        for (final x in p.payouts.where((x) => x.kind != 'paid'))
          row(x.kind == 'advance' ? 'Advance' : (x.kind == 'bonus' ? 'Extra bonus' : 'Deduction'), x.note, '${x.kind == 'bonus' ? '' : '-'}${_m(x.amount, cur)}'),
        pw.Divider(),
        row('Net pay', '', _m(p.net, cur), bold: true),
        row('Paid', '', _m(p.paid, cur)),
        row('Balance', '', _m(p.balance, cur), bold: true),
        pw.Spacer(),
        pw.Row(children: [
          pw.Text('Staff signature: ____________'),
          pw.Spacer(),
          pw.Text('Owner: ____________'),
        ]),
        pw.SizedBox(height: 8),
        pw.Text('LaundryCase by BrotriX Technologies', style: const pw.TextStyle(fontSize: 7, color: _slate)),
      ]),
    ));
    return doc.save();
  }

  static String branchCsv(ShopData d, DateRange range) => _csv([
        ['Branch', 'Address', 'Orders', 'Pieces', 'Sales', 'Collected', 'Expenses', 'Profit', 'Pending dues', 'Complaints', 'Wrong deliveries', 'Active staff'],
        for (final b in d.branches)
          () {
            final r = Report(orders: d.orders, expenses: d.expenses, range: range, branchId: b.id);
            return [
              b.name,
              b.address,
              r.orderCount,
              r.pieces,
              r.sales.toStringAsFixed(2),
              r.collected.toStringAsFixed(2),
              r.expense.toStringAsFixed(2),
              r.profit.toStringAsFixed(2),
              r.pendingDues.toStringAsFixed(2),
              d.issues.where((i) => i.branchId == b.id && i.kind == 'complaint' && range.has(i.openedAt)).length,
              d.issues.where((i) => i.branchId == b.id && i.kind != 'complaint' && range.has(i.openedAt)).length,
              d.staff.where((s) => s.active && s.branchId == b.id).length,
            ];
          }(),
      ]);

  static String customersCsv(ShopData d) => _csv([
        ['Name', 'Phone', 'Type', 'Address', 'Orders', 'Spent', 'Due'],
        for (final c in d.customers)
          [
            c.name,
            c.phone,
            c.type,
            c.address,
            d.orders.where((o) => o.customerId == c.id).length,
            d.orders.where((o) => o.customerId == c.id && o.status != 'cancelled').fold<double>(0, (s, o) => s + o.total).toStringAsFixed(2),
            d.dueOf(c.id).toStringAsFixed(2),
          ],
      ]);

  // ---------------- actions ----------------

  /// WhatsApp booking link for customers (free – opens a chat with the shop).
  static String bookingLink(String shopName, String phone) {
    var p = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.length == 10) p = '91$p';
    final msg = 'Namaste $shopName, please pick up my clothes.\nName: \nAddress: \nBest time: ';
    return 'https://wa.me/$p?text=${Uri.encodeComponent(msg)}';
  }

  /// A4 poster with the booking QR, to stick at the counter / share.
  static Future<Uint8List> bookingPosterPdf({required ShopProfile shop, required String link, String branchName = '', String phone = ''}) async {
    final doc = pw.Document(title: 'Book pickup - ${shop.shopName}');
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.SizedBox(height: 20),
        pw.Text(shop.shopName, style: pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold, color: _navy), textAlign: pw.TextAlign.center),
        if (branchName.isNotEmpty) pw.Text(branchName, style: const pw.TextStyle(fontSize: 16, color: _slate)),
        pw.SizedBox(height: 24),
        pw.Text('Book a FREE pickup on WhatsApp', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Text('Scan the code with your phone camera', style: const pw.TextStyle(fontSize: 14, color: _slate)),
        pw.SizedBox(height: 24),
        pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: link, width: 300, height: 300),
        pw.SizedBox(height: 24),
        if (phone.isNotEmpty) pw.Text('Or call / WhatsApp: +${phone.length == 10 ? '91$phone' : phone}', style: const pw.TextStyle(fontSize: 16)),
        pw.Spacer(),
        pw.Text('Wash & fold  -  Dry clean  -  Steam iron  -  Home pickup & delivery', style: const pw.TextStyle(fontSize: 12, color: _slate)),
        pw.SizedBox(height: 6),
        pw.Text('LaundryCase by BrotriX Technologies', style: const pw.TextStyle(fontSize: 9, color: _slate)),
      ]),
    ));
    return doc.save();
  }

  static Future<void> printPdf(Uint8List bytes, String name) => Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  static Future<void> sharePdf(Uint8List bytes, String file) => Printing.sharePdf(bytes: bytes, filename: file);

  static Future<void> shareCsv(String csv, String file) => Share.shareXFiles(
        [XFile.fromData(Uint8List.fromList(utf8.encode(csv)), name: file, mimeType: 'text/csv')],
        subject: file,
      );
}
