import 'dart:math';

import 'ops_models.dart';
import 'shop_data.dart';

/// Demo data so the owner can explore every screen. All ids start with "demo_"
/// so More → Sample data → Clear removes exactly these.
class SampleData {
  SampleData._();

  static const _names = [
    'Priya Sharma', 'Rahul Verma', 'Anjali Mehta', 'Vikram Singh', 'Neha Gupta', 'Arjun Nair', 'Sneha Patil',
    'Rohit Kapoor', 'Kavya Iyer', 'Aman Joshi', 'Pooja Reddy', 'Sanjay Malhotra', 'Ritu Bansal', 'Karan Chopra',
    'Meera Pillai', 'Hotel Sea Breeze', 'Fitness First Gym', 'Dr. Asha Rao',
  ];
  static const _areas = [
    'Andheri West', 'Lokhandwala', 'Versova', 'Juhu', 'Bandra West', 'Khar', 'Powai', 'Hiranandani', 'Chandivali',
  ];

  static void fill(ShopData d, {required List<String> services}) {
    final r = Random(7);
    final now = DateTime.now();
    final main = d.branches.first.id;

    // branches
    final b2 = Branch(id: 'demo_b2', name: 'Bandra', address: 'Hill Road, Bandra West');
    final b3 = Branch(id: 'demo_b3', name: 'Powai', address: 'Hiranandani Gardens, Powai');
    d.branches.addAll([b2, b3]);
    final bIds = [main, main, b2.id, b3.id];

    // staff
    final staff = [
      Staff(id: 'demo_s1', name: 'Sunita Kale', phone: '9820011111', role: Role.manager, branchId: main, pin: '1111', salary: 22000),
      Staff(id: 'demo_s2', name: 'Imran Shaikh', phone: '9820022222', role: Role.counter, branchId: b2.id, pin: '2222', salary: 15000),
      Staff(id: 'demo_s3', name: 'Ravi Pawar', phone: '9820033333', role: Role.washer, branchId: main, pin: '3333', salary: 14000),
      Staff(id: 'demo_s4', name: 'Arjun More', phone: '9820044444', role: Role.delivery, branchId: main, pin: '4444', salary: 13000),
      Staff(id: 'demo_s5', name: 'Deepak Yadav', phone: '9820055555', role: Role.delivery, branchId: b2.id, pin: '5555', salary: 13000),
      Staff(id: 'demo_s6', name: 'Neha Salvi', phone: '9820066666', role: Role.counter, branchId: b3.id, pin: '6666', salary: 15000),
    ];
    d.staff.addAll(staff);
    final counters = ['owner', 'demo_s1', 'demo_s2', 'demo_s6'];
    final drivers = ['demo_s4', 'demo_s5'];

    // customers
    for (var i = 0; i < _names.length; i++) {
      d.customers.add(Customer(
        id: 'demo_c$i',
        name: _names[i],
        phone: '98${(10000000 + r.nextInt(89999999))}',
        address: '${r.nextInt(80) + 1}, ${_areas[i % _areas.length]}, Mumbai',
        type: i >= 15 ? 'business' : (i % 5 == 0 ? 'vip' : 'regular'),
        createdAt: now.subtract(Duration(days: 40 + r.nextInt(60))),
      ));
    }

    // orders over the last 30 days
    final rateKeys = d.rates.keys.where((k) => services.any((s) => k.endsWith('|$s'))).toList();
    if (rateKeys.isEmpty) return;
    var n = 0;
    for (var day = 29; day >= 0; day--) {
      final perDay = day == 0 ? 7 : 2 + r.nextInt(4);
      for (var k = 0; k < perDay; k++) {
        n++;
        final created = DateTime(now.year, now.month, now.day, 9 + r.nextInt(10), r.nextInt(60))
            .subtract(Duration(days: day));
        final createdAt = created.isAfter(now) ? now.subtract(Duration(minutes: 10 * (k + 1))) : created;
        final cust = d.customers[r.nextInt(d.customers.length)];
        final lines = <OrderLine>[];
        final lineCount = 1 + r.nextInt(3);
        for (var l = 0; l < lineCount; l++) {
          final key = rateKeys[r.nextInt(rateKeys.length)];
          final parts = key.split('|');
          final g = d.garment(parts[0])!;
          lines.add(OrderLine(
            garment: g.name,
            service: parts[1],
            qty: g.unit == 'kg' ? (2 + r.nextInt(6)).toDouble() : (g.unit == 'sqft' ? 20 : (1 + r.nextInt(4)).toDouble()),
            rate: d.rates[key]!,
            unit: g.unit,
            note: r.nextInt(9) == 0 ? 'Oil stain on sleeve' : '',
          ));
        }
        final home = r.nextInt(3) == 0;
        final by = counters[r.nextInt(counters.length)];
        final o = LaundryOrder(
          id: 'demo_o$n',
          number: d.nextNumber++,
          customerId: cust.id,
          branchId: bIds[r.nextInt(bIds.length)],
          lines: lines,
          createdAt: createdAt,
          dueAt: createdAt.add(const Duration(days: 2)),
          express: r.nextInt(8) == 0,
          homeDelivery: home,
          discount: r.nextInt(6) == 0 ? 20 : 0,
          taxPct: d.taxPct,
          expressPct: d.expressPct,
          createdBy: by,
          deliveryAgent: home ? drivers[r.nextInt(2)] : '',
          rack: 'R${1 + r.nextInt(12)}',
        );
        // how far it got
        final List<String> path;
        if (day >= 3) {
          path = r.nextInt(25) == 0 ? ['received', 'cancelled'] : ['received', 'washing', 'ready', if (home) 'out', 'delivered'];
        } else if (day == 2) {
          path = r.nextBool() ? ['received', 'washing', 'ready'] : ['received', 'washing', 'ready', if (home) 'out', 'delivered'];
        } else if (day == 1) {
          path = [
            ['received', 'washing'],
            ['received', 'washing', 'ready'],
            ['received', 'washing', 'ready', if (home) 'out'],
          ][r.nextInt(3)];
        } else {
          path = k < 2 ? ['pickup'] : (k < 5 ? ['received'] : ['received', 'washing']);
        }
        var t = createdAt;
        for (var i = 0; i < path.length; i++) {
          if (i > 0) t = t.add(Duration(hours: 3 + r.nextInt(14)));
          if (t.isAfter(now)) t = now.subtract(Duration(minutes: 5 + r.nextInt(50)));
          final who = path[i] == 'washing' || path[i] == 'ready'
              ? 'demo_s3'
              : (path[i] == 'out' || (path[i] == 'delivered' && home) || path[i] == 'pickup' ? o.deliveryAgent.isEmpty ? drivers.first : o.deliveryAgent : by);
          o.history.add(StatusEvent(status: path[i], at: t, by: who));
          d.activity.add(Activity(by: who, kind: i == 0 ? 'order.new' : 'status.${path[i]}', at: t, orderId: o.id, text: o.code));
        }
        o.status = path.last;
        if (o.status == 'pickup') {
          o.pickupAgent = drivers[r.nextInt(2)];
          o.homeDelivery = true;
        }
        // payments: most pay on delivery, some advance, some udhaar
        final total = o.total;
        if (o.status != 'cancelled' && o.status != 'pickup') {
          final roll = r.nextInt(10);
          final mode = payModes[[0, 1, 1, 1, 2][r.nextInt(5)]];
          if (o.status == 'delivered') {
            if (roll < 8) {
              o.payments.add(Payment(amount: total, mode: mode, at: o.timeOf('delivered')!, by: o.homeDelivery ? o.deliveryAgent : by));
            } else if (roll == 8) {
              o.payments.add(Payment(amount: (total / 2).roundToDouble(), mode: mode, at: o.timeOf('delivered')!, by: by));
            }
          } else if (roll < 4) {
            o.payments.add(Payment(amount: (total * .5).roundToDouble(), mode: mode, at: createdAt, by: by, note: 'advance'));
          }
        }
        d.orders.add(o);
      }
    }

    // attendance today + last week
    for (var day = 6; day >= 0; day--) {
      final dt = now.subtract(Duration(days: day));
      for (final s in staff) {
        if (day == 0 && s.id == 'demo_s6') continue; // absent today
        if (r.nextInt(9) == 0 && day > 0) continue;
        final inAt = DateTime(dt.year, dt.month, dt.day, 9, r.nextInt(25));
        final outAt = day == 0 ? null : DateTime(dt.year, dt.month, dt.day, 19, r.nextInt(50));
        if (day == 0 && inAt.isAfter(now)) continue;
        d.attendance.add(Attendance(staffId: s.id, day: dayKey(dt), inAt: inAt, outAt: outAt));
      }
    }

    // expenses this month
    final exp = <List<Object>>[
      ['Detergent & chemicals', 3200], ['Electricity', 5400], ['Water', 900], ['Rent', 25000], ['Salary', 92000],
      ['Maintenance', 1800], ['Fuel & transport', 2600], ['Packaging', 1200], ['Detergent & chemicals', 2100],
      ['Fuel & transport', 1900],
    ];
    for (var i = 0; i < exp.length; i++) {
      d.expenses.add(Expense(
        id: 'demo_e$i',
        branchId: bIds[i % bIds.length],
        category: exp[i][0] as String,
        amount: (exp[i][1] as int).toDouble(),
        at: now.subtract(Duration(days: (i * 3) % 28)),
      ));
    }
    // GPS trail of the two delivery staff today (Andheri / Bandra, Mumbai)
    final starts = {'demo_s4': [19.1364, 72.8296], 'demo_s5': [19.0596, 72.8295]};
    starts.forEach((id, ll) {
      final pts = <Ping>[];
      for (var i = 0; i < 18; i++) {
        final at = now.subtract(Duration(minutes: (18 - i) * 12));
        if (at.day != now.day) continue;
        pts.add(Ping(lat: ll[0] + i * .0011 + r.nextDouble() * .0006, lng: ll[1] + (i.isEven ? 1 : -1) * r.nextDouble() * .0012 + i * .0004, at: at));
      }
      d.pings[id] = pts;
    });
    for (final o in d.orders.where((o) => o.homeDelivery && o.status == 'delivered')) {
      final ll = starts[o.deliveryAgent] ?? starts.values.first;
      o.proof = Ping(lat: ll[0] + r.nextDouble() * .02, lng: ll[1] + r.nextDouble() * .02, at: o.timeOf('delivered')!, orderId: o.id);
    }
    d.hasSample = true;
    d.changed();
  }
}
