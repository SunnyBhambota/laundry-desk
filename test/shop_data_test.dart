import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_desk/data/cloud_sync.dart';
import 'package:laundry_desk/data/issue_models.dart';
import 'package:laundry_desk/logic/payroll.dart';
import 'package:laundry_desk/data/ops_models.dart';
import 'package:laundry_desk/data/rate_card.dart';
import 'package:laundry_desk/data/reports.dart';
import 'package:laundry_desk/data/sample_data.dart';
import 'package:laundry_desk/data/shop_data.dart';
import 'package:laundry_desk/data/shop_v12.dart';
import 'package:laundry_desk/services/expiry_service.dart';
import 'package:laundry_desk/data/shop_v13.dart';
import 'package:laundry_desk/logic/messages.dart';
import 'package:laundry_desk/models/models.dart';
import 'package:laundry_desk/services/export_service.dart';
import 'package:laundry_desk/services/thermal_printer.dart';
import 'package:laundry_desk/widgets/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShopProfile _shop({bool gst = false}) => ShopProfile(
      shopName: 'Sparkle Laundry',
      services: const ['Wash & fold', 'Dry clean', 'Steam iron'],
      branches: '1',
      team: '1–3',
      country: 'India',
      currency: 'INR',
      gst: gst,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('money uses Indian grouping', () {
    expect(money(1240, 'INR'), '₹1,240');
    expect(money(123456, 'INR'), '₹1,23,456');
    expect(money(1234567, 'USD'), '\$1,234,567');
  });

  test('default rate card has prices for chosen services only', () {
    final r = DefaultRates.defaultRates(['Dry clean']);
    expect(r['g_shirt|Dry clean'], 80);
    expect(r.keys.every((k) => k.endsWith('|Dry clean')), isTrue);
    expect(r.containsKey('g_kg|Dry clean'), isFalse);
  });

  test('order totals: express, discount, GST, payments, tags', () {
    final o = LaundryOrder(
      id: 'o1',
      number: 7,
      customerId: 'c',
      branchId: 'b',
      lines: [
        OrderLine(garment: 'Shirt', service: 'Dry clean', qty: 3, rate: 80),
        OrderLine(garment: 'Mixed clothes', service: 'Wash & fold', qty: 2.5, rate: 80, unit: 'kg'),
      ],
      createdAt: DateTime(2026, 11, 1),
      dueAt: DateTime(2026, 11, 3),
      express: true,
      discount: 40,
      taxPct: 18,
    );
    expect(o.subtotal, 440);
    expect(o.expressCharge, 220);
    expect(o.taxable, 620);
    expect(o.total, 732); // 620 + 111.6 rounded
    expect(o.pieces, 4);
    expect(o.tags.first, 'LD-0007 · 1/4');
    o.payments.add(Payment(amount: 500, mode: 'upi', at: DateTime(2026, 11, 1)));
    expect(o.due, 232);
    final again = LaundryOrder.fromJson(o.toJson());
    expect(again.total, o.total);
    expect(again.payments.single.mode, 'upi');
  });

  test('status flow', () {
    expect(nextStatus('received', homeDelivery: false), 'washing');
    expect(nextStatus('ready', homeDelivery: false), 'delivered');
    expect(nextStatus('ready', homeDelivery: true), 'out');
    expect(nextStatus('delivered', homeDelivery: true), isNull);
  });

  test('shop data: create order, pay, deliver, report', () async {
    final d = ShopData('local_test');
    await d.initialise(_shop(gst: true));
    expect(d.shopCode.length, 6);
    expect(d.taxPct, 18);
    final c = d.addCustomer(name: 'Priya', phone: '98765 43210');
    final o = d.createOrder(
      customerId: c.id,
      branchId: d.branches.first.id,
      lines: [OrderLine(garment: 'Shirt', service: 'Dry clean', qty: 2, rate: 100)],
      by: 'owner',
      advance: 100,
    );
    expect(o.code, 'LD-0001');
    expect(o.total, 236);
    expect(d.dueOf(c.id), 136);
    d.setStatus(o, 'washing', by: 'owner');
    d.setStatus(o, 'ready', by: 'owner');
    d.addPayment(o, 136, 'cash', by: 'owner');
    d.setStatus(o, 'delivered', by: 'owner');
    expect(o.due, 0);
    expect(o.open, isFalse);
    final r = Report(orders: d.orders, expenses: d.expenses, range: DateRange.of(Period.today));
    expect(r.orderCount, 1);
    expect(r.collected, 236);
    expect(r.byMode['cash'], 236); // advance (cash) + rest (cash)
    final back = await ShopData.open('local_test');
    // saved after the debounce or on demand
    d.save(now: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final reopened = await ShopData.open('local_test');
    expect(reopened.orders.length, 1);
    expect(back.shopCode.isNotEmpty || reopened.shopCode.isNotEmpty, isTrue);
  });

  test('sample data fills every screen and clears cleanly', () async {
    final d = ShopData('local_sample');
    final shop = _shop();
    await d.initialise(shop);
    SampleData.fill(d, services: shop.services);
    expect(d.branches.length, 3);
    expect(d.staff.length, 6);
    expect(d.customers.length, greaterThan(10));
    expect(d.orders.length, greaterThan(60));
    expect(d.orders.any((o) => o.status == 'pickup'), isTrue);
    expect(d.orders.any((o) => o.status == 'ready'), isTrue);
    final stats = StaffStats.build(activity: d.activity, orders: d.orders, attendance: d.attendance, range: DateRange.of(Period.month));
    expect(stats['demo_s3']!.statusUpdates, greaterThan(0));
    final msg = Messages.bill(d.orders.first, shopName: 'Sparkle', customerName: 'Priya', currency: 'INR');
    expect(msg, contains('Total'));
    expect(d.verifyStaff('+91 98200 44444', '4444')?.id, 'demo_s4');
    expect(d.verifyStaff('9820044444', '1234'), isNull);
    expect(d.staff.every((s) => s.pinHash.length == 64 && !s.pinHash.startsWith('plain:')), isTrue); // only hashes are stored
    final pdf = await ExportService.billPdf(shop: shop, data: d, o: d.orders.first);
    expect(pdf.length, greaterThan(1000));
    final tags = await ExportService.tagsPdf(shop: shop, data: d, o: d.orders.first);
    expect(tags.length, greaterThan(1000));
    final rep = await ExportService.reportPdf(
        shop: shop, data: d, r: Report(orders: d.orders, expenses: d.expenses, range: DateRange.of(Period.month)), periodLabel: 'This month');
    expect(rep.length, greaterThan(1000));
    final csv = ExportService.ordersCsv(d, d.orders);
    expect(csv.split('\n').first, startsWith('Order,Date,Customer'));
    expect(d.lastPing('demo_s4'), isNotNull);
    d.clearSample();
    expect(d.pings, isEmpty);
    expect(d.orders, isEmpty);
    expect(d.staff, isEmpty);
    expect(d.branches.length, 1);
  });

  test('cloud json is canonical (no write loops)', () {
    expect(CloudSync.enc({'b': 1, 'a': [1.0, {'y': 2, 'x': 'z'}]}), CloudSync.enc({'a': [1, {'x': 'z', 'y': 2.0}], 'b': 1.0}));
  });

  test('complaint, wrong delivery, re-open and payroll', () async {
    final d = ShopData('local_issue');
    final shop = _shop();
    await d.initialise(shop);
    final washer = d.addStaff(name: 'Ravi', phone: '9820033333', role: Role.washer, branchId: d.branches.first.id, pin: '3333', salary: 14000);
    final agent = d.addStaff(name: 'Arjun', phone: '9820044444', role: Role.delivery, branchId: d.branches.first.id, pin: '4444', salary: 13000);
    final c = d.addCustomer(name: 'Priya', phone: '9876543210');
    final o = d.createOrder(
      customerId: c.id,
      branchId: d.branches.first.id,
      lines: [OrderLine(garment: 'Shirt', service: 'Dry clean', qty: 4, rate: 80)],
      by: 'owner',
      homeDelivery: true,
    );
    d.setStatus(o, 'washing', by: washer.id);
    d.setStatus(o, 'ready', by: washer.id);
    d.assign(o, deliveryAgent: agent.id, by: 'owner');
    d.setStatus(o, 'out', by: agent.id);
    d.addPayment(o, o.total, 'cash', by: agent.id);
    d.setStatus(o, 'delivered', by: agent.id);
    expect(d.suspects(o)[washer.id], 'washing');
    final i = d.openComplaint(o: o, pieces: [o.tags.first], reason: 'Stain left', by: 'owner', fault: [washer.id], pickupFromHome: true, agent: agent.id);
    expect(i.code, 'ISS-0001');
    expect(i.tasks.single.agent, agent.id);
    d.issueStage(i, 'washing', by: washer.id);
    d.closeIssue(i, by: 'owner');
    d.reopenIssue(i, by: 'owner', note: 'still there');
    expect(i.open, isTrue);
    expect(i.reopenCount, 1);
    final w = d.openWrongDelivery(o: o, subKind: 'missing', by: 'owner', fault: [agent.id], agent: agent.id);
    expect(w.tasks.length, 2);
    for (final tk in w.tasks) {
      d.taskDone(w, tk, by: agent.id);
    }
    d.closeIssue(w, by: 'owner');
    d.addPayout(agent.id, monthKey(DateTime.now()), 'advance', 1000);
    final ps = buildPayslip(
      s: agent,
      month: monthKey(DateTime.now()),
      orders: d.orders,
      activity: d.activity,
      attendance: d.attendance,
      issues: d.issues,
      payouts: d.payouts,
      rules: d.rules,
    );
    expect(ps.drops, 1);
    expect(ps.wrongs, 1);
    expect(ps.collected, o.total);
    // 13000 + 20 delivery + 0.5% of 320 − 50 penalty − 1000 advance
    expect(ps.net, closeTo(13000 + 20 + 1.6 - 50 - 1000, .01));
    final wp = buildPayslip(
        s: washer, month: monthKey(DateTime.now()), orders: d.orders, activity: d.activity, attendance: d.attendance, issues: d.issues, payouts: d.payouts, rules: d.rules);
    expect(wp.dry, 4);
    expect(wp.complaints, 1);
    expect(ExportService.issuesCsv(d, d.issues).split('\n').length, 3);
  });

  test('v0.3: VIP rate, edit + refund, UPI link, delete customer, ESC/POS', () async {
    final d = ShopData('local_v03');
    final shop = _shop();
    await d.initialise(shop);
    final vip = d.addCustomer(name: 'Hotel', phone: '9876500000', type: 'business');
    expect(d.rateFor('g_shirt', 'Dry clean', vip), 64); // 80 − 20%
    final o = d.createOrder(
      customerId: vip.id,
      branchId: d.branches.first.id,
      lines: [OrderLine(garment: 'Shirt', service: 'Dry clean', qty: 3, rate: 64)],
      by: 'owner',
      advance: 192,
    );
    expect(o.due, 0);
    d.editOrder(o, [OrderLine(garment: 'Shirt', service: 'Dry clean', qty: 2, rate: 64)], by: 'owner');
    expect(o.history.last.status, 'edited');
    expect(d.overpaid(o), 64);
    d.refund(o, 64, 'cash', by: 'owner');
    expect(d.overpaid(o), 0);
    expect(o.paid, 128);
    expect(d.upiLink(o, 'Shop'), isNull); // nothing due
    d.upiId = 'shop@okhdfc';
    o.lines.add(OrderLine(garment: 'Shirt', service: 'Dry clean', qty: 1, rate: 64));
    expect(d.upiLink(o, 'Sparkle Laundry'), startsWith('upi://pay?pa=shop%40okhdfc&pn=Sparkle%20Laundry&am=64.00'));
    expect(d.deleteCustomer(vip, by: 'owner'), isFalse); // 64 still due
    final p = ThermalPrinter.instance;
    final bytes = p.billBytes(shop: shop, d: d, o: o);
    expect(bytes.take(2), [0x1B, 0x40]);
    expect(bytes.length, greaterThan(200));
    expect(p.tagBytes(d: d, o: o).length, greaterThan(100));
  });

  test('v0.4: coupon, points, package, stock, location, cloud json', () async {
    final d = ShopData('local_v04');
    final shop = _shop();
    await d.initialise(shop);
    d.taxPct = 0;
    final c = d.addCustomer(name: 'Asha', phone: '9876511111');
    d.coupons.add(Coupon(id: 'cp1', code: 'FIRST50', kind: 'flat', value: 50, minOrder: 200, onlyNew: true));
    expect(d.couponDiscount('first50', c, 300), 50);
    expect(d.couponDiscount('FIRST50', c, 150), 0); // below minimum
    final o = d.createOrder(
      customerId: c.id,
      branchId: d.branches.first.id,
      lines: [OrderLine(garment: 'Shirt', service: 'Wash & iron', qty: 10, rate: 30)],
      by: 'owner',
      couponCode: 'FIRST50',
      couponAmount: 50,
    );
    expect(o.total, 250);
    expect(d.couponUses('FIRST50'), 1);
    expect(d.couponDiscount('FIRST50', c, 300), 0); // not new any more
    d.pointsPer100 = 1;
    d.setStatus(o, 'delivered', by: 'owner');
    expect(c.points, 2);
    c.points = 60;
    d.minRedeem = 50;
    d.pointValue = 1;
    expect(d.pointsMoney(c), 60);
    final plan = PackagePlan(id: 'pk1', name: 'Family 30 kg', service: 'Wash & fold', unit: 'kg', credits: 30, price: 1200);
    final sold = d.sellPackage(c, plan, by: 'owner', branchId: d.branches.first.id);
    expect(sold.due, 0);
    final pk = c.activePackage('Wash & fold', 'kg');
    expect(pk, isNotNull);
    final o2 = d.createOrder(
      customerId: c.id,
      branchId: d.branches.first.id,
      lines: [OrderLine(garment: 'Mixed', service: 'Wash & fold', qty: 5, rate: 40, unit: 'kg')],
      by: 'owner',
      package: pk,
      packageQty: 5,
      packageValue: 200,
      pointsUsed: 20,
    );
    expect(o2.offers, 220);
    expect(pk!.remaining, 25);
    expect(c.points, 40);
    final it = d.addStockItem('Detergent', 'kg', qty: 10, minQty: 5);
    final before = d.expenses.length;
    d.moveStock(it, -6, by: 'owner');
    expect(d.lowStock.map((s) => s.name), ['Detergent']);
    d.moveStock(it, 20, by: 'owner', cost: 1500);
    expect(it.qty, 24);
    expect(d.expenses.length, before + 1);
    expect(d.lowStock, isEmpty);
    d.setCustomerLocation(c.id, 19.1, 72.9);
    d.setCustomerLocation(c.id, 1, 1, onlyIfMissing: true);
    expect(c.lat, 19.1);
    final back = Customer.fromJson(c.toJson());
    expect(back.points, 40);
    expect(back.packages.single.remaining, 25);
    expect(LaundryOrder.fromJson(o.toJson()).couponCode, 'FIRST50');
    final sample = ShopData('local_v04s');
    await sample.initialise(shop);
    SampleData.fill(sample, services: shop.services);
    expect(sample.coupons, isNotEmpty);
    expect(sample.stock, isNotEmpty);
    sample.clearSample();
    expect(sample.coupons.where((x) => x.id.startsWith('demo_')), isEmpty);
  });

  test('multi-branch: totals add up, CSV, agents, booking link', () async {
    final d = ShopData('local_mb');
    final shop = _shop();
    await d.initialise(shop);
    SampleData.fill(d, services: shop.services);
    expect(d.branches.length, 3);
    for (final range in [DateRange.of(Period.today), DateRange.of(Period.month), DateRange.of(Period.all)]) {
      final all = Report(orders: d.orders, expenses: d.expenses, range: range);
      var sales = 0.0, coll = 0.0, exp = 0.0, n = 0;
      for (final b in d.branches) {
        final r = Report(orders: d.orders, expenses: d.expenses, range: range, branchId: b.id);
        sales += r.sales;
        coll += r.collected;
        exp += r.expense;
        n += r.orderCount;
      }
      expect(sales, closeTo(all.sales, .5));
      expect(coll, closeTo(all.collected, .5));
      expect(exp, closeTo(all.expense, .5));
      expect(n, all.orderCount);
    }
    final csv = ExportService.branchCsv(d, DateRange.of(Period.month)).split('\n');
    expect(csv.length, d.branches.length + 1);
    final b2 = d.branches[1];
    final agents = d.agentsFor(b2.id);
    expect(agents, isNotEmpty);
    expect(agents.every((s) => s.role == Role.delivery), isTrue);
    expect(ExportService.bookingLink('Sparkle', '98200 11111'), startsWith('https://wa.me/919820011111?text='));
    final pdf = await ExportService.reportPdf(shop: shop, data: d, r: Report(orders: d.orders, expenses: d.expenses, range: DateRange.of(Period.month)), periodLabel: 'month');
    expect(pdf.length, greaterThan(1000));
    final poster = await ExportService.bookingPosterPdf(shop: shop, link: 'https://wa.me/919820011111');
    expect(poster.length, greaterThan(1000));
  });

  test('staff requests + stock used booked once', () async {
    final d = ShopData('local_rq');
    final shop = _shop();
    await d.initialise(shop);
    SampleData.fill(d, services: shop.services);
    final it = d.stock.firstWhere((x) => x.id == 'demo_st3');
    final start = it.qty;
    final r = d.addRequest(by: 'demo_s3', branchId: d.branches.first.id, item: it.name, itemId: it.id, qty: 5, unit: 'L', urgent: true);
    expect(d.pendingRequests.takeWhile((x) => x.urgent).map((x) => x.id), contains(r.id)); // urgent first
    d.decideRequest(r, 'given', by: 'owner', fromStock: true);
    expect(it.qty, start - 5);
    expect(r.open, isFalse);
    d.addStockUse(it, 2, by: 'demo_s3');
    expect(d.pendingUse(it.id), 2);
    expect(d.applyStockUses(), isTrue);
    expect(d.applyStockUses(), isFalse); // only once
    expect(it.qty, start - 7);
    expect(d.pendingUse(it.id), 0);
    final n = DateTime.now();
    expect(d.usedIn(it.id, n.subtract(const Duration(days: 1)), n.add(const Duration(days: 1))), 7);
    final buy = d.addRequest(by: 'demo_s3', branchId: d.branches.first.id, item: 'Iron / istri', qty: 1, unit: 'pc');
    final exp = d.expenses.length;
    d.decideRequest(buy, 'given', by: 'owner', cost: 1200);
    expect(d.expenses.length, exp + 1);
    final back = StaffRequest.fromJson(r.toJson());
    expect(back.status, 'given');
    expect(d.unitCost('demo_st1'), closeTo(160, .01));
    d.clearSample();
    expect(d.requests.where((x) => x.by.startsWith('demo_')), isEmpty);
  });

  test('v0.8: work assign, notices, leave, cash drawer, piece count, repeat copy', () async {
    final d = ShopData('local_v08');
    final shop = _shop();
    await d.initialise(shop);
    SampleData.fill(d, services: shop.services);
    final main = d.branches.first.id;
    final ravi = d.staff.firstWhere((x) => x.id == 'demo_s3');
    expect(d.openWork(ravi.id), isNotEmpty);
    // new order, auto assign by skills
    d.autoAssign = true;
    final c = d.customers.first;
    final o = d.createOrder(customerId: c.id, branchId: main, lines: [
      OrderLine(garment: 'Shirt', service: 'Dry clean', qty: 2, rate: 80),
      OrderLine(garment: 'Saree', service: 'Dry clean', qty: 1, rate: 200),
    ], by: 'owner');
    expect(o.lines.every((l) => l.worker == ravi.id), isTrue);
    d.lineWork(o, 0, 'doing', by: ravi.id);
    expect(o.status, 'washing');
    d.lineWork(o, 0, 'done', by: ravi.id);
    expect(o.status, 'washing');
    d.lineWork(o, 1, 'done', by: ravi.id);
    expect(o.status, 'ready');
    final n = DateTime.now();
    expect(d.workDone(ravi.id, DateTime(n.year, n.month, n.day), n.add(const Duration(days: 1))).$1, greaterThanOrEqualTo(3));
    // payslip counts finished lines once
    final ps = buildPayslip(s: ravi, month: monthKey(n), orders: d.orders, activity: d.activity, attendance: d.attendance, issues: d.issues, payouts: d.payouts, rules: d.rules);
    expect(ps.dry, greaterThanOrEqualTo(3));
    // piece count
    d.countOut(o, 2, by: 'owner');
    expect(d.activity.any((a) => a.kind == 'count.mismatch' && a.orderId == o.id), isTrue);
    // notices
    final nt = d.addNotice('Hello team', by: 'owner');
    expect(d.noticesFor(ravi.id, main).first.id, nt.id);
    d.readNotice(nt, ravi.id);
    d.readNotice(nt, ravi.id);
    expect(nt.readBy, [ravi.id]);
    // leave
    final lv = d.addLeave(by: ravi.id, branchId: main, from: DateTime(n.year, n.month, 1), to: DateTime(n.year, n.month, 2));
    expect(lv.leaveDays, 2);
    d.decideRequest(lv, 'approved', by: 'owner');
    expect(lv.open, isFalse);
    expect(d.leaveDaysIn(ravi.id, monthKey(n)), 2);
    // cash drawer
    d.openDrawer(main, 1000, by: 'owner');
    final before = d.expectedCash(main, n);
    d.addPayment(o, 100, 'cash', by: 'owner');
    expect(d.expectedCash(main, n), before + 100);
    d.closeDrawer(main, before + 90, by: 'owner');
    expect(d.cashDay(main, n).closing, before + 90);
    // json round trips
    expect(OrderLine.fromJson(o.lines.first.toJson()).worker, ravi.id);
    expect(Notice.fromJson(nt.toJson()).readBy, [ravi.id]);
    expect(CashDay.fromJson(d.cashDay(main, n).toJson()).opening, 1000);
    expect(StaffRequest.fromJson(lv.toJson()).kind, 'leave');
    expect(Staff.fromJson(ravi.toJson()).skills, ravi.skills);
    final copy = o.lines.first.copy();
    expect(copy.worker, isEmpty);
    d.clearSample();
    expect(d.notices.where((x) => x.id.startsWith('demo_')), isEmpty);
  });

  test('v0.9: referral, groups, rating, permissions, statement', () async {
    final d = ShopData('local_v09');
    final shop = _shop();
    await d.initialise(shop);
    SampleData.fill(d, services: shop.services);
    final a = d.customers.first;
    final b = d.addCustomer(name: 'New Friend', phone: '9000000001');
    b.referredBy = a.id;
    final pa = a.points;
    d.referralPoints = 50;
    final o = d.createOrder(customerId: b.id, branchId: d.branches.first.id, lines: [OrderLine(garment: 'Shirt', service: 'Wash & iron', qty: 2, rate: 30)], by: 'owner');
    d.setStatus(o, 'delivered', by: 'owner');
    expect(a.points, pa + 50);
    expect(b.referralPaid, isTrue);
    final pb = b.points;
    final o2 = d.createOrder(customerId: b.id, branchId: d.branches.first.id, lines: [OrderLine(garment: 'Shirt', service: 'Wash & iron', qty: 1, rate: 30)], by: 'owner');
    d.setStatus(o2, 'delivered', by: 'owner');
    expect(b.points, lessThan(pb + 50)); // only once
    d.rateOrder(o, 2, by: 'owner', note: 'late');
    expect(d.customerGroup('low_rating').map((c) => c.id), contains(b.id));
    expect(d.customerGroup('new').map((c) => c.id), contains(b.id));
    expect(d.customerGroup('top').length, lessThanOrEqualTo(20));
    expect(d.clothesHistory(b.id).length, 2);
    final counter = d.staff.firstWhere((s) => s.role == Role.counter);
    expect(d.can(counter, 'refund'), isFalse);
    expect(d.can(counter, 'discount'), isTrue);
    counter.perms['refund'] = true;
    expect(d.can(counter, 'refund'), isTrue);
    expect(d.can(null, 'refund'), isTrue);
    expect(Staff.fromJson(counter.toJson()).perms['refund'], isTrue);
    expect(LaundryOrder.fromJson(o.toJson()).rating, 2);
    final back = Customer.fromJson(b.toJson());
    expect(back.referredBy, a.id);
    final n = DateTime.now();
    final pdf = await ExportService.statementPdf(shop: shop, data: d, c: a, from: DateTime(n.year, n.month, 1), to: DateTime(n.year, n.month + 1, 1));
    expect(pdf.length, greaterThan(1000));
  });

  test('v0.10: loans, shifts, meters, machines, insights, GST', () async {
    final d = ShopData('local_v10');
    final shop = _shop();
    await d.initialise(shop);
    SampleData.fill(d, services: shop.services);
    final l = Loan(id: 'x', staffId: 's', amount: 2500, monthly: 1000, start: '2026-01', at: DateTime(2026));
    expect(l.cutIn('2025-12'), 0);
    expect(l.cutIn('2026-01'), 1000);
    expect(l.cutIn('2026-03'), 500);
    expect(l.cutIn('2026-04'), 0);
    expect(l.leftAfter('2026-02'), 500);
    expect(l.leftAfter('2027-01'), 0);
    final ravi = d.staff.firstWhere((x) => x.id == 'demo_s3');
    final n = DateTime.now();
    final r = d.shiftReport(ravi, monthKey(n));
    expect(r.days, greaterThanOrEqualTo(0));
    final ps = buildPayslip(s: ravi, month: monthKey(n), orders: d.orders, activity: d.activity, attendance: d.attendance, issues: d.issues, payouts: d.payouts, rules: d.rules, loans: d.loans, notes: d.staffNotes);
    expect(ps.lines.any((x) => x.label == 'Loan installment' && x.amount == -1000), isTrue);
    final arjun = d.staff.firstWhere((x) => x.id == 'demo_s4');
    final pa = buildPayslip(s: arjun, month: monthKey(d.staffNotes.firstWhere((x) => x.id == 'demo_sn1').at), orders: d.orders, activity: d.activity, attendance: d.attendance, issues: d.issues, payouts: d.payouts, rules: d.rules, notes: d.staffNotes);
    expect(pa.lines.any((x) => x.label.startsWith('Fine') && x.amount == -100), isTrue);
    final main = d.branches.first.id;
    expect(d.meterUsed('electricity', main, n.subtract(const Duration(days: 30)), n.add(const Duration(days: 1))), closeTo(385, .01));
    expect(d.machinesDue.map((m) => m.id), contains('demo_mc1'));
    d.reportFault(d.machines[1], by: 'demo_s3', branchId: main, note: 'noise');
    expect(d.machinesDue.map((m) => m.id), contains('demo_mc2'));
    d.serviceMachine(d.machines.first, by: 'owner', cost: 800);
    expect(d.machines.first.serviceDue, isFalse);
    final from = DateTime(2000), to = n.add(const Duration(days: 1));
    final sv = d.serviceRevenue(from, to);
    final total = sv.values.fold<double>(0, (s, v) => s + v.$1);
    final taxable = d.orders.where((o) => o.status != 'cancelled').fold<double>(0, (s, o) => s + o.taxable);
    expect(total, closeTo(taxable, 1));
    expect(d.monthlySales(6).length, 6);
    final busy = d.busyTimes(from, to);
    expect(busy.$1.fold<int>(0, (a, b) => a + b), d.orders.length);
    final ds = d.deliveryStats('demo_s4', from, to);
    expect(ds.drops, greaterThanOrEqualTo(0));
    d.taxPct = 18;
    final csv = ExportService.gstCsv(d, from, to).split('\n');
    expect(csv.first, startsWith('Date'));
    expect(Machine.fromJson(d.machines.first.toJson()).name, d.machines.first.name);
    expect(Loan.fromJson(d.loans.first.toJson()).monthly, 1000);
    d.clearSample();
    expect(d.machines, isEmpty);
    expect(d.loans, isEmpty);
  });

  test('v0.12: outside, QC, wallet, claim, party, alteration', () async {
    final shop = ShopProfile(shopName: 'T', services: const ['Wash & fold', 'Alteration'], branches: '1', team: '1', country: 'India', currency: 'INR', gst: false);
    final d = await ShopData.open('t12');
    await d.initialise(shop);
    expect(d.hasAlteration, isTrue);
    expect(d.rates.containsKey('g_alt_hem|Alteration'), isTrue);
    final c = d.addCustomer(name: 'Hotel Sun', phone: '9876543210');
    c.type = 'business';
    expect(d.partyCustomers.length, 1);
    final g = d.garments.firstWhere((x) => x.id == 'g_alt_hem');
    final o = d.createOrder(
      customerId: c.id,
      branchId: d.branches.first.id,
      lines: [OrderLine(garment: g.name, service: 'Alteration', qty: 2, rate: 80)],
      by: 'owner',
    );
    expect(o.total, 160);
    d.sendOutside(o, 'Tailor Raju', 50, by: 'owner');
    expect(d.outsideOrders.length, 1);
    d.receiveOutside(o, by: 'owner');
    expect(d.outsideOrders, isEmpty);
    expect(d.outsideCostIn(DateTime(2000), DateTime(2100)), 50);
    d.doQc(o, by: 'owner', note: 'ok');
    expect(o.qcDone, isTrue);
    d.walletTopUp(c, 100, by: 'owner');
    expect(d.payFromWallet(o, by: 'owner'), 100);
    expect(c.wallet, 0);
    expect(o.due, 60);
    d.addClaim(o, kind: 'lost', piece: 'shirt', amount: 40, by: 'owner');
    expect(o.due, 20);
    final back = LaundryOrder.fromJson(o.toJson());
    expect(back.claims.length, 1);
    expect(back.outTo, 'Tailor Raju');
    expect(Customer.fromJson(c.toJson()).walletLog.length, 2);
    expect(d.estimateText(shopName: 'T', currency: 'INR', lines: o.lines, subtotal: 160, express: 0, tax: 0, total: 160, due: DateTime.now()), contains('Total'));
  });

  test('v0.13: membership, repeat, slot, rack, chat', () async {
    final shop = ShopProfile(shopName: 'T', services: const ['Wash & fold'], branches: '1', team: '1', country: 'India', currency: 'INR', gst: false);
    final d = await ShopData.open('t13');
    await d.initialise(shop);
    final c = d.addCustomer(name: 'Asha', phone: '9876500000');
    final plan = PackagePlan(id: 'pp1', name: 'Family 30 kg', service: 'Wash & fold', unit: 'kg', credits: 30, price: 1999);
    d.packagePlans.add(plan);
    d.sellPackage(c, plan, by: 'owner', branchId: d.branches.first.id);
    expect(d.activeMemberships.length, 1);
    expect(d.membershipsToRenew, isEmpty);
    c.packages.first.remaining = 3;
    expect(d.membershipsToRenew.length, 1);
    expect(d.planOf(c.packages.first), isNotNull);
    d.setRepeat(c, every: 7, slot: '12–3');
    expect(d.repeatsDue, isEmpty);
    c.repeat = {...c.repeat!, 'next': DateTime.now().toIso8601String()};
    expect(d.repeatsDue.length, 1);
    d.repeatDone(c);
    expect(d.repeatsDue, isEmpty);
    expect(Customer.fromJson(c.toJson()).repeat?['every'], 7);
    d.slotLimit = 1;
    expect(d.slotFull('12–3'), isFalse);
    final o = d.createOrder(customerId: c.id, branchId: d.branches.first.id, lines: [OrderLine(garment: 'Shirt', service: 'Wash & fold', qty: 2, rate: 20)], by: 'owner', slot: '12–3');
    o.status = 'pickup';
    expect(d.slotFull('12–3'), isTrue);
    o.rack = 'A-4';
    expect(d.rackMap.containsKey(4), isTrue);
    expect(d.freeRacks.contains(4), isFalse);
    d.addChat(o, from: 'customer', text: 'Please starch collars', by: 'owner');
    expect(LaundryOrder.fromJson(o.toJson()).chat.length, 1);
  });

  test('test build never expires without a build time', () {
    // local runs have BUILD_EPOCH = 0: no expiry
    ExpiryService.instance.check();
    expect(ExpiryService.instance.expired, isFalse);
    expect(ExpiryService.instance.daysLeft, isNull);
  });
}
