import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import 'ops_models.dart';
import 'rate_card.dart';

/// Everything a shop works with, saved on the phone (and to Firestore in cloud mode).
class ShopData extends ChangeNotifier {
  ShopData(this.ownerUid);

  final String ownerUid;

  String shopCode = '';
  int nextNumber = 1;
  double taxPct = 0;
  double expressPct = 50;
  int dueDays = 2;
  String plan = 'trial'; // trial | free | pro | business
  DateTime? planUntil;
  Set<String> disabledModules = {};
  bool hasSample = false;

  List<Branch> branches = [];
  List<Customer> customers = [];
  List<Garment> garments = [];
  Map<String, double> rates = {};
  List<LaundryOrder> orders = [];
  List<Staff> staff = [];
  List<Attendance> attendance = [];
  List<Expense> expenses = [];
  List<Activity> activity = [];
  /// Delivery staff GPS trail: staffId → points (last 200 each).
  Map<String, List<Ping>> pings = {};
  /// Owner app-lock PIN (salted hash, empty = off).
  String lockHash = '';

  static String _key(String uid) => 'ld_data_$uid';
  static const _kIndex = 'ld_shop_index';

  Timer? _saveTimer;
  final _rnd = Random();

  String newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';

  // ---------------- load / save ----------------

  static Future<ShopData> open(String ownerUid) async {
    final d = ShopData(ownerUid);
    final p = await SharedPreferences.getInstance();
    var raw = p.getString(_key(ownerUid));
    if (raw == null && AuthService.instance.cloud && !ownerUid.startsWith('local_')) {
      try {
        final doc = await FirebaseFirestore.instance.collection('shopData').doc(ownerUid).get();
        if (doc.exists) raw = doc.data()?['json'] as String?;
      } catch (_) {}
    }
    if (raw != null) {
      try {
        d._fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    return d;
  }

  bool get initialised => branches.isNotEmpty;

  /// First run after Business setup.
  Future<void> initialise(ShopProfile shop, {bool sample = false}) async {
    shopCode = _code();
    taxPct = shop.gst ? 18 : 0;
    branches = [Branch(id: 'b_main', name: shop.address.isEmpty ? 'Main branch' : shop.address.split(',').first.trim())];
    garments = DefaultRates.garments.map((g) => Garment.fromJson(g.toJson())).toList();
    rates = DefaultRates.defaultRates(shop.services, currencyFactor: DefaultRates.currencyFactor[shop.currency] ?? 1);
    await _registerIndex();
    if (sample) {
      // filled by SampleData (kept out of here to keep this file short)
      hasSample = true;
    }
    save(now: true);
  }

  String _code() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  Future<void> _registerIndex() async {
    final p = await SharedPreferences.getInstance();
    final m = Map<String, dynamic>.from(jsonDecode(p.getString(_kIndex) ?? '{}') as Map);
    m[shopCode] = ownerUid;
    await p.setString(_kIndex, jsonEncode(m));
    if (AuthService.instance.cloud && !ownerUid.startsWith('local_')) {
      try {
        await FirebaseFirestore.instance.collection('shopCodes').doc(shopCode).set({'ownerUid': ownerUid});
      } catch (_) {}
    }
  }

  /// Staff login: shop code → owner uid (this phone first, then cloud).
  static Future<String?> ownerForCode(String code) async {
    final c = code.trim().toUpperCase();
    final p = await SharedPreferences.getInstance();
    final m = Map<String, dynamic>.from(jsonDecode(p.getString(_kIndex) ?? '{}') as Map);
    if (m[c] is String) return m[c] as String;
    if (AuthService.instance.cloud) {
      try {
        final doc = await FirebaseFirestore.instance.collection('shopCodes').doc(c).get();
        return doc.data()?['ownerUid'] as String?;
      } catch (_) {}
    }
    return null;
  }

  void changed() {
    notifyListeners();
    save();
  }

  void save({bool now = false}) {
    _saveTimer?.cancel();
    if (now) {
      _write();
    } else {
      _saveTimer = Timer(const Duration(milliseconds: 400), _write);
    }
  }

  Future<void> _write() async {
    final raw = jsonEncode(toJson());
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(ownerUid), raw);
    if (AuthService.instance.cloud && !ownerUid.startsWith('local_')) {
      try {
        await FirebaseFirestore.instance
            .collection('shopData')
            .doc(ownerUid)
            .set({'json': raw, 'updatedAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'shopCode': shopCode,
        'nextNumber': nextNumber,
        'taxPct': taxPct,
        'expressPct': expressPct,
        'dueDays': dueDays,
        'plan': plan,
        'planUntil': planUntil?.toIso8601String(),
        'disabledModules': disabledModules.toList(),
        'hasSample': hasSample,
        'branches': branches.map((e) => e.toJson()).toList(),
        'customers': customers.map((e) => e.toJson()).toList(),
        'garments': garments.map((e) => e.toJson()).toList(),
        'rates': rates,
        'orders': orders.map((e) => e.toJson()).toList(),
        'staff': staff.map((e) => e.toJson()).toList(),
        'attendance': attendance.map((e) => e.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
        'activity': activity.map((e) => e.toJson()).toList(),
        'pings': pings.map((k, v) => MapEntry(k, v.map((p) => p.toJson()).toList())),
        'lockHash': lockHash,
      };

  void _fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) =>
        ((j[k] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    shopCode = j['shopCode'] as String? ?? '';
    nextNumber = (j['nextNumber'] as num?)?.toInt() ?? 1;
    taxPct = (j['taxPct'] as num?)?.toDouble() ?? 0;
    expressPct = (j['expressPct'] as num?)?.toDouble() ?? 50;
    dueDays = (j['dueDays'] as num?)?.toInt() ?? 2;
    plan = j['plan'] as String? ?? 'trial';
    planUntil = DateTime.tryParse(j['planUntil'] as String? ?? '');
    disabledModules = ((j['disabledModules'] as List?) ?? []).map((e) => '$e').toSet();
    hasSample = j['hasSample'] as bool? ?? false;
    branches = list('branches').map(Branch.fromJson).toList();
    customers = list('customers').map(Customer.fromJson).toList();
    garments = list('garments').map(Garment.fromJson).toList();
    rates = Map<String, dynamic>.from(j['rates'] as Map? ?? {}).map((k, v) => MapEntry(k, (v as num).toDouble()));
    orders = list('orders').map(LaundryOrder.fromJson).toList();
    staff = list('staff').map(Staff.fromJson).toList();
    attendance = list('attendance').map(Attendance.fromJson).toList();
    expenses = list('expenses').map(Expense.fromJson).toList();
    activity = list('activity').map(Activity.fromJson).toList();
    pings = Map<String, dynamic>.from(j['pings'] as Map? ?? {}).map((k, v) => MapEntry(
        k, (v as List).map((e) => Ping.fromJson(Map<String, dynamic>.from(e as Map))).toList()));
    lockHash = j['lockHash'] as String? ?? '';
  }

  // ---------------- plan & modules ----------------

  bool premiumActive(ShopProfile shop) {
    if (!AppConfig.enforcePremium) return true;
    if ((plan == 'pro' || plan == 'business') && planUntil != null && planUntil!.isAfter(DateTime.now())) return true;
    return shop.trialDaysLeft(AppConfig.trialDays) > 0;
  }

  bool moduleOn(String m, ShopProfile shop) {
    if (disabledModules.contains(m)) return false;
    if (AppConfig.freeModules.contains(m)) return true;
    return premiumActive(shop);
  }

  void setModule(String m, bool on) {
    on ? disabledModules.remove(m) : disabledModules.add(m);
    changed();
  }

  void setPlan(String p, {int months = 1}) {
    plan = p;
    planUntil = p == 'free' ? null : DateTime.now().add(Duration(days: 30 * months));
    changed();
  }

  // ---------------- lookups ----------------

  Customer? customer(String id) => customers.where((c) => c.id == id).firstOrNull;
  Staff? staffBy(String id) => staff.where((s) => s.id == id).firstOrNull;
  Branch? branch(String id) => branches.where((b) => b.id == id).firstOrNull;
  LaundryOrder? order(String id) => orders.where((o) => o.id == id).firstOrNull;
  Garment? garment(String id) => garments.where((g) => g.id == id).firstOrNull;
  double? rate(String garmentId, String service) => rates['$garmentId|$service'];

  String nameOf(String by) {
    if (by.isEmpty || by == 'owner') return 'Owner';
    return staffBy(by)?.name ?? 'Staff';
  }

  Iterable<LaundryOrder> ordersIn(String? branchId) =>
      branchId == null ? orders : orders.where((o) => o.branchId == branchId);

  List<LaundryOrder> ordersOf(String customerId) =>
      orders.where((o) => o.customerId == customerId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  double dueOf(String customerId) =>
      orders.where((o) => o.customerId == customerId && o.status != 'cancelled').fold(0, (s, o) => s + o.due);

  Attendance? todayAttendance(String staffId) {
    final k = dayKey(DateTime.now());
    return attendance.where((a) => a.staffId == staffId && a.day == k).firstOrNull;
  }

  int actionsToday(String by) {
    final k = dayKey(DateTime.now());
    return activity.where((a) => a.by == by && dayKey(a.at) == k && !a.kind.startsWith('check')).length;
  }

  // ---------------- actions ----------------

  void log(String by, String kind, {String orderId = '', String text = ''}) {
    activity.add(Activity(by: by, kind: kind, at: DateTime.now(), orderId: orderId, text: text));
    if (activity.length > 3000) activity.removeRange(0, activity.length - 3000);
  }

  Customer addCustomer({required String name, required String phone, String address = '', String type = 'regular'}) {
    final c = Customer(id: newId('c'), name: name.trim(), phone: phone.replaceAll(RegExp(r'[^0-9]'), ''), address: address.trim(), type: type);
    customers.add(c);
    changed();
    return c;
  }

  void updateCustomer(Customer c) => changed();

  LaundryOrder createOrder({
    required String customerId,
    required String branchId,
    required List<OrderLine> lines,
    required String by,
    bool express = false,
    bool homeDelivery = false,
    bool pickup = false,
    double discount = 0,
    DateTime? dueAt,
    double advance = 0,
    String advanceMode = 'cash',
    String notes = '',
    String pickupAgent = '',
  }) {
    final now = DateTime.now();
    final status = pickup ? 'pickup' : 'received';
    final o = LaundryOrder(
      id: newId('o'),
      number: nextNumber++,
      customerId: customerId,
      branchId: branchId,
      lines: lines,
      createdAt: now,
      dueAt: dueAt ?? now.add(Duration(days: express ? 1 : dueDays)),
      status: status,
      express: express,
      homeDelivery: homeDelivery || pickup,
      discount: discount,
      taxPct: taxPct,
      expressPct: expressPct,
      notes: notes,
      createdBy: by,
      pickupAgent: pickupAgent,
      history: [StatusEvent(status: status, at: now, by: by)],
    );
    if (advance > 0) o.payments.add(Payment(amount: advance, mode: advanceMode, at: now, by: by, note: 'advance'));
    orders.add(o);
    log(by, 'order.new', orderId: o.id, text: o.code);
    if (advance > 0) log(by, 'pay', orderId: o.id, text: advance.toStringAsFixed(0));
    changed();
    return o;
  }

  void setStatus(LaundryOrder o, String status, {required String by, String note = ''}) {
    o.status = status;
    o.history.add(StatusEvent(status: status, at: DateTime.now(), by: by, note: note));
    log(by, status == 'delivered' && o.homeDelivery ? 'delivery.done' : (status == 'received' && o.timeOf('pickup') != null ? 'pickup.done' : 'status.$status'),
        orderId: o.id, text: o.code);
    changed();
  }

  void addPayment(LaundryOrder o, double amount, String mode, {required String by, String note = ''}) {
    if (amount <= 0) return;
    o.payments.add(Payment(amount: amount, mode: mode, at: DateTime.now(), by: by, note: note));
    log(by, 'pay', orderId: o.id, text: amount.toStringAsFixed(0));
    changed();
  }

  void assign(LaundryOrder o, {String? pickupAgent, String? deliveryAgent, required String by}) {
    if (pickupAgent != null) o.pickupAgent = pickupAgent;
    if (deliveryAgent != null) o.deliveryAgent = deliveryAgent;
    log(by, 'assign', orderId: o.id, text: o.code);
    changed();
  }

  void checkIn(String staffId) {
    if (todayAttendance(staffId) != null) return;
    attendance.add(Attendance(staffId: staffId, day: dayKey(DateTime.now()), inAt: DateTime.now()));
    log(staffId, 'checkin');
    changed();
  }

  void checkOut(String staffId) {
    final a = todayAttendance(staffId);
    if (a == null || a.outAt != null) return;
    a.outAt = DateTime.now();
    log(staffId, 'checkout');
    changed();
  }

  Staff addStaff({required String name, required String phone, required Role role, required String branchId, required String pin, double salary = 0}) {
    final s = Staff(id: newId('s'), name: name.trim(), phone: phone.replaceAll(RegExp(r'[^0-9]'), ''), role: role, branchId: branchId, pin: pin, salary: salary);
    staff.add(s);
    changed();
    return s;
  }

  Branch addBranch(String name, {String address = '', String phone = ''}) {
    final b = Branch(id: newId('b'), name: name.trim(), address: address.trim(), phone: phone.trim());
    branches.add(b);
    changed();
    return b;
  }

  Expense addExpense({required String branchId, required String category, required double amount, String note = '', DateTime? at}) {
    final e = Expense(id: newId('e'), branchId: branchId, category: category, amount: amount, at: at ?? DateTime.now(), note: note);
    expenses.add(e);
    changed();
    return e;
  }

  void setRate(String garmentId, String service, double? price) {
    if (price == null) {
      rates.remove('$garmentId|$service');
    } else {
      rates['$garmentId|$service'] = price;
    }
    changed();
  }

  Garment addGarment(String name, {String unit = 'pc', String category = 'Other'}) {
    final g = Garment(id: newId('g'), name: name.trim(), unit: unit, category: category);
    garments.add(g);
    changed();
    return g;
  }

  void addPing(String staffId, Ping p) {
    final l = pings.putIfAbsent(staffId, () => []);
    l.add(p);
    if (l.length > 200) l.removeRange(0, l.length - 200);
    changed();
  }

  Ping? lastPing(String staffId) {
    final l = pings[staffId];
    return (l == null || l.isEmpty) ? null : l.last;
  }

  /// Removes sample customers/orders/staff/expenses (keeps setup, rate card, branches you added).
  void clearSample() {
    customers.removeWhere((c) => c.id.startsWith('demo_'));
    orders.removeWhere((o) => o.id.startsWith('demo_'));
    staff.removeWhere((s) => s.id.startsWith('demo_'));
    expenses.removeWhere((e) => e.id.startsWith('demo_'));
    branches.removeWhere((b) => b.id.startsWith('demo_'));
    attendance.removeWhere((a) => a.staffId.startsWith('demo_'));
    activity.removeWhere((a) => a.by.startsWith('demo_') || a.orderId.startsWith('demo_'));
    pings.removeWhere((k, _) => k.startsWith('demo_'));
    hasSample = false;
    if (orders.isEmpty) nextNumber = 1;
    changed();
  }
}
