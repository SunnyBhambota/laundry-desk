/// Pure checks used by the login / sign-up screens (tested in test/validators_test.dart).
class V {
  V._();

  static String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static bool isEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

  /// Mobile without country code: 7–15 digits (India: 10).
  /// Indian number typed as +91 98…, 091…, 098… → last 10 digits.
  static String local(String s, {String dial = '+91'}) {
    var d = digits(s);
    if (dial == '+91') {
      if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
      if (d.length == 13 && d.startsWith('091')) d = d.substring(3);
      if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    }
    return d;
  }

  static bool isMobile(String s, {String dial = '+91'}) {
    final d = local(s, dial: dial);
    if (dial == '+91') return RegExp(r'^[6-9]\d{9}$').hasMatch(d);
    return d.length >= 7 && d.length <= 15;
  }

  static bool isLoginId(String s) => isEmail(s) || isMobile(s);

  static bool isPassword(String s) => s.length >= 8;

  static bool isName(String s) => s.trim().length >= 2;

  /// 0–4: length 8+, a capital, a number, a symbol. Anything typed counts as at least 1.
  static int strength(String s) {
    if (s.isEmpty) return 0;
    var n = 0;
    if (s.length >= 8) n++;
    if (RegExp(r'[A-Z]').hasMatch(s)) n++;
    if (RegExp(r'[0-9]').hasMatch(s)) n++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(s)) n++;
    return n == 0 ? 1 : n;
  }
}

/// What the runaway button says, from how many checks are still missing.
enum RunPhase { idle, loading, done }

String runawayStatus({
  required bool login,
  required int total,
  required int left,
  required RunPhase phase,
  required String Function(String) t,
}) {
  if (phase == RunPhase.loading) return t(login ? 'run.signingIn' : 'run.creating');
  if (phase == RunPhase.done) return t(login ? 'run.doneLogin' : 'run.doneSignup');
  if (left == 0) return t('run.locked');
  if (left == total) return t(login ? 'run.fillBoth' : 'run.fillAll');
  if (left == 1) return t('run.oneToGo');
  return t('run.nToGo').replaceAll('{n}', '$left');
}
