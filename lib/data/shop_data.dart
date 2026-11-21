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
  List<StaffRequest> requests = [];
  List<StockUse> stockUses = [];
  List<Notice> notices = [];
  List<CashDay> cashDays = [];
  List<Machine> machines = [];
  List<MeterReading> readings = [];
  List<StaffNote> staffNotes = [];
  List<Loan> loans = [];
  List<String> trainingItems = ['Billing in the app', 'Tagging clothes', 'Stain types & care labels', 'Machine safety', 'Customer behaviour'];
  Map<String, double> meterRates = {'electricity': 9, 'water': 0.05, 'gas': 0};
  String gstin = '';
  // v0.8 settings
  double dailyTarget = 0; // sales target per day (whole shop or per branch below)
  int dailyOrderTarget = 0;
  bool autoAssign = false; // give new order lines to washers by their skills
  double referralPoints = 50; // points to both customers when a referred customer's first order is delivered
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
        if (admin && d.applyStockUses()) d.changed();
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
  /// Set by AppState: called after another phone changed something (for notifications).
  VoidCallback? onRemote;

  void remoteChanged() {
    onRemote?.call();
    // owner phone books staff "used" entries into stock (once each)
    if ((sync?.admin ?? true) && applyStockUses()) {
      Future.microtask(changed);
    }
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
        'targets': {'sales': dailyTarget, 'orders': dailyOrderTarget},
        'autoAssign': autoAssign,
        'referralPoints': referralPoints,
        'trainingItems': trainingItems,
        'meterRates': meterRates,
        'gstin': gstin,
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
    _targets(j);
  }

  void _targets(Map<String, dynamic> j) {
    final t = j['targets'];
    if (t is Map) {
      dailyTarget = (t['sales'] as num?)?.toDouble() ?? dailyTarget;
      dailyOrderTarget = (t['orders'] as num?)?.toInt() ?? dailyOrderTarget;
    }
    autoAssign = j['autoAssign'] as bool? ?? autoAssign;
    referralPoints = (j['referralPoints'] as num?)?.toDouble() ?? referralPoints;
    if (j['trainingItems'] is List) trainingItems = (j['trainingItems'] as List).map((e) => '$e').toList();
    if (j['meterRates'] is Map) meterRates = Map<String, dynamic>.from(j['meterRates'] as Map).map((k, v) => MapEntry(k, (v as num).toDouble()));
    gstin = j['gstin'] as String? ?? gstin;
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
    garments = [...DefaultRates.garments, if (shop.services.contains('Alteration')) ...DefaultRates.alterations].map((g) => Garment.fromJson(g.toJson())).toList();
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
        'targets': {'sales': dailyTarget, 'orders': dailyOrderTarget},
        'autoAssign': autoAssign,
        'referralPoints': referralPoints,
        'trainingItems': trainingItems,
        'meterRates': meterRates,
        'gstin': gstin,
        'machines': machines.map((e) => e.toJson()).toList(),
        'readings': readings.map((e) => e.toJson()).toList(),
        'staffNotes': staffNotes.map((e) => e.toJson()).toList(),
        'loans': loans.map((e) => e.toJson()).toList(),
        'notices': notices.map((e) => e.toJson()).toList(),
        'cashDays': cashDays.map((e) => e.toJson()).toList(),
        'coupons': coupons.map((e) => e.toJson()).toList(),
        'packagePlans': packagePlans.map((e) => e.toJson()).toList(),
        'stock': stock.map((e) => e.toJson()).toList(),
        'stockMoves': stockMoves.map((e) => e.toJson()).toList(),
        'suppliers': suppliers.map((e) => e.toJson()).toList(),
        'requests': requests.map((e) => e.toJson()).toList(),
        'stockUses': stockUses.map((e) => e.toJson()).toList(),
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
    _targets(j);
    notices = list('notices').map(Notice.fromJson).toList();
    cashDays = list('cashDays').map(CashDay.fromJson).toList();
    machines = list('machines').map(Machine.fromJson).toList();
    readings = list('readings').map(MeterReading.fromJson).toList();
    staffNotes = list('staffNotes').map(StaffNote.fromJson).toList();
    loans = list('loans').map(Loan.fromJson).toList();
    coupons = list('coupons').map(Coupon.fromJson).toList();
    packagePlans = list('packagePlans').map(PackagePlan.fromJson).toList();
    stock = list('stock').map(StockItem.fromJson).toList();
    stockMoves = list('stockMoves').map(StockMove.fromJson).toList();
    suppliers = list('suppliers').map(Supplier.fromJson).toList();
    requests = list('requests').map(StaffRequest.fromJson).toList();
    stockUses = list('stockUses').map(StockUse.fromJson).toList();
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
    if (autoAssign) autoAssignWork(o);
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
      // referral: first delivered order of a referred customer → points to both
      if (c != null && c.referredBy.isNotEmpty && !c.referralPaid && referralPoints > 0) {
        final ref = customer(c.referredBy);
        c.points += referralPoints;
        ref?.points += referralPoints;
        c.referralPaid = true;
        log(by, 'referral', text: '${c.name} ← ${ref?.name ?? ''} +${referralPoints.toStringAsFixed(0)}');
      }
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
    log(by, 'pay', orderId: o.id, text: '${o.code}: ${amount.toStringAsFixed(0)} ($mode)');
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
    log(by, 'order.edit', orderId: o.id, text: '${o.code}: ${before.toStringAsFixed(0)} → ${o.total.toStringAsFixed(0)}');
    changed();
  }

  /// Money given back to the customer (a negative payment, so reports stay right).
  void refund(LaundryOrder o, double amount, String mode, {required String by, String note = ''}) {
    if (amount <= 0) return;
    o.payments.add(Payment(amount: -amount, mode: mode, at: DateTime.now(), by: by, note: note.isEmpty ? 'refund' : 'refund: $note'));
    o.history.add(StatusEvent(status: 'refund', at: DateTime.now(), by: by, note: amount.toStringAsFixed(0)));
    log(by, 'refund', orderId: o.id, text: '${o.code}: ${amount.toStringAsFixed(0)} ($mode)${note.isEmpty ? '' : ' – $note'}');
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

  // ---------- staff requests ----------

  StaffRequest addRequest({required String by, required String branchId, required String item, String itemId = '', double qty = 1, String unit = '', String note = '', bool urgent = false}) {
    final r = StaffRequest(id: newId('rq'), by: by, branchId: branchId, item: item.trim(), itemId: itemId, qty: qty, unit: unit, note: note.trim(), urgent: urgent, at: DateTime.now());
    requests.add(r);
    log(by, 'request.new', text: '${r.item} ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} $unit');
    changed();
    return r;
  }

  /// status: approved | given | rejected. [fromStock] takes the qty out of stock when giving.
  void decideRequest(StaffRequest r, String status, {required String by, String reply = '', bool fromStock = false, double cost = 0, String supplierId = ''}) {
    r
      ..status = status
      ..doneAt = DateTime.now()
      ..doneBy = by
      ..reply = reply.trim();
    final it = r.itemId.isEmpty ? null : stock.where((x) => x.id == r.itemId).firstOrNull;
    final admin = sync?.admin ?? true;
    if (status == 'given' && it != null) {
      if (cost > 0 && admin) moveStock(it, r.qty, by: by, cost: cost, supplierId: supplierId, note: 'for request ${r.item}');
      if (fromStock || cost > 0) {
        if (admin) {
          it.qty -= r.qty;
          stockMoves.add(StockMove(id: 'rq_${r.id}', itemId: it.id, qty: -r.qty, at: DateTime.now(), by: r.by, note: 'given to ${nameOf(r.by)}'));
        } else {
          // manager phone: the owner's phone books it into stock
          stockUses.add(StockUse(id: 'rq_${r.id}', by: r.by, itemId: it.id, qty: r.qty, at: DateTime.now(), branchId: r.branchId, note: 'given to ${nameOf(r.by)}'));
        }
      }
    } else if (status == 'given' && cost > 0 && admin) {
      expenses.add(Expense(id: newId('e'), branchId: r.branchId.isEmpty ? branches.first.id : r.branchId, category: 'Stock purchase', amount: cost, at: DateTime.now(), note: '${r.item} for ${nameOf(r.by)}'));
    }
    log(by, 'request.$status', text: r.item);
    changed();
  }

  List<StaffRequest> get pendingRequests => requests.where((r) => r.status == 'pending').toList()..sort((a, b) => (b.urgent ? 1 : 0) - (a.urgent ? 1 : 0) != 0 ? (b.urgent ? 1 : 0) - (a.urgent ? 1 : 0) : a.at.compareTo(b.at));

  // ---------- stock used by staff ----------

  void addStockUse(StockItem it, double qty, {required String by, String branchId = '', String note = ''}) {
    stockUses.add(StockUse(id: newId('su'), by: by, itemId: it.id, qty: qty, at: DateTime.now(), branchId: branchId.isEmpty ? it.branchId : branchId, note: note));
    changed();
  }

  /// Uses not yet booked into stock (staff phones show them as pending).
  double pendingUse(String itemId) =>
      stockUses.where((u) => u.itemId == itemId && !stockMoves.any((m) => m.id == 'use_${u.id}')).fold(0.0, (s, u) => s + u.qty);

  /// Owner phone: books every staff "used" entry into stock exactly once.
  bool applyStockUses() {
    var any = false;
    for (final u in stockUses) {
      final mid = 'use_${u.id}';
      if (stockMoves.any((m) => m.id == mid)) continue;
      final it = stock.where((x) => x.id == u.itemId).firstOrNull;
      if (it == null) continue;
      it.qty -= u.qty;
      stockMoves.add(StockMove(id: mid, itemId: it.id, qty: -u.qty, at: u.at, by: u.by, note: u.note));
      any = true;
    }
    return any;
  }

  /// Average cost of one unit (from purchases with a price).
  double unitCost(String itemId) {
    final buys = stockMoves.where((m) => m.itemId == itemId && m.qty > 0 && m.cost > 0);
    final q = buys.fold(0.0, (s, m) => s + m.qty);
    return q <= 0 ? 0 : buys.fold(0.0, (s, m) => s + m.cost) / q;
  }

  /// Amount used in [from, to) (owner moves + staff uses), optional branch / person.
  double usedIn(String itemId, DateTime from, DateTime to, {String? by}) => stockMoves
      .where((m) => m.itemId == itemId && m.qty < 0 && !m.at.isBefore(from) && m.at.isBefore(to) && (by == null || m.by == by))
      .fold(0.0, (s, m) => s - m.qty);

  double boughtIn(String itemId, DateTime from, DateTime to) =>
      stockMoves.where((m) => m.itemId == itemId && m.qty > 0 && !m.at.isBefore(from) && m.at.isBefore(to)).fold(0.0, (s, m) => s + m.qty);

  /// kg of clothes washed in [from, to) (orders by kg + 0.25 kg per piece).
  double kgWashed(DateTime from, DateTime to, {String? branchId}) {
    var kg = 0.0;
    for (final o in orders) {
      if (o.status == 'cancelled' || o.createdAt.isBefore(from) || !o.createdAt.isBefore(to)) continue;
      if (branchId != null && o.branchId != branchId) continue;
      for (final l in o.lines) {
        kg += l.unit == 'kg' ? l.qty : l.qty * 0.25;
      }
    }
    return kg;
  }

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

  /// upi://pay link for any amount (statements).
  String upiAmountLink(double amount, String shopName, String note) {
    final q = {'pa': upiId.trim(), 'pn': shopName, 'am': amount.toStringAsFixed(2), 'cu': 'INR', 'tn': note}
        .entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'upi://pay?$q';
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
  // ---------- machines ----------

  Machine addMachine(String name, {required String branchId, String kind = 'Washer', int everyDays = 90}) {
    final m = Machine(id: newId('mc'), name: name.trim(), branchId: branchId, kind: kind, everyDays: everyDays, lastService: DateTime.now());
    machines.add(m);
    changed();
    return m;
  }

  void serviceMachine(Machine m, {required String by, double cost = 0, String note = ''}) {
    m
      ..lastService = DateTime.now()
      ..status = 'ok'
      ..note = note.trim();
    if (cost > 0) {
      expenses.add(Expense(id: newId('e'), branchId: m.branchId.isEmpty ? branches.first.id : m.branchId, category: 'Repairs', amount: cost, at: DateTime.now(), note: '${m.name} service'));
    }
    log(by, 'machine.service', text: '${m.name}${cost > 0 ? ' ${cost.toStringAsFixed(0)}' : ''}');
    changed();
  }

  /// Staff report a breakdown: a request of kind 'fault' (owner sees it with staff requests).
  void reportFault(Machine m, {required String by, required String branchId, String note = ''}) {
    requests.add(StaffRequest(id: newId('ft'), kind: 'fault', by: by, branchId: branchId, item: m.name, itemId: m.id, qty: 1, unit: '', note: note.trim(), urgent: true, at: DateTime.now()));
    log(by, 'machine.fault', text: '${m.name} ${note.trim()}');
    changed();
  }

  List<Machine> get machinesDue => machines.where((m) => m.serviceDue || m.status == 'broken' || requests.any((r) => r.kind == 'fault' && r.itemId == m.id && r.open)).toList();

  // ---------- meters ----------

  void addReading(String kind, String branchId, double value, {required String by}) {
    readings.add(MeterReading(id: newId('mr'), kind: kind, branchId: branchId, value: value, at: DateTime.now(), by: by));
    changed();
  }

  /// Units used between the last reading before [from] (or first in range) and the last reading before [to].
  double meterUsed(String kind, String branchId, DateTime from, DateTime to) {
    final l = readings.where((r) => r.kind == kind && r.branchId == branchId && r.at.isBefore(to)).toList()..sort((a, b) => a.at.compareTo(b.at));
    if (l.length < 2) return 0;
    final before = l.where((r) => r.at.isBefore(from)).toList();
    final start = before.isNotEmpty ? before.last : l.first;
    final end = l.last;
    return (end.value - start.value).clamp(0, double.infinity).toDouble();
  }

  // ---------- staff notes, loans, training, late ----------

  void addStaffNote(String staffId, String kind, String text, {required String by, double fine = 0}) {
    staffNotes.add(StaffNote(id: newId('sn'), staffId: staffId, kind: kind, text: text.trim(), at: DateTime.now(), by: by, fine: fine));
    log(by, 'staff.$kind', text: '${nameOf(staffId)}: ${text.trim()}${fine > 0 ? ' (−${fine.toStringAsFixed(0)})' : ''}');
    changed();
  }

  void addLoan(String staffId, double amount, double monthly, String start, {required String by, String note = ''}) {
    loans.add(Loan(id: newId('ln'), staffId: staffId, amount: amount, monthly: monthly, start: start, at: DateTime.now(), note: note.trim()));
    log(by, 'loan', text: '${nameOf(staffId)}: ${amount.toStringAsFixed(0)} @ ${monthly.toStringAsFixed(0)}/month');
    changed();
  }

  /// Minutes late (after shift start + 10 min grace) and overtime minutes for a month.
  ({int days, int lateDays, int lateMin, int overMin}) shiftReport(Staff s, String month) {
    var days = 0, lateDays = 0, lateMin = 0, overMin = 0;
    for (final a in attendance.where((a) => a.staffId == s.id && a.day.startsWith(month))) {
      days++;
      if (s.shiftStart.length == 5) {
        final st = DateTime(a.inAt.year, a.inAt.month, a.inAt.day, int.parse(s.shiftStart.substring(0, 2)), int.parse(s.shiftStart.substring(3)));
        final late = a.inAt.difference(st).inMinutes;
        if (late > 10) {
          lateDays++;
          lateMin += late;
        }
      }
      if (s.shiftEnd.length == 5 && a.outAt != null) {
        final en = DateTime(a.outAt!.year, a.outAt!.month, a.outAt!.day, int.parse(s.shiftEnd.substring(0, 2)), int.parse(s.shiftEnd.substring(3)));
        final over = a.outAt!.difference(en).inMinutes;
        if (over > 15) overMin += over;
      }
    }
    return (days: days, lateDays: lateDays, lateMin: lateMin, overMin: overMin);
  }

  // ---------- analytics ----------

  /// Sales per month for the last [n] months (oldest first): (label yyyy-mm, sales).
  List<(String, double)> monthlySales(int n, {String? branchId}) {
    final now = DateTime.now();
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final from = DateTime(now.year, now.month - i, 1);
          final to = DateTime(now.year, now.month - i + 1, 1);
          final v = ordersIn(branchId).where((o) => o.status != 'cancelled' && !o.createdAt.isBefore(from) && o.createdAt.isBefore(to)).fold(0.0, (s, o) => s + o.total);
          return ('${from.year}-${from.month.toString().padLeft(2, '0')}', v);
        }(),
    ];
  }

  /// Orders by weekday (Mon..Sun) and by hour (0..23) in [from, to).
  (List<int>, List<int>) busyTimes(DateTime from, DateTime to, {String? branchId}) {
    final wd = List.filled(7, 0), hr = List.filled(24, 0);
    for (final o in ordersIn(branchId)) {
      if (o.createdAt.isBefore(from) || !o.createdAt.isBefore(to)) continue;
      wd[o.createdAt.weekday - 1]++;
      hr[o.createdAt.hour]++;
    }
    return (wd, hr);
  }

  /// Per service: (revenue, pieces/kg, orders) in [from, to). Discounts / offers spread by share.
  Map<String, (double, double, int)> serviceRevenue(DateTime from, DateTime to, {String? branchId}) {
    final m = <String, (double, double, int)>{};
    for (final o in ordersIn(branchId)) {
      if (o.status == 'cancelled' || o.createdAt.isBefore(from) || !o.createdAt.isBefore(to) || o.subtotal <= 0) continue;
      final f = o.taxable / o.subtotal; // after discount + offers, before tax
      final seen = <String>{};
      for (final l in o.lines) {
        final cur = m[l.service] ?? (0.0, 0.0, 0);
        m[l.service] = (cur.$1 + l.amount * f, cur.$2 + (l.unit == 'kg' ? l.qty : l.pieces.toDouble()), cur.$3 + (seen.add(l.service) ? 1 : 0));
      }
    }
    return m;
  }

  /// Regular customers (3+ orders) who have not come for [days].
  List<Customer> lostRegulars({int days = 45}) {
    final n = DateTime.now();
    return customers.where((c) {
      final os = orders.where((o) => o.customerId == c.id && o.status != 'cancelled').length;
      final l = lastVisit(c.id);
      return os >= 3 && l != null && n.difference(l).inDays >= days;
    }).toList();
  }

  /// Delivery person in [from, to): drops, pickups, avg minutes out→delivered, km (from GPS pings), on-time %.
  ({int drops, int pickups, double avgMin, double km, double onTime}) deliveryStats(String staffId, DateTime from, DateTime to) {
    var drops = 0, pickups = 0, ontime = 0;
    var mins = 0.0;
    for (final o in orders) {
      for (final h in o.history) {
        if (h.by != staffId || h.at.isBefore(from) || !h.at.isBefore(to)) continue;
        if (h.status == 'delivered' && o.homeDelivery) {
          drops++;
          final out = o.timeOf('out');
          if (out != null) mins += h.at.difference(out).inMinutes;
          if (!h.at.isAfter(o.dueAt.add(const Duration(hours: 2)))) ontime++;
        }
        if (h.status == 'received' && o.timeOf('pickup') != null) pickups++;
      }
    }
    var km = 0.0;
    final ps = (pings[staffId] ?? []).where((p) => !p.at.isBefore(from) && p.at.isBefore(to)).toList()..sort((a, b) => a.at.compareTo(b.at));
    for (var i = 1; i < ps.length; i++) {
      if (dayKey(ps[i].at) != dayKey(ps[i - 1].at)) continue;
      final d = _km(ps[i - 1].lat, ps[i - 1].lng, ps[i].lat, ps[i].lng);
      if (d < 5) km += d; // ignore GPS jumps
    }
    return (drops: drops, pickups: pickups, avgMin: drops == 0 ? 0 : mins / drops, km: km, onTime: drops == 0 ? 0 : ontime / drops * 100);
  }

  static double _km(double a1, double o1, double a2, double o2) {
    const r = 6371.0;
    double rad(double x) => x * pi / 180;
    final da = rad(a2 - a1), dlo = rad(o2 - o1);
    final h = sin(da / 2) * sin(da / 2) + cos(rad(a1)) * cos(rad(a2)) * sin(dlo / 2) * sin(dlo / 2);
    return 2 * r * asin(sqrt(h));
  }

  // ---------- customers: groups, history, statement ----------

  DateTime? lastVisit(String customerId) {
    DateTime? last;
    for (final o in orders) {
      if (o.customerId == customerId && o.status != 'cancelled' && (last == null || o.createdAt.isAfter(last))) last = o.createdAt;
    }
    return last;
  }

  double spendOf(String customerId) => orders.where((o) => o.customerId == customerId && o.status != 'cancelled').fold(0.0, (s, o) => s + o.total);

  /// group: away30 | away60 | vip | business | dues | birthday | top | new | low_rating
  List<Customer> customerGroup(String group) {
    final n = DateTime.now();
    switch (group) {
      case 'away30':
      case 'away60':
        final days = group == 'away30' ? 30 : 60;
        return customers.where((c) {
          final l = lastVisit(c.id);
          return l != null && n.difference(l).inDays >= days;
        }).toList();
      case 'vip':
      case 'business':
        return customers.where((c) => c.type == group).toList();
      case 'dues':
        return customers.where((c) => dueOf(c.id) > 0.5).toList();
      case 'birthday':
        return customers.where((c) => c.dob != null && c.dob!.month == n.month).toList();
      case 'top':
        final l = [...customers]..sort((a, b) => spendOf(b.id).compareTo(spendOf(a.id)));
        return l.take(20).toList();
      case 'new':
        return customers.where((c) => n.difference(c.createdAt).inDays <= 30).toList();
      case 'lost':
        return lostRegulars();
      case 'low_rating':
        final ids = {for (final o in orders) if (o.rating > 0 && o.rating <= 2) o.customerId};
        return customers.where((c) => ids.contains(c.id)).toList();
    }
    return customers;
  }

  /// Every item this customer ever gave: newest first.
  List<(LaundryOrder, OrderLine)> clothesHistory(String customerId) {
    final l = <(LaundryOrder, OrderLine)>[];
    for (final o in orders.where((o) => o.customerId == customerId)) {
      for (final x in o.lines) {
        l.add((o, x));
      }
    }
    l.sort((a, b) => b.$1.createdAt.compareTo(a.$1.createdAt));
    return l;
  }

  void rateOrder(LaundryOrder o, int stars, {required String by, String note = ''}) {
    o.rating = stars.clamp(1, 5);
    o.ratingNote = note.trim();
    log(by, 'rating', orderId: o.id, text: '${o.code}: $stars★${note.isEmpty ? '' : ' $note'}');
    changed();
  }

  // ---------- staff permissions ----------

  static const permKeys = ['discount', 'refund', 'editOrder', 'cancel', 'deleteCustomer', 'expenses', 'reports', 'rates'];

  static bool permDefault(Role r, String key) => switch (r) {
        Role.owner || Role.manager => true,
        Role.counter => key == 'discount' || key == 'editOrder',
        _ => false,
      };

  bool can(Staff? s, String key) {
    if (s == null) return true; // owner
    return s.perms[key] ?? permDefault(s.role, key);
  }

  // ---------- work assign (who washes / irons which clothes) ----------

  List<Staff> workersIn(String branchId) =>
      staff.where((s) => s.active && (s.role == Role.washer || s.role == Role.manager) && (branchId.isEmpty || s.branchId == branchId)).toList();

  /// Open (not done) lines given to a person: (order, line index).
  List<(LaundryOrder, int)> openWork(String staffId) => [
        for (final o in orders)
          if (o.open && o.status != 'pickup')
            for (var i = 0; i < o.lines.length; i++)
              if (o.lines[i].worker == staffId && o.lines[i].work != 'done') (o, i),
      ];

  /// Lines nobody has yet (received / washing orders).
  List<(LaundryOrder, int)> unassignedWork(String? branchId) => [
        for (final o in orders)
          if ((o.status == 'received' || o.status == 'washing') && (branchId == null || o.branchId == branchId))
            for (var i = 0; i < o.lines.length; i++)
              if (o.lines[i].worker.isEmpty) (o, i),
      ];

  int openPieces(String staffId) => openWork(staffId).fold(0, (s, w) => s + w.$1.lines[w.$2].pieces);

  /// Gives each free line to a washer who has that service in skills (least busy first).
  int autoAssignWork(LaundryOrder o) {
    var n = 0;
    for (final l in o.lines) {
      if (l.worker.isNotEmpty) continue;
      final ws = workersIn(o.branchId).where((w) => w.role == Role.washer).toList();
      var pool = ws.where((w) => w.skills.contains(l.service)).toList();
      if (pool.isEmpty) pool = ws.where((w) => w.skills.isEmpty).toList();
      if (pool.isEmpty) continue;
      pool.sort((a, b) => openPieces(a.id).compareTo(openPieces(b.id)));
      l.worker = pool.first.id;
      n++;
    }
    return n;
  }

  void assignLine(LaundryOrder o, int i, String staffId, {required String by}) {
    final l = o.lines[i];
    l.worker = staffId;
    if (staffId.isEmpty) {
      l.work = '';
      l.workAt = null;
    }
    log(by, 'work.assign', orderId: o.id, text: '${o.code} ${l.garment} → ${staffId.isEmpty ? '-' : nameOf(staffId)}');
    changed();
  }

  /// Start / finish one line. The order moves to "washing" on the first start
  /// and to "ready" when every line is done.
  void lineWork(LaundryOrder o, int i, String work, {required String by}) {
    final l = o.lines[i];
    if (l.worker.isEmpty) l.worker = by;
    l.work = work;
    l.workAt = DateTime.now();
    log(by, 'work.$work', orderId: o.id, text: '${o.code} ${l.garment} ${qtyLabel(l)}');
    if (o.status == 'received') {
      o.status = 'washing';
      o.history.add(StatusEvent(status: 'washing', at: DateTime.now(), by: by));
    }
    if (o.lines.every((x) => x.work == 'done') && (o.status == 'washing' || o.status == 'received')) {
      o.status = 'ready';
      o.history.add(StatusEvent(status: 'ready', at: DateTime.now(), by: by));
      log(by, 'status.ready', orderId: o.id, text: o.code);
    }
    changed();
  }

  static String qtyLabel(OrderLine l) => l.unit == 'kg' ? '${l.qty.toStringAsFixed(1)} kg' : '${l.qty.toStringAsFixed(0)} pc';

  /// Pieces / kg a person finished in [from, to).
  (int, double) workDone(String staffId, DateTime from, DateTime to) {
    var pcs = 0;
    var kg = 0.0;
    for (final o in orders) {
      for (final l in o.lines) {
        if (l.worker != staffId || l.work != 'done' || l.workAt == null || l.workAt!.isBefore(from) || !l.workAt!.isBefore(to)) continue;
        if (l.unit == 'kg') {
          kg += l.qty;
        } else {
          pcs += l.pieces;
        }
      }
    }
    return (pcs, kg);
  }

  // ---------- notices ----------

  Notice addNotice(String text, {required String by, String branchId = ''}) {
    final n = Notice(id: newId('nt'), text: text.trim(), by: by, at: DateTime.now(), branchId: branchId);
    notices.add(n);
    log(by, 'notice', text: n.text.length > 40 ? '${n.text.substring(0, 40)}…' : n.text);
    changed();
    return n;
  }

  List<Notice> noticesFor(String staffId, String branchId) =>
      notices.where((n) => n.branchId.isEmpty || n.branchId == branchId).toList()..sort((a, b) => b.at.compareTo(a.at));

  void readNotice(Notice n, String staffId) {
    if (n.readBy.contains(staffId)) return;
    n.readBy.add(staffId);
    changed();
  }

  // ---------- leave ----------

  StaffRequest addLeave({required String by, required String branchId, required DateTime from, required DateTime to, String note = ''}) {
    final r = StaffRequest(
        id: newId('lv'), kind: 'leave', by: by, branchId: branchId, item: 'Leave', qty: (to.difference(from).inDays + 1).toDouble(), unit: 'days',
        note: note.trim(), at: DateTime.now(), from: DateTime(from.year, from.month, from.day), to: DateTime(to.year, to.month, to.day));
    requests.add(r);
    log(by, 'leave.new', text: '${dayKey(r.from!)} → ${dayKey(r.to!)}');
    changed();
    return r;
  }

  /// Approved leave days of a person in a month (yyyy-mm).
  int leaveDaysIn(String staffId, String month) {
    var n = 0;
    for (final r in requests.where((r) => r.kind == 'leave' && r.by == staffId && (r.status == 'approved' || r.status == 'given') && r.from != null)) {
      for (var d = r.from!; !d.isAfter(r.to ?? r.from!); d = d.add(const Duration(days: 1))) {
        if (dayKey(d).startsWith(month)) n++;
      }
    }
    return n;
  }

  // ---------- cash drawer ----------

  CashDay cashDay(String branchId, DateTime day) {
    final id = '${branchId}_${dayKey(day)}';
    return cashDays.where((c) => c.id == id).firstOrNull ?? CashDay(id: id, branchId: branchId, day: dayKey(day));
  }

  void openDrawer(String branchId, double amount, {required String by}) {
    final c = cashDay(branchId, DateTime.now());
    c
      ..opening = amount
      ..openedBy = by
      ..openedAt = DateTime.now();
    if (!cashDays.contains(c)) cashDays.add(c);
    log(by, 'cash.open', text: '${branch(branchId)?.name ?? ''}: ${amount.toStringAsFixed(0)}');
    changed();
  }

  /// Cash that should be in the drawer: opening + cash taken − cash refunds − expenses of that day.
  double expectedCash(String branchId, DateTime day) {
    final c = cashDay(branchId, day);
    final k = dayKey(day);
    var cash = c.opening;
    for (final o in orders.where((o) => o.branchId == branchId)) {
      for (final p in o.payments) {
        if (p.mode == 'cash' && dayKey(p.at) == k) cash += p.amount;
      }
    }
    for (final e in expenses.where((e) => e.branchId == branchId && dayKey(e.at) == k)) {
      cash -= e.amount;
    }
    return cash;
  }

  void closeDrawer(String branchId, double counted, {required String by, String note = ''}) {
    final c = cashDay(branchId, DateTime.now());
    c
      ..closing = counted
      ..closedBy = by
      ..closedAt = DateTime.now()
      ..note = note.trim();
    if (!cashDays.contains(c)) cashDays.add(c);
    final diff = counted - expectedCash(branchId, DateTime.now());
    log(by, 'cash.close', text: '${branch(branchId)?.name ?? ''}: ${counted.toStringAsFixed(0)} (${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(0)})');
    changed();
  }

  // ---------- piece count at hand-over ----------

  void countOut(LaundryOrder o, int counted, {required String by}) {
    o.countOut = counted;
    if (counted != o.pieces) log(by, 'count.mismatch', orderId: o.id, text: '${o.code}: $counted / ${o.pieces}');
    changed();
  }

  /// Removes demo records. Own records that point at demo branches/customers are kept and moved
  /// to the main branch so nothing real is lost. Returns how many records were removed.
  int clearSample() {
    bool demo(String id) => id.startsWith('demo_');
    final before = customers.length + orders.length + staff.length + expenses.length + branches.length + attendance.length + activity.length +
        pings.length + issues.length + coupons.length + packagePlans.length + stock.length + stockMoves.length + suppliers.length + payouts.length;
    final keepBranch = branches.where((b) => !demo(b.id)).firstOrNull ?? branches.firstOrNull;
    final usedCustomers = orders.where((o) => !demo(o.id)).map((o) => o.customerId).toSet();
    orders.removeWhere((o) => demo(o.id));
    customers.removeWhere((c) => demo(c.id) && !usedCustomers.contains(c.id));
    staff.removeWhere((x) => demo(x.id));
    expenses.removeWhere((e) => demo(e.id));
    if (keepBranch != null && !demo(keepBranch.id)) {
      branches.removeWhere((b) => demo(b.id));
      for (final o in orders) {
        if (demo(o.branchId)) o.branchId = keepBranch.id;
      }
      for (final x in staff) {
        if (demo(x.branchId)) x.branchId = keepBranch.id;
      }
      for (final e in expenses) {
        if (demo(e.branchId)) e.branchId = keepBranch.id;
      }
    }
    attendance.removeWhere((a) => demo(a.staffId));
    activity.removeWhere((a) => demo(a.by) || demo(a.orderId));
    pings.removeWhere((k, _) => demo(k));
    issues.removeWhere((i) => demo(i.id) || demo(i.orderId));
    coupons.removeWhere((x) => demo(x.id));
    packagePlans.removeWhere((x) => demo(x.id));
    stock.removeWhere((x) => demo(x.id));
    stockMoves.removeWhere((x) => demo(x.id));
    suppliers.removeWhere((x) => demo(x.id));
    payouts.removeWhere((p) => demo(p.id) || demo(p.staffId));
    requests.removeWhere((r) => demo(r.id) || demo(r.by));
    stockUses.removeWhere((u) => demo(u.id) || demo(u.by));
    notices.removeWhere((n) => demo(n.id));
    machines.removeWhere((m) => demo(m.id));
    readings.removeWhere((r) => demo(r.id));
    staffNotes.removeWhere((x) => demo(x.id) || demo(x.staffId));
    loans.removeWhere((x) => demo(x.id) || demo(x.staffId));
    cashDays.removeWhere((c) => demo(c.branchId) || demo(c.openedBy) || demo(c.closedBy));
    final after = customers.length + orders.length + staff.length + expenses.length + branches.length + attendance.length + activity.length +
        pings.length + issues.length + coupons.length + packagePlans.length + stock.length + stockMoves.length + suppliers.length + payouts.length;
    hasSample = false;
    if (orders.isEmpty) nextNumber = 1;
    changed();
    return before - after;
  }
}
