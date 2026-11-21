import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Test builds stop working [AppConfig.testDays] days after they were built
/// (until the app is on the Play Store). Built in CI with --dart-define=BUILD_EPOCH=<seconds>.
/// Local / unit-test runs have no build time, so they never expire.
class ExpiryService extends ChangeNotifier {
  ExpiryService._();
  static final instance = ExpiryService._();

  bool expired = false;
  DateTime? serverNow;

  DateTime? get builtAt => AppConfig.buildEpoch == 0 ? null : DateTime.fromMillisecondsSinceEpoch(AppConfig.buildEpoch * 1000, isUtc: true);
  DateTime? get expiresAt => builtAt?.add(const Duration(days: AppConfig.testDays));

  /// Whole days left (0 = last day), null when the build never expires.
  int? get daysLeft => expiresAt == null ? null : expiresAt!.difference((serverNow ?? DateTime.now()).toUtc()).inDays;

  void check() {
    final end = expiresAt;
    if (end == null) return;
    final now = DateTime.now().toUtc();
    final t = (serverNow != null && serverNow!.isAfter(now)) ? serverNow! : now; // a set-back phone clock does not help
    final e = !t.isBefore(end);
    if (e != expired) {
      expired = e;
      notifyListeners();
    }
  }

  /// Asks a web server for the real time (when online), so changing the phone date does not help.
  Future<void> syncServerTime() async {
    if (expiresAt == null) return;
    try {
      final r = await http.head(Uri.parse('https://github.com')).timeout(const Duration(seconds: 4));
      final h = r.headers['date'];
      if (h != null) serverNow = HttpDate.parse(h).toUtc();
    } catch (_) {}
    check();
  }
}
