import 'dart:math';

import 'issue_models.dart';
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
      Staff(id: 'demo_s1', name: 'Sunita Kale', phone: '9820011111', role: Role.manager, branchId: main, pinHash: ShopData.staffKey(d.shopCode, '9820011111', '1111'), salary: 22000),
      Staff(id: 'demo_s2', name: 'Imran Shaikh', phone: '9820022222', role: Role.counter, branchId: b2.id, pinHash: ShopData.staffKey(d.shopCode, '9820022222', '2222'), salary: 15000),
      Staff(id: 'demo_s3', name: 'Ravi Pawar', phone: '9820033333', role: Role.washer, branchId: main, pinHash: ShopData.staffKey(d.shopCode, '9820033333', '3333'), salary: 14000),
      Staff(id: 'demo_s4', name: 'Arjun More', phone: '9820044444', role: Role.delivery, branchId: main, pinHash: ShopData.staffKey(d.shopCode, '9820044444', '4444'), salary: 13000),
      Staff(id: 'demo_s5', name: 'Deepak Yadav', phone: '9820055555', role: Role.delivery, branchId: b2.id, pinHash: ShopData.staffKey(d.shopCode, '9820055555', '5555'), salary: 13000),
      Staff(id: 'demo_s6', name: 'Neha Salvi', phone: '9820066666', role: Role.counter, branchId: b3.id, pinHash: ShopData.staffKey(d.shopCode, '9820066666', '6666'), salary: 15000),
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
    // issues: complaints and wrong deliveries on delivered orders
    final delivered = d.orders.where((o) => o.status == 'delivered').toList();
    const reasons = complaintReasons;
    for (var k = 0; k < 9 && k < delivered.length; k++) {
      final o = delivered[(k * 7) % delivered.length];
      final at = o.timeOf('delivered')!.add(Duration(hours: 3 + k));
      if (at.isAfter(now)) continue;
      final wrong = k % 3 == 2;
      final washer = 'demo_s3';
      final agent = o.deliveryAgent.isEmpty ? 'demo_s4' : o.deliveryAgent;
      final closed = k < 6;
      final i = Issue(
        id: 'demo_i$k',
        number: k + 1,
        kind: wrong ? 'wrong' : 'complaint',
        subKind: wrong ? 'swap' : '',
        orderId: o.id,
        otherOrderId: wrong ? delivered[(k * 7 + 1) % delivered.length].id : '',
        customerId: o.customerId,
        branchId: o.branchId,
        openedAt: at,
        openedBy: 'demo_s1',
        dueAt: at.add(const Duration(days: 1)),
        pieces: [o.tags.first],
        reason: wrong ? 'Wrong delivery' : reasons[k % 5],
        fault: [wrong ? agent : washer],
        compensation: k == 4 ? 100 : 0,
        stage: closed ? 'returned' : (wrong ? 'open' : 'washing'),
        closed: closed,
        closedAt: closed ? at.add(Duration(hours: 5 + k)) : null,
        reopenCount: k == 7 ? 1 : 0,
        history: [
          StatusEvent(status: 'open', at: at, by: 'demo_s1'),
          if (!wrong) StatusEvent(status: 'received', at: at.add(const Duration(hours: 1)), by: agent),
          if (!wrong) StatusEvent(status: 'washing', at: at.add(const Duration(hours: 2)), by: washer),
          if (closed && !wrong) StatusEvent(status: 'ready', at: at.add(const Duration(hours: 4)), by: washer),
          if (closed) StatusEvent(status: 'closed', at: at.add(Duration(hours: 5 + k)), by: 'demo_s1'),
          if (k == 7) StatusEvent(status: 'reopened', at: at.add(const Duration(hours: 9)), by: 'owner', note: 'Stain still there'),
        ],
        tasks: wrong
            ? [
                IssueTask(text: 'Take back clothes from the wrong customer', agent: agent, done: closed, doneAt: closed ? at.add(const Duration(hours: 2)) : null, doneBy: agent),
                IssueTask(text: 'Give the right clothes', agent: agent, done: closed, doneAt: closed ? at.add(const Duration(hours: 3)) : null, doneBy: agent),
              ]
            : [],
      );
      d.issues.add(i);
    }
    // staff advances this month
    d.payouts.addAll([
      Payout(id: 'demo_p1', staffId: 'demo_s4', month: monthKey(now), kind: 'advance', amount: 2000, at: now.subtract(const Duration(days: 10))),
      Payout(id: 'demo_p2', staffId: 'demo_s3', month: monthKey(now), kind: 'advance', amount: 1500, at: now.subtract(const Duration(days: 6))),
    ]);
    // offers, packages, stock (v0.4)
    d.coupons.addAll([
      Coupon(id: 'demo_cp1', code: 'DIWALI10', kind: 'pct', value: 10, minOrder: 300, validTill: now.add(const Duration(days: 20))),
      Coupon(id: 'demo_cp2', code: 'FIRST50', kind: 'flat', value: 50, onlyNew: true),
    ]);
    d.packagePlans.addAll([
      PackagePlan(id: 'demo_pk1', name: 'Family 30 kg', service: 'Wash & fold', unit: 'kg', credits: 30, price: 1999),
      PackagePlan(id: 'demo_pk2', name: 'Office shirts 40', service: 'Wash & iron', unit: 'pc', credits: 40, price: 1499),
    ]);
    for (var i = 0; i < d.customers.length; i++) {
      d.customers[i].points = (i * 37 % 140).toDouble();
      if (i < 9) {
        d.customers[i].lat = 19.13 + (i * 0.007) % 0.05;
        d.customers[i].lng = 72.82 + (i * 0.011) % 0.06;
      }
    }
    d.customers[0].packages.add(CustPackage(
        id: 'demo_cpk1', name: 'Family 30 kg', service: 'Wash & fold', unit: 'kg', credits: 30, remaining: 22, price: 1999,
        start: now.subtract(const Duration(days: 8)), end: now.add(const Duration(days: 22))));
    d.suppliers.addAll([
      Supplier(id: 'demo_su1', name: 'Shree Chemicals', phone: '9820099001', items: 'Detergent, solvent, stain remover'),
      Supplier(id: 'demo_su2', name: 'Mumbai Packaging', phone: '9820099002', items: 'Hangers, poly covers, tag rolls'),
    ]);
    d.stock.addAll([
      StockItem(id: 'demo_st1', name: 'Liquid detergent', unit: 'L', qty: 6, minQty: 10, branchId: main),
      StockItem(id: 'demo_st2', name: 'Hangers', unit: 'pc', qty: 40, minQty: 100, branchId: main),
      StockItem(id: 'demo_st3', name: 'Dry clean solvent', unit: 'L', qty: 45, minQty: 20, branchId: main),
      StockItem(id: 'demo_st4', name: 'Poly covers', unit: 'pc', qty: 800, minQty: 200, branchId: main),
      StockItem(id: 'demo_st5', name: 'Tag rolls (printer)', unit: 'roll', qty: 12, minQty: 4, branchId: main),
    ]);
    d.stockMoves.add(StockMove(id: 'demo_sm1', itemId: 'demo_st1', qty: 20, at: now.subtract(const Duration(days: 9)), by: 'owner', supplierId: 'demo_su1', cost: 3200));
    // daily use of detergent / hangers by the washer
    for (var i = 1; i <= 8; i++) {
      d.stockMoves.add(StockMove(id: 'demo_smu$i', itemId: 'demo_st1', qty: -1.75, at: now.subtract(Duration(days: i)), by: 'demo_s3'));
      d.stockMoves.add(StockMove(id: 'demo_smh$i', itemId: 'demo_st2', qty: -12, at: now.subtract(Duration(days: i)), by: i.isEven ? 'demo_s3' : 'demo_s1'));
    }
    // v0.8: who does what, notices, cash drawer, target
    d.staff.firstWhere((x) => x.id == 'demo_s3').skills = ['Wash & fold', 'Wash & iron', 'Dry clean'];
    var given = 0;
    for (final o in d.orders.where((o) => o.status == 'received' || o.status == 'washing')) {
      for (final l in o.lines) {
        if (o.branchId != main || given > 6) continue;
        l.worker = 'demo_s3';
        if (o.status == 'washing') {
          l.work = 'doing';
          l.workAt = now.subtract(const Duration(minutes: 40));
        }
        given++;
      }
    }
    for (final o in d.orders.where((o) => (o.status == 'ready' || o.status == 'delivered') && o.branchId == main).take(12)) {
      for (final l in o.lines) {
        l
          ..worker = 'demo_s3'
          ..work = 'done'
          ..workAt = o.timeOf('ready') ?? o.createdAt.add(const Duration(hours: 20));
      }
      if (o.status == 'ready' && o.rack.isEmpty) o.rack = 'R${(o.number % 6) + 1}';
    }
    d.notices.addAll([
      Notice(id: 'demo_nt1', text: 'Sunday shop opens at 10 AM. Please keep all ready orders in racks by 9:30.', by: 'owner', at: now.subtract(const Duration(hours: 5)), readBy: ['demo_s1']),
      Notice(id: 'demo_nt2', text: 'New rate for curtains from 1st. Check the rate card.', by: 'owner', at: now.subtract(const Duration(days: 2)), readBy: ['demo_s1', 'demo_s2', 'demo_s3']),
    ]);
    d.cashDays.add(CashDay(id: '${main}_${dayKey(now)}', branchId: main, day: dayKey(now), opening: 2000, openedBy: 'demo_s1', openedAt: DateTime(now.year, now.month, now.day, 9, 15)));
    // v0.10: machines, meters, shifts, notes, loan, training
    d.machines.addAll([
      Machine(id: 'demo_mc1', name: 'LG 10 kg front load', branchId: main, kind: 'Washer', everyDays: 90, lastService: now.subtract(const Duration(days: 88))),
      Machine(id: 'demo_mc2', name: 'IFB dryer', branchId: main, kind: 'Dryer', everyDays: 120, lastService: now.subtract(const Duration(days: 30))),
      Machine(id: 'demo_mc3', name: 'Steam press 1', branchId: main, kind: 'Steam press', everyDays: 60, lastService: now.subtract(const Duration(days: 20))),
    ]);
    for (var i = 10; i >= 0; i--) {
      d.readings.add(MeterReading(id: 'demo_mr$i', kind: 'electricity', branchId: main, value: 12000 + (10 - i) * 38.5, at: DateTime(now.year, now.month, now.day, 9).subtract(Duration(days: i)), by: 'demo_s1'));
    }
    for (final st in d.staff.where((x) => x.id.startsWith('demo_'))) {
      st
        ..shiftStart = '09:30'
        ..shiftEnd = '19:00';
      st.training[d.trainingItems.first] = true;
    }
    d.staffNotes.addAll([
      StaffNote(id: 'demo_sn1', staffId: 'demo_s4', kind: 'mistake', text: 'Gave order to wrong flat', at: now.subtract(const Duration(days: 3)), by: 'owner', fine: 100),
      StaffNote(id: 'demo_sn2', staffId: 'demo_s3', kind: 'praise', text: 'Removed a tough wine stain', at: now.subtract(const Duration(days: 1)), by: 'owner'),
    ]);
    d.loans.add(Loan(id: 'demo_ln1', staffId: 'demo_s3', amount: 6000, monthly: 1000, start: monthKey(now), at: now.subtract(const Duration(days: 4)), note: 'Phone'));
    d.dailyTarget = 6000;
    d.dailyOrderTarget = 15;
    d.requests.addAll([
      StaffRequest(id: 'demo_rq1', by: 'demo_s3', branchId: main, item: 'Hangers', itemId: 'demo_st2', qty: 100, unit: 'pc', note: 'Ready rack is full', urgent: true, at: now.subtract(const Duration(hours: 3))),
      StaffRequest(id: 'demo_rq2', by: 'demo_s3', branchId: main, item: 'Iron / istri', qty: 1, unit: 'pc', note: 'Steam iron 2 not heating', at: now.subtract(const Duration(hours: 20))),
      StaffRequest(id: 'demo_rq3', by: 'demo_s5', branchId: b2.id, item: 'Rain cover for bike bag', qty: 1, unit: 'pc', at: now.subtract(const Duration(days: 2)), status: 'approved', doneBy: 'owner', doneAt: now.subtract(const Duration(days: 1))),
      StaffRequest(id: 'demo_lv1', kind: 'leave', by: 'demo_s4', branchId: main, item: 'Leave', qty: 2, unit: 'days', note: 'Sister\'s wedding', at: now.subtract(const Duration(hours: 6)),
          from: DateTime(now.year, now.month, now.day).add(const Duration(days: 5)), to: DateTime(now.year, now.month, now.day).add(const Duration(days: 6))),
      StaffRequest(id: 'demo_rq4', by: 'demo_s2', branchId: b2.id, item: 'Bill roll', qty: 5, unit: 'roll', at: now.subtract(const Duration(days: 4)), status: 'given', doneBy: 'owner', doneAt: now.subtract(const Duration(days: 3)), reply: 'Kept in drawer'),
    ]);
    d.hasSample = true;
    d.changed();
  }
}
