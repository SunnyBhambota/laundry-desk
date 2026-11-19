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
import 'package:laundry_desk/screens/shell.dart';
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

  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

  Future<void> type(WidgetTester t, String key, String text) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.pump();
    await t.enterText(field(key), text);
    await t.pump();
  }

  Future<void> tap(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.pump();
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

    // cloud copy must match what the phone has
    final shopRef = FirebaseFirestore.instance.collection('shops').doc(uid);
    var cloudOrders = 0;
    final cloudEnd = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(cloudEnd)) {
      await pause(t, 3000);
      cloudOrders = (await shopRef.collection('orders').get(const GetOptions(source: Source.server))).size;
      if (cloudOrders == orders) break;
    }
    log('cloud orders $cloudOrders / $orders');
    expect(cloudOrders, orders, reason: 'all orders reached the cloud');
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
    log('ALL PASSED');
  });
}
