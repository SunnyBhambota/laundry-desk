import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_desk/data/cloud_sync.dart';
import 'package:laundry_desk/data/ops_models.dart';
import 'package:laundry_desk/data/rate_card.dart';
import 'package:laundry_desk/data/reports.dart';
import 'package:laundry_desk/data/sample_data.dart';
import 'package:laundry_desk/data/shop_data.dart';
import 'package:laundry_desk/logic/messages.dart';
import 'package:laundry_desk/models/models.dart';
import 'package:laundry_desk/services/export_service.dart';
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
}
