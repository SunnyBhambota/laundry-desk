import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'issue_models.dart';
import 'ops_models.dart';
import 'shop_data.dart';

/// Keeps a [ShopData] in step with Firestore, one document per record:
///
///   shops/{ownerUid}/branches|customers|garments|orders|staff|attendance|expenses|activity|pings/{id}
///   shops/{ownerUid}/meta/settings   (owner only)
///   shops/{ownerUid}/meta/counter    (next order number; staff may update)
///   staffKeys/{shopCode}             (staff PIN hashes; never readable by the app, used by rules)
///
/// Only changed records are written, so two phones working at the same time don't
/// overwrite each other's orders. Remote changes arrive through snapshot listeners.
class CloudSync {
  CloudSync(this.d);

  final ShopData d;

  /// false for staff: they may not write settings, staff, branches, rates or expenses.
  bool admin = true;

  static const adminCols = {'branches', 'garments', 'staff', 'expenses', 'payouts', 'coupons', 'packagePlans', 'stock', 'stockMoves', 'suppliers'};
  static const memberCols = {'customers', 'orders', 'attendance', 'activity', 'pings', 'issues', 'requests', 'stockUses', 'notices', 'cashDays'};
  static const allCols = [...adminCols, ...memberCols];

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get _shop => _fs.collection('shops').doc(d.ownerUid);

  final Map<String, String> _synced = {}; // "col/id" → canonical json
  String _syncedKeys = '';
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _pushing = false;
  bool _again = false;
  bool _applying = false;

  /// true while changes are being sent.
  bool get busy => _pushing;

  /// Shown in More → Cloud: last good sync and last problem.
  DateTime? lastOk;
  String lastError = '';

  // ---------------- canonical json ----------------

  static Object? _canon(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canon(v[k])};
    }
    if (v is List) return v.map(_canon).toList();
    if (v is int) return v.toDouble();
    return v;
  }

  static String enc(Object? v) => jsonEncode(_canon(v));

  // ---------------- local records ----------------

  Map<String, Map<String, dynamic>> _records() {
    final m = <String, Map<String, dynamic>>{};
    for (final x in d.branches) {
      m['branches/${x.id}'] = x.toJson();
    }
    for (final x in d.customers) {
      m['customers/${x.id}'] = x.toJson();
    }
    for (final x in d.garments) {
      m['garments/${x.id}'] = x.toJson();
    }
    for (final x in d.orders) {
      m['orders/${x.id}'] = x.toJson();
    }
    for (final x in d.staff) {
      m['staff/${x.id}'] = x.toJson();
    }
    for (final x in d.attendance) {
      m['attendance/${x.staffId}_${x.day}'] = x.toJson();
    }
    for (final x in d.expenses) {
      m['expenses/${x.id}'] = x.toJson();
    }
    for (final x in d.activity) {
      m['activity/${x.id}'] = x.toJson();
    }
    for (final x in d.issues) {
      m['issues/${x.id}'] = x.toJson();
    }
    for (final x in d.payouts) {
      m['payouts/${x.id}'] = x.toJson();
    }
    for (final x in d.coupons) {
      m['coupons/${x.id}'] = x.toJson();
    }
    for (final x in d.packagePlans) {
      m['packagePlans/${x.id}'] = x.toJson();
    }
    for (final x in d.stock) {
      m['stock/${x.id}'] = x.toJson();
    }
    for (final x in d.stockMoves) {
      m['stockMoves/${x.id}'] = x.toJson();
    }
    for (final x in d.suppliers) {
      m['suppliers/${x.id}'] = x.toJson();
    }
    for (final x in d.requests) {
      m['requests/${x.id}'] = x.toJson();
    }
    for (final x in d.stockUses) {
      m['stockUses/${x.id}'] = x.toJson();
    }
    for (final x in d.notices) {
      m['notices/${x.id}'] = x.toJson();
    }
    for (final x in d.cashDays) {
      m['cashDays/${x.id}'] = x.toJson();
    }
    d.pings.forEach((k, v) => m['pings/$k'] = {'list': v.map((p) => p.toJson()).toList()});
    m['meta/settings'] = d.settingsJson();
    m['meta/counter'] = {'nextNumber': d.nextNumber};
    return m;
  }

  bool _allowed(String key) {
    final col = key.split('/').first;
    if (key == 'meta/counter') return true;
    if (key == 'meta/settings') return admin;
    if (adminCols.contains(col)) return admin;
    return memberCols.contains(col);
  }

  void _apply(String col, String id, Map<String, dynamic>? j) {
    void put<T>(List<T> list, T Function(Map<String, dynamic>) from, bool Function(T) same) {
      final i = list.indexWhere(same);
      if (j == null) {
        if (i >= 0) list.removeAt(i);
      } else if (i >= 0) {
        list[i] = from(j);
      } else {
        list.add(from(j));
      }
    }

    switch (col) {
      case 'branches':
        put<Branch>(d.branches, Branch.fromJson, (x) => x.id == id);
      case 'customers':
        put<Customer>(d.customers, Customer.fromJson, (x) => x.id == id);
      case 'garments':
        put<Garment>(d.garments, Garment.fromJson, (x) => x.id == id);
      case 'orders':
        put<LaundryOrder>(d.orders, LaundryOrder.fromJson, (x) => x.id == id);
      case 'staff':
        put<Staff>(d.staff, Staff.fromJson, (x) => x.id == id);
      case 'attendance':
        put<Attendance>(d.attendance, Attendance.fromJson, (x) => '${x.staffId}_${x.day}' == id);
      case 'expenses':
        put<Expense>(d.expenses, Expense.fromJson, (x) => x.id == id);
      case 'activity':
        put<Activity>(d.activity, Activity.fromJson, (x) => x.id == id);
      case 'issues':
        put<Issue>(d.issues, Issue.fromJson, (x) => x.id == id);
      case 'payouts':
        put<Payout>(d.payouts, Payout.fromJson, (x) => x.id == id);
      case 'coupons':
        put<Coupon>(d.coupons, Coupon.fromJson, (x) => x.id == id);
      case 'packagePlans':
        put<PackagePlan>(d.packagePlans, PackagePlan.fromJson, (x) => x.id == id);
      case 'stock':
        put<StockItem>(d.stock, StockItem.fromJson, (x) => x.id == id);
      case 'stockMoves':
        put<StockMove>(d.stockMoves, StockMove.fromJson, (x) => x.id == id);
      case 'suppliers':
        put<Supplier>(d.suppliers, Supplier.fromJson, (x) => x.id == id);
      case 'requests':
        put<StaffRequest>(d.requests, StaffRequest.fromJson, (x) => x.id == id);
      case 'stockUses':
        put<StockUse>(d.stockUses, StockUse.fromJson, (x) => x.id == id);
      case 'notices':
        put<Notice>(d.notices, Notice.fromJson, (x) => x.id == id);
      case 'cashDays':
        put<CashDay>(d.cashDays, CashDay.fromJson, (x) => x.id == id);
      case 'pings':
        if (j == null) {
          d.pings.remove(id);
        } else {
          d.pings[id] = ((j['list'] as List?) ?? []).map((e) => Ping.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        }
      case 'meta':
        if (j == null) return;
        if (id == 'settings') d.applySettings(j);
        if (id == 'counter') {
          final n = (j['nextNumber'] as num?)?.toInt() ?? 1;
          if (n > d.nextNumber) d.nextNumber = n;
        }
    }
  }

  // ---------------- start ----------------

  /// Reads everything once. Returns false when the shop has no cloud data yet.
  Future<bool> pull() async {
    final settings = await _shop.collection('meta').doc('settings').get();
    if (!settings.exists && admin) {
      // settings may be missing while records exist (older versions): still load them
      final any = await _shop.collection('branches').limit(1).get();
      if (any.docs.isEmpty) return false;
    }
    _applying = true;
    try {
      for (final col in [...allCols, 'meta']) {
        final qs = await _shop.collection(col).get();
        _clear(col);
        for (final doc in qs.docs) {
          _apply(col, doc.id, doc.data());
          _synced['$col/${doc.id}'] = enc(doc.data());
        }
      }
    } finally {
      _applying = false;
    }
    lastOk = DateTime.now();
    return true;
  }

  void _clear(String col) {
    switch (col) {
      case 'branches':
        d.branches.clear();
      case 'customers':
        d.customers.clear();
      case 'garments':
        d.garments.clear();
      case 'orders':
        d.orders.clear();
      case 'staff':
        d.staff.clear();
      case 'attendance':
        d.attendance.clear();
      case 'expenses':
        d.expenses.clear();
      case 'activity':
        d.activity.clear();
      case 'pings':
        d.pings.clear();
      case 'issues':
        d.issues.clear();
      case 'payouts':
        d.payouts.clear();
      case 'coupons':
        d.coupons.clear();
      case 'packagePlans':
        d.packagePlans.clear();
      case 'stock':
        d.stock.clear();
      case 'stockMoves':
        d.stockMoves.clear();
      case 'suppliers':
        d.suppliers.clear();
      case 'requests':
        d.requests.clear();
      case 'stockUses':
        d.stockUses.clear();
      case 'notices':
        d.notices.clear();
      case 'cashDays':
        d.cashDays.clear();
    }
  }

  void listen() {
    stop();
    for (final col in [...allCols, 'meta']) {
      _subs.add(_shop.collection(col).snapshots().listen((qs) {
        var changed = false;
        _applying = true;
        try {
          for (final ch in qs.docChanges) {
            final key = '$col/${ch.doc.id}';
            if (ch.type == DocumentChangeType.removed) {
              if (_synced.remove(key) != null) {
                _apply(col, ch.doc.id, null);
                changed = true;
              }
              continue;
            }
            final data = ch.doc.data();
            if (data == null) continue;
            final e = enc(data);
            if (_synced[key] == e) continue;
            _synced[key] = e;
            _apply(col, ch.doc.id, data);
            changed = true;
          }
        } finally {
          _applying = false;
        }
        if (changed) d.remoteChanged();
      }, onError: (_) {}));
    }
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  // ---------------- push ----------------

  Future<void> push() async {
    if (_applying) return;
    if (_pushing) {
      _again = true;
      return;
    }
    _pushing = true;
    try {
      do {
        _again = false;
        await _pushOnce();
      } while (_again);
      lastOk = DateTime.now();
      lastError = '';
    } catch (e) {
      // offline or denied: Firestore keeps offline writes; retried on next change
      lastError = e is FirebaseException ? (e.code) : e.toString();
    } finally {
      _pushing = false;
    }
  }

  Future<void> _pushOnce() async {
    final now = _records();
    final writes = <String, Map<String, dynamic>?>{};
    now.forEach((k, v) {
      if (!_allowed(k)) return;
      final e = enc(v);
      if (_synced[k] != e) writes[k] = v;
    });
    for (final k in _synced.keys.toList()) {
      if (!now.containsKey(k) && _allowed(k)) writes[k] = null;
    }
    // staff PIN hashes for staff login rules (owner only)
    Map<String, String>? keys;
    if (admin && d.shopCode.isNotEmpty) {
      keys = {for (final s in d.staff.where((s) => s.active && !s.pinHash.startsWith('plain:'))) phone10(s.phone): s.pinHash};
      if (enc(keys) == _syncedKeys) keys = null;
    }
    if (writes.isEmpty && keys == null) return;

    // Settings + counter first (small, and other phones need them to open the shop).
    final entries = [
      ...writes.entries.where((e) => e.key.startsWith('meta/')),
      ...writes.entries.where((e) => !e.key.startsWith('meta/')),
    ];
    final failed = <String>[];
    for (var i = 0; i < entries.length; i += 400) {
      final chunk = entries.skip(i).take(400).toList();
      try {
        final b = _fs.batch();
        for (final e in chunk) {
          final parts = e.key.split('/');
          final ref = _shop.collection(parts[0]).doc(parts[1]);
          e.value == null ? b.delete(ref) : b.set(ref, e.value!);
        }
        if (i == 0 && keys != null) {
          b.set(_fs.collection('staffKeys').doc(d.shopCode), {'ownerUid': d.ownerUid, 'keys': keys});
        }
        await b.commit();
        for (final e in chunk) {
          e.value == null ? _synced.remove(e.key) : _synced[e.key] = enc(e.value);
        }
      } catch (_) {
        // One bad record must not block the rest: write them one by one.
        for (final e in chunk) {
          try {
            final parts = e.key.split('/');
            final ref = _shop.collection(parts[0]).doc(parts[1]);
            if (e.value == null) {
              await ref.delete();
            } else {
              await ref.set(e.value!);
            }
            e.value == null ? _synced.remove(e.key) : _synced[e.key] = enc(e.value);
          } catch (err) {
            failed.add('${e.key}: ${err is FirebaseException ? err.code : err}');
          }
        }
        if (i == 0 && keys != null) {
          try {
            await _fs.collection('staffKeys').doc(d.shopCode).set({'ownerUid': d.ownerUid, 'keys': keys});
          } catch (err) {
            failed.add('staffKeys: ${err is FirebaseException ? err.code : err}');
            keys = null;
          }
        }
      }
    }
    if (entries.isEmpty && keys != null) {
      await _fs.collection('staffKeys').doc(d.shopCode).set({'ownerUid': d.ownerUid, 'keys': keys});
    }
    if (keys != null) _syncedKeys = enc(keys);
    if (failed.isNotEmpty) throw StateError('${failed.length} not saved – ${failed.take(3).join('; ')}');
  }
}
