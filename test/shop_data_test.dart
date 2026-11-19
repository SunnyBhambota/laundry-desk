import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_desk/data/cloud_sync.dart';
import 'package:laundry_desk/data/issue_models.dart';
import 'package:laundry_desk/logic/payroll.dart';
import 'package:laundry_desk/data/ops_models.dart';
import 'package:laundry_desk/data/rate_card.dart';
import 'package:laundry_desk/data/reports.dart';
import 'package:laundry_desk/data/sample_data.dart';
import 'package:laundry_desk/data/shop_data.dart';
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
    expect(d.staff.every((s) => !s.pinHash.contains('4444')), isTrue);
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
}

