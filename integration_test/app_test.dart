// End-to-end check on a real Android emulator with the real Firebase project.
// Runs in GitHub Actions before every release:
//   sign up → business setup with sample data → cloud copy matches →
//   log out → "new phone" (local data wiped) → log in with mobile (+91 typed) →
//   log out → log in with email → staff login with shop code → staff adds an order →
//   owner sees it → branch-wise numbers add up → test account removed.
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:laundry_desk/data/ops_models.dart';
import 'package:laundry_desk/data/reports.dart';
import 'package:laundry_desk/main.dart' as app;
import 'package:laundry_desk/data/issue_models.dart';
import 'package:laundry_desk/screens/admin_screens.dart';
import 'package:laundry_desk/screens/customers_screen.dart';
import 'package:laundry_desk/screens/dashboard_screen.dart';
import 'package:laundry_desk/screens/delivery_screen.dart';
import 'package:laundry_desk/screens/issue_screens.dart';
import 'package:laundry_desk/screens/live_map_screen.dart';
import 'package:laundry_desk/screens/lock_screen.dart';
import 'package:laundry_desk/screens/more_screen.dart';
import 'package:laundry_desk/screens/new_order_screen.dart';
import 'package:laundry_desk/screens/order_detail_screen.dart';
import 'package:laundry_desk/screens/orders_screen.dart';
import 'package:laundry_desk/screens/payroll_screens.dart';
import 'package:laundry_desk/screens/reports_screen.dart';
import 'package:laundry_desk/screens/shell.dart';
import 'package:laundry_desk/screens/staff_screen.dart';
import 'package:laundry_desk/screens/v03_screens.dart';
import 'package:laundry_desk/screens/v04_screens.dart';
import 'package:laundry_desk/screens/v06_screens.dart';
import 'package:laundry_desk/screens/v08_screens.dart';
import 'package:laundry_desk/screens/v09_screens.dart';
import 'package:laundry_desk/screens/v10_screens.dart';
import 'package:laundry_desk/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> wait(WidgetTester t, bool Function() ok, String what, {int secs = 90}) async {
    final end = DateTime.now().add(Duration(seconds: secs));
    while (DateTime.now().isBefore(end)) {
      await t.pump();
      if (ok()) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // ignore: avoid_print
    print('E2E TIMEOUT: $what');
    throw TestFailure('Timed out waiting for: $what');
  }

  Future<void> pause(WidgetTester t, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await t.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> reveal(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    }
    await t.ensureVisible(f);
    await t.pump();
  }

  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

  Future<void> type(WidgetTester t, String key, String text) async {
    await reveal(t, key);
    await t.enterText(field(key), text);
    await t.pump();
  }

  Future<void> tap(WidgetTester t, String key) async {
    await reveal(t, key);
    await t.tap(find.byKey(ValueKey(key)), warnIfMissed: false);
    await t.pump();
  }

  void log(String s) {
    // ignore: avoid_print
    print('E2E: $s');
  }

  testWidgets('owner + staff full flow on the real cloud', (t) async {
    final rnd = Random();
    final mobile = '9${List.generate(9, (_) => rnd.nextInt(10)).join()}';
    final email = 'e2e.$mobile@example.com';
    const pw = 'Test@12345';

    // Layout warnings (overflow etc.) are logged, not fatal, so the whole flow runs.
    final orig = FlutterError.onError;
    final uiWarnings = <String>{};
    FlutterError.onError = (details) {
      final m = details.exceptionAsString();
      if (m.contains('overflowed') || m.contains('ListTile background')) {
        final where = details.toString().split('\n').firstWhere((l) => l.contains('file:///'), orElse: () => '');
        if (uiWarnings.add('$m $where')) log('UI-WARN: $m $where');
        return;
      }
      orig?.call(details);
    };
    addTearDown(() => FlutterError.onError = orig);

    app.main();
    await wait(t, () => find.byKey(const ValueKey('f.loginId')).evaluate().isNotEmpty, 'login screen');
    final s = t.element(find.byKey(const ValueKey('f.loginId'))).read<AppState>();

    // ---- sign up ----
    await tap(t, 'b.switch');
    await pause(t, 600);
    await type(t, 'f.name', 'E2E Owner');
    await type(t, 'f.mobile', mobile);
    await type(t, 'f.email', email);
    await type(t, 'f.newPw', pw);
    await tap(t, 'b.agree');
    await tap(t, 'b.submit');
    await wait(t, () => s.owner != null, 'sign up');
    log('signed up ${s.owner!.uid}');
    final uid = s.owner!.uid;

    // ---- business setup with sample data ----
    await wait(t, () => find.byKey(const ValueKey('f.shop')).evaluate().isNotEmpty, 'setup screen');
    await type(t, 'f.shop', 'E2E Laundry');
    await tap(t, 'b.finish');
    await wait(t, () => s.setupDone && find.byType(Shell).evaluate().isNotEmpty, 'dashboard after setup');
    final d0 = s.data!;
    expect(d0.branches.length, 3);
    expect(d0.orders.length, greaterThan(50));
    final orders = d0.orders.length;
    final customers = d0.customers.length;
    final code = d0.shopCode;
    log('setup ok: $orders orders, code $code');

    // cloud copy must match what the phone has (every collection)
    final shopRef = FirebaseFirestore.instance.collection('shops').doc(uid);
    await wait(t, () => d0.sync != null && !d0.sync!.busy, 'first upload finished', secs: 180);
    await pause(t, 3000);
    await wait(t, () => !d0.sync!.busy, 'upload idle', secs: 180);
    log('sync error: "${d0.sync?.lastError}"');
    expect(d0.sync!.lastError, isEmpty);
    final local = <String, int>{
      'orders': d0.orders.length,
      'customers': d0.customers.length,
      'branches': d0.branches.length,
      'staff': d0.staff.length,
      'expenses': d0.expenses.length,
      'issues': d0.issues.length,
      'payouts': d0.payouts.length,
      'coupons': d0.coupons.length,
      'packagePlans': d0.packagePlans.length,
      'stock': d0.stock.length,
      'suppliers': d0.suppliers.length,
      'garments': d0.garments.length,
      'pings': d0.pings.length,
    };
    for (final e in local.entries) {
      final n = (await shopRef.collection(e.key).get(const GetOptions(source: Source.server))).size;
      log('cloud ${e.key}: $n / ${e.value}');
      expect(n, e.value, reason: '${e.key} in cloud');
    }
    expect((await shopRef.collection('meta').doc('settings').get(const GetOptions(source: Source.server))).exists, isTrue);

    // ---- log out, wipe this phone, log in with mobile typed as +91 … ----
    await s.signOut();
    await wait(t, () => find.byKey(const ValueKey('f.loginId')).evaluate().isNotEmpty, 'login screen after logout');
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await type(t, 'f.loginId', '+91 $mobile');
    await type(t, 'f.loginPw', pw);
    await tap(t, 'b.submit');
    await wait(t, () => s.owner != null && s.setupDone && find.byType(Shell).evaluate().isNotEmpty, 're-login with mobile');
    await wait(t, () => s.data!.orders.length == orders, 'orders back after re-login');
    expect(s.data!.customers.length, customers);
    expect(s.data!.shopCode, code);
    expect(s.data!.branches.length, local['branches']);
    expect(s.data!.staff.length, local['staff']);
    expect(s.data!.issues.length, local['issues']);
    expect(s.data!.coupons.length, local['coupons']);
    expect(s.data!.stock.length, local['stock']);
    log('re-login with mobile ok');

    // ---- log out, log in with email ----
    await s.signOut();
    await wait(t, () => find.byKey(const ValueKey('f.loginId')).evaluate().isNotEmpty, 'login screen 2');
    await type(t, 'f.loginId', email);
    await type(t, 'f.loginPw', pw);
    await tap(t, 'b.submit');
    await wait(t, () => s.owner != null && s.setupDone, 're-login with email');
    expect(s.owner!.uid, uid);
    log('email login ok');

    // ---- branch-wise numbers add up ----
    final d = s.data!;
    final range = DateRange.of(Period.month, DateTime.now());
    final all = Report(orders: d.orders, expenses: d.expenses, range: range).sales;
    var sum = 0.0;
    for (final b in d.branches) {
      sum += Report(orders: d.orders, expenses: d.expenses, range: range, branchId: b.id).sales;
    }
    expect(sum, closeTo(all, 0.5));
    for (final b in d.branches) {
      s.setBranchFilter(b.id);
      await t.pump();
      expect(d.ordersIn(s.scopeBranch).every((o) => o.branchId == b.id), isTrue);
    }
    s.setBranchFilter(null);
    log('branch totals ok');

    // ---- open every screen (all branches, then one branch) ----
    Future<void> visit(String name, Widget w) async {
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => w));
      await pause(t, 1500);
      final sc = find.byType(Scrollable);
      if (sc.evaluate().isNotEmpty) {
        try {
          await t.drag(sc.last, const Offset(0, -700), warnIfMissed: false);
        } catch (_) {}
        await pause(t, 500);
      }
      nav.pop();
      await pause(t, 400);
      log('screen ok: $name');
    }

    final o1 = d.orders.firstWhere((o) => o.status == 'delivered');
    final iss = d.issues.isEmpty ? null : d.issues.first;
    final staff1 = d.staff.first;
    Future<void> tour(String tag) async {
      await visit('$tag dashboard', const Scaffold(body: DashboardScreen()));
      await visit('$tag orders', const OrdersScreen());
      await visit('$tag order detail', OrderDetailScreen(orderId: o1.id));
      await visit('$tag edit order', EditOrderScreen(orderId: o1.id));
      await visit('$tag new order', const NewOrderScreen());
      await visit('$tag customers', const CustomersScreen());
      await visit('$tag customer detail', CustomerDetailScreen(customerId: o1.customerId));
      await visit('$tag staff', const StaffScreen());
      await visit('$tag payslip', PayslipScreen(staffId: staff1.id, month: monthKey(DateTime.now())));
      await visit('$tag rules', const RulesScreen());
      await visit('$tag reports', const ReportsScreen());
      await visit('$tag day close', const DayCloseScreen());
      await visit('$tag late orders', const OverdueScreen());
      await visit('$tag issues', const IssuesScreen());
      await visit('$tag issue reports', const IssueReportsScreen());
      if (iss != null) await visit('$tag issue detail', IssueDetailScreen(issueId: iss.id));
      await visit('$tag complaint', ComplaintScreen(orderId: o1.id));
      await visit('$tag wrong delivery', WrongDeliveryScreen(orderId: o1.id));
      await visit('$tag delivery board', const DeliveryBoardScreen());
      await visit('$tag route map', const RouteMapScreen());
      await visit('$tag live map', LiveMapScreen(customerId: o1.customerId, orderId: o1.id));
      await visit('$tag offers', const OffersScreen());
      await visit('$tag stock', const StockScreen());
      await visit('$tag requests', const RequestsScreen());
      await visit('$tag stock used', const StockUseScreen());
      await visit('$tag work board', const WorkBoardScreen());
      await visit('$tag notices', const NoticeBoardScreen());
      await visit('$tag audit', const AuditScreen());
      await visit('$tag customer groups', const CustomerGroupsScreen());
      await visit('$tag machines', const MachinesScreen());
      await visit('$tag meters', const MetersScreen());
      await visit('$tag staff report', const StaffReportScreen());
      await visit('$tag insights', const InsightsScreen());
      await visit('$tag booking qr', const BookingQrScreen());
      await visit('$tag expenses', const ExpensesScreen());
      await visit('$tag branches', const BranchesScreen());
      await visit('$tag rate card', const RateCardScreen());
      await visit('$tag plans', const PlansScreen());
      await visit('$tag settings', const SettingsScreen());
      await visit('$tag more', const MoreScreen());
      await visit('$tag queue', const QueueScreen());
    }

    await tour('all');
    s.setBranchFilter(d.branches[1].id);
    await pause(t, 300);
    await tour(d.branches[1].name);
    s.setBranchFilter(null);
    await pause(t, 300);
    log('screen tour ok');

    // ---- app lock shows above any open screen ----
    s.setLockPin('1234');
    final nav0 = t.state<NavigatorState>(find.byType(Navigator).first);
    nav0.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await pause(t, 800);
    s.lockNow();
    await pause(t, 800);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(s.unlock('1234'), isTrue);
    await pause(t, 600);
    expect(find.byType(LockScreen), findsNothing);
    nav0.pop();
    s.setLockPin(null);
    await pause(t, 400);
    log('app lock ok');

    // ---- staff login (manager Sunita 98200 11111 / 1111) ----
    await s.signOut();
    await wait(t, () => find.byKey(const ValueKey('b.staff')).evaluate().isNotEmpty, 'login screen 3');
    await tap(t, 'b.staff');
    await pause(t, 800);
    await type(t, 'f.staffCode', code);
    await type(t, 'f.staffMobile', '9820011111');
    await type(t, 'f.staffPin', '1111');
    await tap(t, 'b.staffGo');
    await wait(t, () => s.staffUser != null && find.byType(Shell).evaluate().isNotEmpty, 'staff login');
    expect(s.staffUser!.role, Role.manager);
    final sd = s.data!;
    await wait(t, () => sd.orders.length >= orders, 'staff sees orders');
    final cust = sd.customers.first;
    final o = sd.createOrder(
      customerId: cust.id,
      branchId: s.staffUser!.branchId,
      lines: [OrderLine(garment: 'Shirt', service: 'Dry clean', qty: 2, rate: 80)],
      by: s.actorId,
    );
    final staffOrder = o.id;
    var there = false;
    final end2 = DateTime.now().add(const Duration(seconds: 60));
    while (!there && DateTime.now().isBefore(end2)) {
      await pause(t, 2000);
      there = (await shopRef.collection('orders').doc(staffOrder).get(const GetOptions(source: Source.server))).exists;
    }
    expect(there, isTrue, reason: 'staff order reached the cloud');
    log('staff login + order ok');

    // ---- owner sees the staff order ----
    await s.signOut();
    await wait(t, () => find.byKey(const ValueKey('f.loginId')).evaluate().isNotEmpty, 'login screen 4');
    await type(t, 'f.loginId', mobile);
    await type(t, 'f.loginPw', pw);
    await tap(t, 'b.submit');
    await wait(t, () => s.owner != null && s.setupDone, 'owner again');
    await wait(t, () => s.data!.orders.any((x) => x.id == staffOrder), 'owner sees staff order');
    log('owner sees staff order');

    // ---- delete sample data: only own records stay, also in the cloud ----
    final od = s.data!;
    final removed = od.clearSample();
    expect(removed, greaterThan(100));
    expect(od.orders.every((x) => !x.id.startsWith('demo_')), isTrue);
    expect(od.orders.any((x) => x.id == staffOrder), isTrue, reason: 'own order kept');
    await od.flush();
    await pause(t, 3000);
    await wait(t, () => !od.sync!.busy, 'delete upload', secs: 180);
    final leftOrders = (await shopRef.collection('orders').get(const GetOptions(source: Source.server))).size;
    expect(leftOrders, od.orders.length);
    expect((await shopRef.collection('branches').get(const GetOptions(source: Source.server))).size, od.branches.length);
    log('sample deleted: $removed records, cloud orders $leftOrders');

    // ---- clean up the test account ----
    try {
      for (final col in ['orders', 'customers', 'activity', 'attendance', 'staff', 'branches', 'garments', 'expenses', 'issues', 'payouts', 'pings', 'meta', 'coupons', 'packagePlans', 'stock', 'stockMoves', 'suppliers']) {
        final qs = await shopRef.collection(col).get();
        for (var i = 0; i < qs.docs.length; i += 400) {
          final b = FirebaseFirestore.instance.batch();
          for (final doc in qs.docs.skip(i).take(400)) {
            b.delete(doc.reference);
          }
          await b.commit();
        }
      }
      await shopRef.delete();
      await FirebaseFirestore.instance.collection('owners').doc(uid).delete();
      await FirebaseAuth.instance.currentUser?.delete();
      log('cleaned up');
    } catch (e) {
      log('cleanup skipped: $e');
    }
    FlutterError.onError = orig;
    log('UI warnings: ${uiWarnings.length}');
    log('ALL PASSED');
  });
}
