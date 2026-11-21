import 'ops_models.dart';
import 'shop_data.dart';

/// v0.13: memberships, repeat pickups, pickup slot limit, order notes, smart rack.
extension ShopV13 on ShopData {
  // ---------- memberships ----------
  /// Packages that are about to end (7 days) or nearly used up (20% left), or ended in the last 30 days.
  List<(Customer, CustPackage)> get membershipsToRenew {
    final now = DateTime.now();
    final out = <(Customer, CustPackage)>[];
    for (final c in customers) {
      // only the newest package of each plan matters
      final seen = <String>{};
      for (final p in c.packages.reversed) {
        if (!seen.add(p.name)) continue;
        final ended = p.end.isBefore(now);
        final soon = p.end.difference(now).inDays <= 7;
        final low = p.credits > 0 && p.remaining / p.credits <= 0.2;
        if ((ended && now.difference(p.end).inDays <= 30) || (!ended && (soon || low))) out.add((c, p));
      }
    }
    out.sort((a, b) => a.$2.end.compareTo(b.$2.end));
    return out;
  }

  List<(Customer, CustPackage)> get activeMemberships {
    final now = DateTime.now();
    return [
      for (final c in customers)
        for (final p in c.packages)
          if (p.end.isAfter(now) && p.remaining > 0) (c, p)
    ]..sort((a, b) => a.$2.end.compareTo(b.$2.end));
  }

  PackagePlan? planOf(CustPackage p) => packagePlans.where((x) => x.name == p.name).firstOrNull;

  // ---------- repeat pickups ----------
  void setRepeat(Customer c, {required int every, required String slot}) {
    c.repeat = {'every': every, 'slot': slot, 'next': DateTime.now().add(Duration(days: every)).toIso8601String()};
    changed();
  }

  void clearRepeat(Customer c) {
    c.repeat = null;
    changed();
  }

  DateTime? repeatNext(Customer c) => DateTime.tryParse(c.repeat?['next'] as String? ?? '');

  /// Customers whose regular pickup is due today / overdue / tomorrow.
  List<Customer> get repeatsDue {
    final lim = DateTime.now().add(const Duration(days: 1));
    return customers.where((c) {
      final n = repeatNext(c);
      return n != null && n.isBefore(DateTime(lim.year, lim.month, lim.day + 1));
    }).toList()
      ..sort((a, b) => repeatNext(a)!.compareTo(repeatNext(b)!));
  }

  void repeatDone(Customer c) {
    final every = (c.repeat?['every'] as num?)?.toInt() ?? 7;
    c.repeat = {...?c.repeat, 'next': DateTime.now().add(Duration(days: every)).toIso8601String()};
    changed();
  }

  // ---------- pickup slot limit ----------
  /// Pickups waiting in a slot right now.
  int slotBooked(String slot) => orders.where((o) => o.status == 'pickup' && o.slot == slot).length;
  bool slotFull(String slot) => slotLimit > 0 && slotBooked(slot) >= slotLimit;

  // ---------- smart rack ----------
  static int? rackNo(String rack) {
    final m = RegExp(r'(\d+)\s*$').firstMatch(rack.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// rack number -> orders kept there (open orders that already have a rack).
  Map<int, List<LaundryOrder>> get rackMap {
    final m = <int, List<LaundryOrder>>{};
    for (final o in orders) {
      if (!o.open || o.rack.trim().isEmpty) continue;
      final n = rackNo(o.rack);
      if (n != null) m.putIfAbsent(n, () => []).add(o);
    }
    return m;
  }

  List<int> get freeRacks {
    final used = rackMap.keys.toSet();
    return [for (var i = 1; i <= rackCount; i++) if (!used.contains(i)) i];
  }

  // ---------- order notes ----------
  void addChat(LaundryOrder o, {required String from, required String text, required String by}) {
    if (text.trim().isEmpty) return;
    o.chat.add({'from': from, 'text': text.trim(), 'at': DateTime.now().toIso8601String(), 'by': by});
    log(by, 'chat', orderId: o.id, text: '${o.code}: ${text.trim()}');
    changed();
  }
}
