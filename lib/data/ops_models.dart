/// Day-to-day shop data: branches, customers, rate card, orders, staff, expenses.
library;

enum Role { owner, manager, counter, washer, delivery }

Role roleFrom(String s) => Role.values.firstWhere((r) => r.name == s, orElse: () => Role.counter);

/// Order life: pickup (booked from home) → received → washing → ready → out → delivered. Or cancelled.
const orderFlow = ['pickup', 'received', 'washing', 'ready', 'out', 'delivered'];

String? nextStatus(String s, {required bool homeDelivery}) {
  switch (s) {
    case 'pickup':
      return 'received';
    case 'received':
      return 'washing';
    case 'washing':
      return 'ready';
    case 'ready':
      return homeDelivery ? 'out' : 'delivered';
    case 'out':
      return 'delivered';
    default:
      return null;
  }
}

const payModes = ['cash', 'upi', 'card'];

const expenseCategories = [
  'Detergent & chemicals',
  'Electricity',
  'Water',
  'Rent',
  'Salary',
  'Maintenance',
  'Fuel & transport',
  'Packaging',
  'Stock purchase',
  'Other',
];

class Branch {
  Branch({required this.id, required this.name, this.address = '', this.phone = ''});
  final String id;
  String name;
  String address;
  String phone;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'address': address, 'phone': phone};
  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        address: j['address'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
      );
}

class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.address = '',
    this.type = 'regular', // regular | vip | business
    this.notes = '',
    this.lat,
    this.lng,
    this.points = 0,
    List<CustPackage>? packages,
    DateTime? createdAt,
  })  : packages = packages ?? [],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  String phone; // digits
  String address;
  String type;
  String notes;
  double? lat;
  double? lng;
  double points; // loyalty points
  final List<CustPackage> packages;
  final DateTime createdAt;

  bool get hasLocation => lat != null && lng != null;
  CustPackage? activePackage(String service, String unit) => packages
      .where((p) => p.service == service && p.unit == unit && p.remaining > 0 && p.end.isAfter(DateTime.now()))
      .firstOrNull;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'type': type,
        'notes': notes,
        'lat': lat,
        'lng': lng,
        'points': points,
        'packages': packages.map((p) => p.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };
  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        address: j['address'] as String? ?? '',
        type: j['type'] as String? ?? 'regular',
        notes: j['notes'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        points: (j['points'] as num?)?.toDouble() ?? 0,
        packages: ((j['packages'] as List?) ?? []).map((e) => CustPackage.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
      );
}

/// A package a customer bought (e.g. 30 kg wash & fold for 30 days).
class CustPackage {
  CustPackage({
    required this.id,
    required this.name,
    required this.service,
    required this.unit,
    required this.credits,
    required this.remaining,
    required this.price,
    required this.start,
    required this.end,
  });
  final String id;
  final String name;
  final String service;
  final String unit; // kg | pc
  final double credits;
  double remaining;
  final double price;
  final DateTime start;
  final DateTime end;
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'service': service,
        'unit': unit,
        'credits': credits,
        'remaining': remaining,
        'price': price,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      };
  factory CustPackage.fromJson(Map<String, dynamic> j) => CustPackage(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        service: j['service'] as String? ?? '',
        unit: j['unit'] as String? ?? 'kg',
        credits: (j['credits'] as num?)?.toDouble() ?? 0,
        remaining: (j['remaining'] as num?)?.toDouble() ?? 0,
        price: (j['price'] as num?)?.toDouble() ?? 0,
        start: DateTime.tryParse(j['start'] as String? ?? '') ?? DateTime.now(),
        end: DateTime.tryParse(j['end'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Shop offers (owner): coupons and packages for sale.
class Coupon {
  Coupon({required this.id, required this.code, required this.kind, required this.value, this.minOrder = 0, this.validTill, this.onlyNew = false, this.active = true});
  final String id;
  String code;
  String kind; // pct | flat
  double value;
  double minOrder;
  DateTime? validTill;
  bool onlyNew;
  bool active;
  bool get valid => active && (validTill == null || validTill!.isAfter(DateTime.now()));
  double discountOn(double amount) {
    if (!valid || amount < minOrder) return 0;
    return kind == 'pct' ? (amount * value / 100).roundToDouble() : (value > amount ? amount : value);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'kind': kind,
        'value': value,
        'minOrder': minOrder,
        'validTill': validTill?.toIso8601String(),
        'onlyNew': onlyNew,
        'active': active,
      };
  factory Coupon.fromJson(Map<String, dynamic> j) => Coupon(
        id: j['id'] as String,
        code: j['code'] as String? ?? '',
        kind: j['kind'] as String? ?? 'pct',
        value: (j['value'] as num?)?.toDouble() ?? 0,
        minOrder: (j['minOrder'] as num?)?.toDouble() ?? 0,
        validTill: DateTime.tryParse(j['validTill'] as String? ?? ''),
        onlyNew: j['onlyNew'] as bool? ?? false,
        active: j['active'] as bool? ?? true,
      );
}

class PackagePlan {
  PackagePlan({required this.id, required this.name, required this.service, required this.unit, required this.credits, required this.price, this.days = 30});
  final String id;
  String name;
  String service;
  String unit;
  double credits;
  double price;
  int days;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'service': service, 'unit': unit, 'credits': credits, 'price': price, 'days': days};
  factory PackagePlan.fromJson(Map<String, dynamic> j) => PackagePlan(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        service: j['service'] as String? ?? '',
        unit: j['unit'] as String? ?? 'kg',
        credits: (j['credits'] as num?)?.toDouble() ?? 0,
        price: (j['price'] as num?)?.toDouble() ?? 0,
        days: (j['days'] as num?)?.toInt() ?? 30,
      );
}

/// Stock (owner): items, movements, suppliers.
class StockItem {
  StockItem({required this.id, required this.name, required this.unit, this.qty = 0, this.minQty = 0, this.branchId = ''});
  final String id;
  String name;
  String unit;
  double qty;
  double minQty;
  String branchId;
  bool get low => qty <= minQty;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'unit': unit, 'qty': qty, 'minQty': minQty, 'branchId': branchId};
  factory StockItem.fromJson(Map<String, dynamic> j) => StockItem(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        unit: j['unit'] as String? ?? 'pc',
        qty: (j['qty'] as num?)?.toDouble() ?? 0,
        minQty: (j['minQty'] as num?)?.toDouble() ?? 0,
        branchId: j['branchId'] as String? ?? '',
      );
}

class StockMove {
  StockMove({required this.id, required this.itemId, required this.qty, required this.at, this.by = '', this.supplierId = '', this.cost = 0, this.note = ''});
  final String id;
  final String itemId;
  final double qty; // + in, − used
  final DateTime at;
  final String by;
  final String supplierId;
  final double cost;
  final String note;
  Map<String, dynamic> toJson() =>
      {'id': id, 'itemId': itemId, 'qty': qty, 'at': at.toIso8601String(), 'by': by, 'supplierId': supplierId, 'cost': cost, 'note': note};
  factory StockMove.fromJson(Map<String, dynamic> j) => StockMove(
        id: j['id'] as String,
        itemId: j['itemId'] as String? ?? '',
        qty: (j['qty'] as num?)?.toDouble() ?? 0,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        by: j['by'] as String? ?? '',
        supplierId: j['supplierId'] as String? ?? '',
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
        note: j['note'] as String? ?? '',
      );
}

class Supplier {
  Supplier({required this.id, required this.name, this.phone = '', this.items = ''});
  final String id;
  String name;
  String phone;
  String items;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'items': items};
  factory Supplier.fromJson(Map<String, dynamic> j) =>
      Supplier(id: j['id'] as String, name: j['name'] as String? ?? '', phone: j['phone'] as String? ?? '', items: j['items'] as String? ?? '');
}

/// One garment type on the rate card. `unit` is 'pc' or 'kg' (or 'sqft').
class Garment {
  Garment({required this.id, required this.name, this.unit = 'pc', this.category = 'Men'});
  final String id;
  String name;
  String unit;
  String category; // Men | Women | Kids | Household | Other
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'unit': unit, 'category': category};
  factory Garment.fromJson(Map<String, dynamic> j) => Garment(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        unit: j['unit'] as String? ?? 'pc',
        category: j['category'] as String? ?? 'Other',
      );
}

class OrderLine {
  OrderLine({
    required this.garment,
    required this.service,
    required this.qty,
    required this.rate,
    this.unit = 'pc',
    this.note = '',
  });
  String garment;
  String service;
  double qty;
  double rate;
  String unit;
  String note; // stain, colour, damage…
  double get amount => qty * rate;
  int get pieces => unit == 'pc' ? qty.round() : 1;

  Map<String, dynamic> toJson() =>
      {'garment': garment, 'service': service, 'qty': qty, 'rate': rate, 'unit': unit, 'note': note};
  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        garment: j['garment'] as String? ?? '',
        service: j['service'] as String? ?? '',
        qty: (j['qty'] as num?)?.toDouble() ?? 1,
        rate: (j['rate'] as num?)?.toDouble() ?? 0,
        unit: j['unit'] as String? ?? 'pc',
        note: j['note'] as String? ?? '',
      );
}

class Payment {
  Payment({required this.amount, required this.mode, required this.at, this.by = '', this.note = ''});
  final double amount;
  final String mode; // cash | upi | card
  final DateTime at;
  final String by; // staff id or 'owner'
  final String note;
  Map<String, dynamic> toJson() => {'amount': amount, 'mode': mode, 'at': at.toIso8601String(), 'by': by, 'note': note};
  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        mode: j['mode'] as String? ?? 'cash',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        by: j['by'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

class StatusEvent {
  StatusEvent({required this.status, required this.at, this.by = '', this.note = ''});
  final String status;
  final DateTime at;
  final String by;
  final String note;
  Map<String, dynamic> toJson() => {'status': status, 'at': at.toIso8601String(), 'by': by, 'note': note};
  factory StatusEvent.fromJson(Map<String, dynamic> j) => StatusEvent(
        status: j['status'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        by: j['by'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

class LaundryOrder {
  LaundryOrder({
    required this.id,
    required this.number,
    required this.customerId,
    required this.branchId,
    required this.lines,
    required this.createdAt,
    required this.dueAt,
    this.status = 'received',
    this.express = false,
    this.homeDelivery = false,
    this.discount = 0,
    this.taxPct = 0,
    this.expressPct = 50,
    this.pickupAgent = '',
    this.deliveryAgent = '',
    this.rack = '',
    this.notes = '',
    this.createdBy = '',
    this.proof,
    this.couponCode = '',
    this.couponAmount = 0,
    this.pointsUsed = 0,
    this.packageValue = 0,
    this.packageNote = '',
    this.slot = '',
    this.pickupAt,
    List<Payment>? payments,
    List<StatusEvent>? history,
  })  : payments = payments ?? [],
        history = history ?? [];

  final String id;
  final int number;
  String customerId;
  String branchId;
  List<OrderLine> lines;
  final DateTime createdAt;
  DateTime dueAt;
  String status;
  bool express;
  bool homeDelivery;
  double discount; // money
  double taxPct;
  double expressPct;
  String pickupAgent;
  String deliveryAgent;
  String rack;
  String notes;
  String createdBy;
  Ping? proof; // where the order was handed over (delivery proof)
  String couponCode;
  double couponAmount;
  double pointsUsed; // money value of loyalty points used
  double packageValue; // value covered by the customer's package
  String packageNote;
  String slot; // pickup slot e.g. 12–3
  DateTime? pickupAt;
  double get offers => couponAmount + pointsUsed + packageValue;
  final List<Payment> payments;
  final List<StatusEvent> history;

  String get code => 'LD-${number.toString().padLeft(4, '0')}';
  double get subtotal => lines.fold(0, (s, l) => s + l.amount);
  double get expressCharge => express ? subtotal * expressPct / 100 : 0;
  double get taxable => (subtotal + expressCharge - discount - offers).clamp(0, double.infinity).toDouble();
  double get tax => taxable * taxPct / 100;
  double get total => (taxable + tax).roundToDouble();
  double get paid => payments.fold(0, (s, p) => s + p.amount);
  double get due => (total - paid).clamp(0, double.infinity).toDouble();
  int get pieces => lines.fold(0, (s, l) => s + l.pieces);
  bool get open => status != 'delivered' && status != 'cancelled';
  bool get late => open && DateTime.now().isAfter(dueAt);

  /// One tag per piece: LD-0012 · 3/7
  List<String> get tags {
    final n = pieces;
    return [for (var i = 1; i <= n; i++) '$code · $i/$n'];
  }

  DateTime? timeOf(String s) {
    for (final e in history.reversed) {
      if (e.status == s) return e.at;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'customerId': customerId,
        'branchId': branchId,
        'lines': lines.map((l) => l.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt.toIso8601String(),
        'status': status,
        'express': express,
        'homeDelivery': homeDelivery,
        'discount': discount,
        'taxPct': taxPct,
        'expressPct': expressPct,
        'pickupAgent': pickupAgent,
        'deliveryAgent': deliveryAgent,
        'rack': rack,
        'notes': notes,
        'createdBy': createdBy,
        'proof': proof?.toJson(),
        'couponCode': couponCode,
        'couponAmount': couponAmount,
        'pointsUsed': pointsUsed,
        'packageValue': packageValue,
        'packageNote': packageNote,
        'slot': slot,
        'pickupAt': pickupAt?.toIso8601String(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'history': history.map((h) => h.toJson()).toList(),
      };

  factory LaundryOrder.fromJson(Map<String, dynamic> j) => LaundryOrder(
        id: j['id'] as String,
        number: (j['number'] as num?)?.toInt() ?? 0,
        customerId: j['customerId'] as String? ?? '',
        branchId: j['branchId'] as String? ?? '',
        lines: ((j['lines'] as List?) ?? []).map((e) => OrderLine.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        dueAt: DateTime.tryParse(j['dueAt'] as String? ?? '') ?? DateTime.now(),
        status: j['status'] as String? ?? 'received',
        express: j['express'] as bool? ?? false,
        homeDelivery: j['homeDelivery'] as bool? ?? false,
        discount: (j['discount'] as num?)?.toDouble() ?? 0,
        taxPct: (j['taxPct'] as num?)?.toDouble() ?? 0,
        expressPct: (j['expressPct'] as num?)?.toDouble() ?? 50,
        pickupAgent: j['pickupAgent'] as String? ?? '',
        deliveryAgent: j['deliveryAgent'] as String? ?? '',
        rack: j['rack'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        createdBy: j['createdBy'] as String? ?? '',
        proof: j['proof'] is Map ? Ping.fromJson(Map<String, dynamic>.from(j['proof'] as Map)) : null,
        couponCode: j['couponCode'] as String? ?? '',
        couponAmount: (j['couponAmount'] as num?)?.toDouble() ?? 0,
        pointsUsed: (j['pointsUsed'] as num?)?.toDouble() ?? 0,
        packageValue: (j['packageValue'] as num?)?.toDouble() ?? 0,
        packageNote: j['packageNote'] as String? ?? '',
        slot: j['slot'] as String? ?? '',
        pickupAt: DateTime.tryParse(j['pickupAt'] as String? ?? ''),
        payments: ((j['payments'] as List?) ?? []).map((e) => Payment.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        history: ((j['history'] as List?) ?? []).map((e) => StatusEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

class Staff {
  Staff({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.branchId,
    required this.pinHash,
    this.salary = 0,
    this.active = true,
  });
  final String id;
  String name;
  String phone;
  Role role;
  String branchId;
  String pinHash; // sha256("<shopCode>:<last 10 digits of phone>:<pin>"), see staffKey()
  double salary;
  bool active;

  String get initials {
    final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'role': role.name,
        'branchId': branchId,
        'pinHash': pinHash,
        'salary': salary,
        'active': active,
      };
  factory Staff.fromJson(Map<String, dynamic> j) => Staff(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        role: roleFrom(j['role'] as String? ?? 'counter'),
        branchId: j['branchId'] as String? ?? '',
        pinHash: j['pinHash'] as String? ?? (j['pin'] is String ? 'plain:${j['pin']}' : ''),
        salary: (j['salary'] as num?)?.toDouble() ?? 0,
        active: j['active'] as bool? ?? true,
      );
}

class Attendance {
  Attendance({required this.staffId, required this.day, required this.inAt, this.outAt});
  final String staffId;
  final String day; // yyyy-mm-dd
  final DateTime inAt;
  DateTime? outAt;
  Map<String, dynamic> toJson() =>
      {'staffId': staffId, 'day': day, 'inAt': inAt.toIso8601String(), 'outAt': outAt?.toIso8601String()};
  factory Attendance.fromJson(Map<String, dynamic> j) => Attendance(
        staffId: j['staffId'] as String? ?? '',
        day: j['day'] as String? ?? '',
        inAt: DateTime.tryParse(j['inAt'] as String? ?? '') ?? DateTime.now(),
        outAt: DateTime.tryParse(j['outAt'] as String? ?? ''),
      );
}

class Expense {
  Expense({
    required this.id,
    required this.branchId,
    required this.category,
    required this.amount,
    required this.at,
    this.note = '',
  });
  final String id;
  String branchId;
  String category;
  double amount;
  DateTime at;
  String note;
  Map<String, dynamic> toJson() =>
      {'id': id, 'branchId': branchId, 'category': category, 'amount': amount, 'at': at.toIso8601String(), 'note': note};
  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String,
        branchId: j['branchId'] as String? ?? '',
        category: j['category'] as String? ?? 'Other',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        note: j['note'] as String? ?? '',
      );
}

/// Who did what, for staff tracking.
class Activity {
  Activity({required this.by, required this.kind, required this.at, this.orderId = '', this.text = ''});
  final String by; // staff id or 'owner'
  final String kind; // order.new | status.<s> | pay | checkin | checkout | delivery.done | pickup.done
  final DateTime at;
  final String orderId;
  final String text;
  String get id => '${at.microsecondsSinceEpoch}_${by}_$kind';
  Map<String, dynamic> toJson() => {'by': by, 'kind': kind, 'at': at.toIso8601String(), 'orderId': orderId, 'text': text};
  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        by: j['by'] as String? ?? '',
        kind: j['kind'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        orderId: j['orderId'] as String? ?? '',
        text: j['text'] as String? ?? '',
      );
}

String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One GPS point of a delivery person.
class Ping {
  Ping({required this.lat, required this.lng, required this.at, this.orderId = ''});
  final double lat;
  final double lng;
  final DateTime at;
  final String orderId;

  String get mapUrl => 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'at': at.toIso8601String(), 'orderId': orderId};
  factory Ping.fromJson(Map<String, dynamic> j) => Ping(
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        orderId: j['orderId'] as String? ?? '',
      );
}

/// Last 10 digits of a phone number (staff login key).
String phone10(String s) {
  final d = s.replaceAll(RegExp(r'[^0-9]'), '');
  return d.length > 10 ? d.substring(d.length - 10) : d;
}
