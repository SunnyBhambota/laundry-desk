import 'dart:convert';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ops_models.dart';
import '../data/shop_data.dart';
import '../models/models.dart';
import '../widgets/ui.dart' show money, qtyText, dmy, hm;

/// Small ESC/POS builder (text, bold, centre, QR, cut) — enough for bills and tags.
class Esc {
  final List<int> b = [0x1B, 0x40]; // init
  final int width; // characters per line (32 for 58 mm, 48 for 80 mm)
  Esc(this.width);

  static List<int> _ascii(String s) =>
      latin1.encode(s.replaceAll('₹', 'Rs ').replaceAll('×', 'x').replaceAll('–', '-').replaceAll('·', '-').replaceAll(RegExp(r'[^\x00-\xFF]'), '?'));

  void align(int a) => b.addAll([0x1B, 0x61, a]); // 0 left, 1 centre, 2 right
  void bold(bool on) => b.addAll([0x1B, 0x45, on ? 1 : 0]);
  void size(int n) => b.addAll([0x1D, 0x21, n == 2 ? 0x11 : 0x00]);
  void text(String s) => b
    ..addAll(_ascii(s))
    ..add(0x0A);
  void line() => text('-' * width);
  void feed(int n) => b.addAll([0x1B, 0x64, n]);
  void cut() => b.addAll([0x1D, 0x56, 0x42, 0x00]);

  /// Left text and right text on one line.
  void lr(String l, String r) {
    final space = width - l.length - r.length;
    if (space >= 1) {
      text('$l${' ' * space}$r');
    } else {
      text(l);
      align(2);
      text(r);
      align(0);
    }
  }

  /// Native QR (GS ( k), size 1..16.
  void qr(String data, {int size = 6}) {
    final d = utf8.encode(data);
    final len = d.length + 3;
    b.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]); // model 2
    b.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size]); // size
    b.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]); // error M
    b.addAll([0x1D, 0x28, 0x6B, len % 256, len ~/ 256, 0x31, 0x50, 0x30, ...d]);
    b.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]); // print
    b.add(0x0A);
  }
}

class ThermalPrinter {
  ThermalPrinter._();
  static final ThermalPrinter instance = ThermalPrinter._();

  static const _kMac = 'ld_printer_mac', _kName = 'ld_printer_name', _kWidth = 'ld_printer_w';
  static const _kAuto = 'ld_printer_auto', _kTags = 'ld_printer_tags';

  String mac = '';
  String name = '';
  int width = 32;
  bool autoBill = false;
  bool autoTags = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mac = p.getString(_kMac) ?? '';
    name = p.getString(_kName) ?? '';
    width = p.getInt(_kWidth) ?? 32;
    autoBill = p.getBool(_kAuto) ?? false;
    autoTags = p.getBool(_kTags) ?? false;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMac, mac);
    await p.setString(_kName, name);
    await p.setInt(_kWidth, width);
    await p.setBool(_kAuto, autoBill);
    await p.setBool(_kTags, autoTags);
  }

  Future<bool> permissions() async {
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    return r.values.every((s) => s.isGranted || s.isLimited) || (await PrintBluetoothThermal.isPermissionBluetoothGranted);
  }

  Future<List<BluetoothInfo>> paired() async {
    await permissions();
    if (!await PrintBluetoothThermal.bluetoothEnabled) return [];
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<bool> _connect() async {
    if (mac.isEmpty) return false;
    if (await PrintBluetoothThermal.connectionStatus) return true;
    return PrintBluetoothThermal.connect(macPrinterAddress: mac);
  }

  /// Returns null if printed, else an error text.
  Future<String?> send(List<int> bytes) async {
    try {
      await permissions();
      if (mac.isEmpty) return 'No printer chosen. More → Printer.';
      if (!await PrintBluetoothThermal.bluetoothEnabled) return 'Bluetooth is off.';
      if (!await _connect()) return 'Could not connect to $name.';
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      return ok ? null : 'Printer did not accept the data.';
    } catch (e) {
      return 'Printer error: $e';
    }
  }

  List<int> billBytes({required ShopProfile shop, required ShopData d, required LaundryOrder o}) {
    final cur = shop.currency;
    final c = d.customer(o.customerId);
    final e = Esc(width)
      ..align(1)
      ..bold(true)
      ..size(2)
      ..text(shop.shopName.toUpperCase())
      ..size(1)
      ..bold(false);
    final br = d.branch(o.branchId);
    if ((br?.address ?? shop.address).isNotEmpty) e.text(br?.address.isNotEmpty == true ? br!.address : shop.address);
    e
      ..align(0)
      ..line()
      ..lr('Bill: ${o.code}', '${dmy(o.createdAt)} ${hm(o.createdAt)}')
      ..text('${c?.name ?? 'Customer'}  +${c?.phone ?? ''}')
      ..line();
    for (final l in o.lines) {
      e.lr('${l.garment} ${qtyText(l.qty, l.unit)}', money(l.amount, cur));
      e.text('  ${l.service}${l.note.isEmpty ? '' : ' - ${l.note}'}');
    }
    e.line();
    if (o.express) e.lr('Express', money(o.expressCharge, cur));
    if (o.discount > 0) e.lr('Discount', '-${money(o.discount, cur)}');
    if (o.tax > 0) e.lr('GST ${o.taxPct.toStringAsFixed(0)}%', money(o.tax, cur));
    e
      ..bold(true)
      ..lr('TOTAL', money(o.total, cur))
      ..bold(false)
      ..lr('Paid', money(o.paid, cur))
      ..lr('Balance', money(o.due, cur))
      ..text('Ready by: ${dmy(o.dueAt)} ${hm(o.dueAt)}')
      ..text('Pieces: ${o.pieces}${o.rack.isEmpty ? '' : '  Rack: ${o.rack}'}');
    final upi = d.upiLink(o, shop.shopName);
    e.align(1);
    if (upi != null) {
      e
        ..qr(upi, size: 6)
        ..bold(true)
        ..text('Scan & pay ${money(o.due, cur)} (UPI)')
        ..bold(false);
    } else {
      e.qr(o.code, size: 5);
    }
    e
      ..text('Thank you!')
      ..text('Laundry Desk')
      ..feed(3)
      ..cut();
    return e.b;
  }

  List<int> tagBytes({required ShopData d, required LaundryOrder o}) {
    final c = d.customer(o.customerId);
    final e = Esc(width);
    var n = 0;
    for (final l in o.lines) {
      for (var k = 0; k < l.pieces; k++) {
        n++;
        final code = '${o.code} $n/${o.pieces}';
        e
          ..align(1)
          ..bold(true)
          ..text(code)
          ..bold(false)
          ..qr(code, size: 4)
          ..text('${c?.name ?? ''} - ${l.garment}')
          ..text('${l.service}  Due ${dmy(o.dueAt)}${o.express ? ' EXPRESS' : ''}');
        if (l.note.isNotEmpty) e.text(l.note);
        e
          ..line()
          ..feed(1);
      }
    }
    e
      ..feed(2)
      ..cut();
    return e.b;
  }
}
