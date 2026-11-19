import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import 'cloud_sync.dart';
import 'issue_models.dart';
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
  List<Issue> issues = [];
  List<Payout> payouts = [];
  List<Coupon> coupons = [];
  List<PackagePlan> packagePlans = [];
  List<StockItem> stock = [];
  List<StockMove> stockMoves = [];
  List<Supplier> suppliers = [];
  /// Loyalty: points per ₹100, value of 1 point, minimum points to redeem (0 per100 = off).
  double pointsPer100 = 1;
  double pointValue = 1;
  double minRedeem = 50;
  /// Delivery staff GPS trail: staffId → points (last 200 each).
  Map<String, List<Ping>> pings = {};
  /// Owner app-lock PIN (salted hash, empty = off).
  String lockHash = '';
  /// Commission / incentive rules (see logic/payroll.dart).
  Map<String, dynamic> rules = {};
  /// Discount % by customer type (price lists), e.g. {'vip': 10, 'business': 20}.
  Map<String, double> typeDiscount = {'vip': 10, 'business': 20};
  /// Shop UPI ID for QR on bills (e.g. shop@okhdfc).
  String upiId = '';

  static String _key(String uid) => 'ld_data_$uid';
  static const _kIndex = 'ld_shop_index';

  Timer? _saveTimer;
  final _rnd = Random();

  String newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';

  // ---------------- load / save ----------------

  bool get cloudOn => AuthService.instance.cloud && !ownerUid.startsWith('local_');
  CloudSync? sync;

  /// [admin] false for staff phones (they cannot write settings/staff/branches/rates/expenses).
  static Future<ShopData> open(String ownerUid, {bool admin = true}) async {
    final d = ShopData(ownerUid);
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(ownerUid));
    if (raw != null) {
      try {
        d._fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    if (d.cloudOn) {
      final cs = CloudSync(d)..admin = admin;
      d.sync = cs;
      try {
        final has = await cs.pull();
        if (!has && admin && d.initialised) {
          // first time online with data made on this phone: upload it
          await cs.push();
        }
        d._saveLocal();
      } catch (e) {
        // offline: keep the phone copy, sync later
        cs.lastError = 'read: $e';
      }
      cs.listen();
    }
    return d;
  }

  /// Called by CloudSync when another phone changed something.
  void remoteChanged() {
    notifyListeners();
    _saveLocal();
  }

  Map<String, dynamic> settingsJson() => {
        'shopCode': shopCode,
        'taxPct': taxPct,
        'expressPct': expressPct,
        'dueDays': dueDays,
        'plan': plan,
        'planUntil': planUntil?.toIso8601String(),
        'disabledModules': disabledModules.toList()..sort(),
        'hasSample': hasSample,
        'rates': rates,
        'lockHash': lockHash,
        'rules': rules,
        'typeDiscount': typeDiscount,
        'upiId': upiId,
        'loyalty': {'per100': pointsPer100, 'value': pointValue, 'min': minRedeem},
      };

  void applySettings(Map<String, dynamic> j) {
    shopCode = j['shopCode'] as String? ?? shopCode;
    taxPct = (j['taxPct'] as num?)?.toDouble() ?? taxPct;
    expressPct = (j['expressPct'] as num?)?.toDouble() ?? expressPct;
    dueDays = (j['dueDays'] as num?)?.toInt() ?? dueDays;
    plan = j['plan'] as String? ?? plan;
    planUntil = DateTime.tryParse(j['planUntil'] as String? ?? '');
    disabledModules = ((j['disabledModules'] as List?) ?? []).map((e) => '$e').toSet();
    hasSample = j['hasSample'] as bool? ?? hasSample;
    rates = Map<String, dynamic>.from(j['rates'] as Map? ?? {}).map((k, v) => MapEntry(k, (v as num).toDouble()));
    lockHash = j['lockHash'] as String? ?? '';
    if (j['rules'] is Map) rules = Map<String, dynamic>.from(j['rules'] as Map);
    if (j['typeDiscount'] is Map) {
      typeDiscount = Map<String, dynamic>.from(j['typeDiscount'] as Map).map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    upiId = j['upiId'] as String? ?? upiId;
    _loyalty(j['loyalty']);
  }

  void _loyalty(Object? l) {
    if (l is! Map) return;
    pointsPer100 = (l['per100'] as num?)?.toDouble() ?? pointsPer100;
    pointValue = (l['value'] as num?)?.toDouble() ?? pointValue;
    minRedeem = (l['min'] as num?)?.toDouble() ?? minRedeem;
  }

  /// Staff PIN hash (same formula in Firestore rules check via staffKeys).
  static String staffKey(String code, String phone, String pin) =>
      sha256.convert(utf8.encode('${code.toUpperCase()}:${phone10(phone)}:$pin')).toString();

  Staff? verifyStaff(String phone, String pin) {
    final p10 = phone10(phone);
    final key = staffKey(shopCode, p10, pin);
    for (final s in staff) {
      if (!s.active || phone10(s.phone) != p10) continue;
      if (s.pinHash == key || s.pinHash == 'plain:$pin') return s;
    }
    return null;
  }

  void setStaffPin(Staff s, String pin) {
    s.pinHash = staffKey(shopCode, s.phone, pin);
    changed();
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
    await _saveLocal();
    await sync?.push();
  }

  /// Saves anything still waiting (used before logout).
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await _write().timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> _saveLocal() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(ownerUid), jsonEncode(toJson()));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    sync?.stop();
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
        'rules': rules,
        'typeDiscount': typeDiscount,
        'upiId': upiId,
        'loyalty': {'per100': pointsPer100, 'value': pointValue, 'min': minRedeem},
        'coupons': coupons.map((e) => e.toJson()).toList(),
        'packagePlans': packagePlans.map((e) => e.toJson()).toList(),
        'stock': stock.map((e) => e.toJson()).toList(),
        'stockMoves': stockMoves.map((e) => e.toJson()).toList(),
        'suppliers': suppliers.map((e) => e.toJson()).toList(),
        'issues': issues.map((e) => e.toJson()).toList(),
        'payouts': payouts.map((e) => e.toJson()).toList(),
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
    if (j['rules'] is Map) rules = Map<String, dynamic>.from(j['rules'] as Map);
    if (j['typeDiscount'] is Map) {
      typeDiscount = Map<String, dynamic>.from(j['typeDiscount'] as Map).map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    upiId = j['upiId'] as String? ?? '';
    _loyalty(j['loyalty']);
    coupons = list('coupons').map(Coupon.fromJson).toList();
    packagePlans = list('packagePlans').map(PackagePlan.fromJson).toList();
    stock = list('stock').map(StockItem.fromJson).toList();
    stockMoves = list('stockMoves').map(StockMove.fromJson).toList();
    suppliers = list('suppliers').map(Supplier.fromJson).toList();
    issues = list('issues').map(Issue.fromJson).toList();
    payouts = list('payouts').map(Payout.fromJson).toList();
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

  /// Delivery people for a branch (own branch first, then others if the branch has none).
  List<Staff> agentsFor(String branchId) {
    final all = staff.where((s) => s.active && s.role == Role.delivery).toList();
    final mine = all.where((s) => s.branchId == branchId).toList();
    return mine.isNotEmpty ? mine : all;
  }
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
    String couponCode = '',
    double couponAmount = 0,
    double pointsUsed = 0,
    CustPackage? package,
    double packageQty = 0,
    double packageValue = 0,
    String slot = '',
    DateTime? pickupAt,
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
      couponCode: couponCode,
      couponAmount: couponAmount,
      pointsUsed: pointsUsed,
      packageValue: packageValue,
      packageNote: package == null ? '' : '${package.name}: ${packageQty.toStringAsFixed(1)} ${package.unit}',
      slot: slot,
      pickupAt: pickupAt,
      history: [StatusEvent(status: status, at: now, by: by)],
    );
    final cust = customer(customerId);
    if (cust != null) {
      if (pointsUsed > 0 && pointValue > 0) cust.points = (cust.points - pointsUsed / pointValue).clamp(0, double.infinity).toDouble();
      if (package != null && packageQty > 0) package.remaining = (package.remaining - packageQty).clamp(0, double.infinity).toDouble();
    }
    if (advance > 0) o.payments.add(Payment(amount: advance, mode: advanceMode, at: now, by: by, note: 'advance'));
    orders.add(o);
    log(by, 'order.new', orderId: o.id, text: o.code);
    if (advance > 0) log(by, 'pay', orderId: o.id, text: advance.toStringAsFixed(0));
    changed();
    return o;
  }

  void setStatus(LaundryOrder o, String status, {required String by, String note = ''}) {
    if (status == 'delivered' && o.status != 'delivered' && pointsPer100 > 0) {
      final c = customer(o.customerId);
      final earn = (o.total / 100).floorToDouble() * pointsPer100;
      if (c != null && earn > 0) c.points += earn;
    }
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
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final s = Staff(id: newId('s'), name: name.trim(), phone: digits, role: role, branchId: branchId, pinHash: staffKey(shopCode, digits, pin), salary: salary);
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

  // ---------------- v0.3: price lists, edit, refund, delete, UPI ----------------

  /// Rate for this customer (VIP / business discount applied).
  double? rateFor(String garmentId, String service, Customer? c) {
    final r = rate(garmentId, service);
    if (r == null) return null;
    final pct = c == null ? 0.0 : (typeDiscount[c.type] ?? 0);
    return (r * (100 - pct) / 100 * 100).roundToDouble() / 100;
  }

  void editOrder(LaundryOrder o, List<OrderLine> lines, {required String by, double? discount, bool? express}) {
    final before = o.total;
    o.lines = lines;
    if (discount != null) o.discount = discount;
    if (express != null) o.express = express;
    o.history.add(StatusEvent(status: 'edited', at: DateTime.now(), by: by, note: 'Total ${before.toStringAsFixed(0)} → ${o.total.toStringAsFixed(0)}'));
    log(by, 'order.edit', orderId: o.id, text: o.code);
    changed();
  }

  /// Money given back to the customer (a negative payment, so reports stay right).
  void refund(LaundryOrder o, double amount, String mode, {required String by, String note = ''}) {
    if (amount <= 0) return;
    o.payments.add(Payment(amount: -amount, mode: mode, at: DateTime.now(), by: by, note: note.isEmpty ? 'refund' : 'refund: $note'));
    o.history.add(StatusEvent(status: 'refund', at: DateTime.now(), by: by, note: amount.toStringAsFixed(0)));
    log(by, 'refund', orderId: o.id, text: amount.toStringAsFixed(0));
    changed();
  }

  // ---------------- v0.4: offers, packages, stock, locations ----------------

  Coupon? couponByCode(String code) => coupons.where((c) => c.code.toUpperCase() == code.trim().toUpperCase()).firstOrNull;

  /// Discount from a coupon for this customer and amount (0 if not valid).
  double couponDiscount(String code, Customer? c, double amount) {
    final cp = couponByCode(code);
    if (cp == null || !cp.valid) return 0;
    if (cp.onlyNew && c != null && orders.any((o) => o.customerId == c.id && o.status != 'cancelled')) return 0;
    return cp.discountOn(amount);
  }

  int couponUses(String code) => orders.where((o) => o.couponCode.toUpperCase() == code.toUpperCase() && o.status != 'cancelled').length;

  /// Points money a customer can use now.
  double pointsMoney(Customer? c) => (c == null || c.points < minRedeem) ? 0 : (c.points * pointValue).floorToDouble();

  /// Sell a package: recorded as a paid order so it shows in sales.
  LaundryOrder sellPackage(Customer c, PackagePlan plan, {required String by, required String branchId, String mode = 'cash'}) {
    final now = DateTime.now();
    c.packages.add(CustPackage(
      id: newId('cp'),
      name: plan.name,
      service: plan.service,
      unit: plan.unit,
      credits: plan.credits,
      remaining: plan.credits,
      price: plan.price,
      start: now,
      end: now.add(Duration(days: plan.days)),
    ));
    final o = createOrder(
      customerId: c.id,
      branchId: branchId,
      lines: [OrderLine(garment: 'Package: ${plan.name}', service: plan.service, qty: 1, rate: plan.price, unit: 'pack')],
      by: by,
      advance: plan.price,
      advanceMode: mode,
      notes: '${plan.credits.toStringAsFixed(0)} ${plan.unit} · ${plan.days} days',
    );
    o.status = 'delivered';
    o.history.add(StatusEvent(status: 'delivered', at: now, by: by, note: 'package'));
    changed();
    return o;
  }

  StockItem addStockItem(String name, String unit, {double qty = 0, double minQty = 0, String branchId = ''}) {
    final it = StockItem(id: newId('st'), name: name.trim(), unit: unit, qty: qty, minQty: minQty, branchId: branchId);
    stock.add(it);
    changed();
    return it;
  }

  /// qty > 0 bought (adds an expense when cost > 0), qty < 0 used.
  void moveStock(StockItem it, double qty, {required String by, String supplierId = '', double cost = 0, String note = ''}) {
    it.qty += qty;
    stockMoves.add(StockMove(id: newId('sm'), itemId: it.id, qty: qty, at: DateTime.now(), by: by, supplierId: supplierId, cost: cost, note: note));
    if (qty > 0 && cost > 0) {
      expenses.add(Expense(
        id: newId('e'),
        branchId: it.branchId.isEmpty ? branches.first.id : it.branchId,
        category: 'Stock purchase',
        amount: cost,
        at: DateTime.now(),
        note: '${it.name} +${qty.toStringAsFixed(0)} ${it.unit}${supplierId.isEmpty ? '' : ' · ${suppliers.where((s) => s.id == supplierId).firstOrNull?.name ?? ''}'}',
      ));
    }
    changed();
  }

  List<StockItem> get lowStock => stock.where((s) => s.low).toList();

  void setCustomerLocation(String customerId, double lat, double lng, {bool onlyIfMissing = false}) {
    final c = customer(customerId);
    if (c == null || (onlyIfMissing && c.hasLocation)) return;
    c
      ..lat = lat
      ..lng = lng;
    changed();
  }

  /// Replace everything with a backup file's data (same owner).
  void restoreFrom(Map<String, dynamic> j) {
    _fromJson(j);
    changed();
  }

  /// Extra paid over the total (after an edit).
  double overpaid(LaundryOrder o) => (o.paid - o.total) > 0.5 ? o.paid - o.total : 0;

  /// Only when nothing is due. Orders stay (shown as "Deleted customer").
  bool deleteCustomer(Customer c, {required String by}) {
    if (dueOf(c.id) > 0.5) return false;
    customers.remove(c);
    log(by, 'customer.delete', text: c.name);
    changed();
    return true;
  }

  /// upi://pay link for the amount due (null when no UPI ID is set).
  String? upiLink(LaundryOrder o, String shopName) {
    if (upiId.trim().isEmpty || o.due <= 0) return null;
    final q = {
      'pa': upiId.trim(),
      'pn': shopName,
      'am': o.due.toStringAsFixed(2),
      'cu': 'INR',
      'tn': 'Laundry ${o.code}',
    }.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return 'upi://pay?$q';
  }

  // ---------------- issues (complaint / re-wash / wrong delivery) ----------------

  Issue? issue(String id) => issues.where((i) => i.id == id).firstOrNull;
  List<Issue> issuesOf(String orderId) => issues.where((i) => i.orderId == orderId || i.otherOrderId == orderId).toList();

  int get _nextIssueNo => issues.fold<int>(0, (m, i) => i.number > m ? i.number : m) + 1;

  /// Who probably caused it, from the order history.
  Map<String, String> suspects(LaundryOrder o) {
    final m = <String, String>{};
    for (final h in o.history) {
      if (h.by.isEmpty || h.by == 'owner') continue;
      if (h.status == 'washing' || h.status == 'ready') m[h.by] = 'washing';
      if (h.status == 'out' || h.status == 'delivered') m.putIfAbsent(h.by, () => 'delivery');
    }
    if (o.deliveryAgent.isNotEmpty) m.putIfAbsent(o.deliveryAgent, () => 'delivery');
    if (o.createdBy.isNotEmpty && o.createdBy != 'owner') m.putIfAbsent(o.createdBy, () => 'counter');
    return m;
  }

  Issue openComplaint({
    required LaundryOrder o,
    required List<String> pieces,
    required String reason,
    required String by,
    String note = '',
    List<String> fault = const [],
    double compensation = 0,
    bool pickupFromHome = false,
    String agent = '',
    DateTime? dueAt,
  }) {
    final now = DateTime.now();
    final i = Issue(
      id: newId('i'),
      number: _nextIssueNo,
      kind: 'complaint',
      orderId: o.id,
      customerId: o.customerId,
      branchId: o.branchId,
      openedAt: now,
      openedBy: by,
      dueAt: dueAt ?? now.add(const Duration(days: 1)),
      pieces: pieces,
      reason: reason,
      note: note,
      fault: fault,
      compensation: compensation,
      stage: pickupFromHome ? 'pickup' : 'received',
      history: [
        StatusEvent(status: 'open', at: now, by: by, note: reason),
        StatusEvent(status: pickupFromHome ? 'pickup' : 'received', at: now, by: by),
      ],
    );
    if (pickupFromHome) i.tasks.add(IssueTask(text: 'Pick up ${pieces.length} pcs for re-wash', agent: agent, customerId: o.customerId));
    if (compensation > 0 && o.due > 0) o.discount += compensation.clamp(0, o.due).toDouble();
    issues.add(i);
    log(by, 'issue.open', orderId: o.id, text: i.code);
    changed();
    return i;
  }

  Issue openWrongDelivery({
    required LaundryOrder o,
    required String subKind,
    required String by,
    LaundryOrder? other,
    String note = '',
    List<String> fault = const [],
    String agent = '',
    List<String> pieces = const [],
  }) {
    final now = DateTime.now();
    final me = customer(o.customerId)?.name ?? '';
    final them = other == null ? '' : (customer(other.customerId)?.name ?? '');
    final tasks = <IssueTask>[];
    switch (subKind) {
      case 'swap':
        tasks
          ..add(IssueTask(text: 'Take back $me\'s clothes from $them', agent: agent, customerId: other?.customerId ?? ''))
          ..add(IssueTask(text: 'Take back $them\'s clothes from $me and give $me the right ones', agent: agent, customerId: o.customerId))
          ..add(IssueTask(text: 'Give $them their own clothes', agent: agent, customerId: other?.customerId ?? ''));
      case 'wrongaddr':
        tasks
          ..add(IssueTask(text: 'Collect the order from the wrong address', agent: agent))
          ..add(IssueTask(text: 'Deliver to $me', agent: agent, customerId: o.customerId));
      default:
        tasks
          ..add(IssueTask(text: 'Find the missing pieces in the shop / racks', agent: by))
          ..add(IssueTask(text: 'Deliver missing pieces to $me', agent: agent, customerId: o.customerId));
    }
    final i = Issue(
      id: newId('i'),
      number: _nextIssueNo,
      kind: 'wrong',
      subKind: subKind,
      orderId: o.id,
      otherOrderId: other?.id ?? '',
      customerId: o.customerId,
      branchId: o.branchId,
      openedAt: now,
      openedBy: by,
      dueAt: now.add(const Duration(hours: 24)),
      pieces: pieces,
      reason: 'Wrong delivery',
      note: note,
      fault: fault,
      tasks: tasks,
      history: [StatusEvent(status: 'open', at: now, by: by, note: subKind)],
    );
    issues.add(i);
    log(by, 'issue.open', orderId: o.id, text: i.code);
    changed();
    return i;
  }

  void issueStage(Issue i, String stage, {required String by, String note = ''}) {
    i.stage = stage;
    i.history.add(StatusEvent(status: stage, at: DateTime.now(), by: by, note: note));
    log(by, 'issue.$stage', orderId: i.orderId, text: i.code);
    changed();
  }

  void taskDone(Issue i, IssueTask task, {required String by}) {
    task
      ..done = true
      ..doneAt = DateTime.now()
      ..doneBy = by;
    i.history.add(StatusEvent(status: 'task', at: DateTime.now(), by: by, note: task.text));
    log(by, 'issue.task', orderId: i.orderId, text: i.code);
    changed();
  }

  void closeIssue(Issue i, {required String by, String note = ''}) {
    i
      ..closed = true
      ..closedAt = DateTime.now();
    i.history.add(StatusEvent(status: 'closed', at: DateTime.now(), by: by, note: note));
    log(by, 'issue.closed', orderId: i.orderId, text: i.code);
    changed();
  }

  void reopenIssue(Issue i, {required String by, required String note}) {
    i
      ..closed = false
      ..closedAt = null
      ..reopenCount += 1
      ..stage = i.kind == 'complaint' ? 'received' : 'open';
    i.history.add(StatusEvent(status: 'reopened', at: DateTime.now(), by: by, note: note));
    log(by, 'issue.reopened', orderId: i.orderId, text: i.code);
    changed();
  }

  // ---------------- payroll ----------------

  void addPayout(String staffId, String month, String kind, double amount, {String mode = 'cash', String note = ''}) {
    payouts.add(Payout(id: newId('p'), staffId: staffId, month: month, kind: kind, amount: amount, at: DateTime.now(), mode: mode, note: note));
    changed();
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
    issues.removeWhere((i) => i.id.startsWith('demo_'));
    coupons.removeWhere((x) => x.id.startsWith('demo_'));
    packagePlans.removeWhere((x) => x.id.startsWith('demo_'));
    stock.removeWhere((x) => x.id.startsWith('demo_'));
    stockMoves.removeWhere((x) => x.id.startsWith('demo_'));
    suppliers.removeWhere((x) => x.id.startsWith('demo_'));
    payouts.removeWhere((p) => p.id.startsWith('demo_'));
    hasSample = false;
    if (orders.isEmpty) nextNumber = 1;
    changed();
  }
}
