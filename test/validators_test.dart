import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_desk/logic/validators.dart';

void main() {
  test('mobile and email login ids', () {
    expect(V.isMobile('98765 43210'), isTrue);
    expect(V.isMobile('12345'), isFalse);
    expect(V.isMobile('5876543210'), isFalse); // Indian mobiles start 6-9
    expect(V.isEmail('owner@shop.in'), isTrue);
    expect(V.isEmail('owner@shop'), isFalse);
    expect(V.isLoginId('9876543210'), isTrue);
    expect(V.isLoginId('a@b.co'), isTrue);
    expect(V.isLoginId('+91 98765 43210'), isTrue);
    expect(V.isLoginId('09876543210'), isTrue);
    expect(V.local('+91-98765-43210'), '9876543210');
  });

  test('password strength 0-4', () {
    expect(V.strength(''), 0);
    expect(V.strength('abc'), 1);
    expect(V.strength('abcdefgh'), 1);
    expect(V.strength('Abcdefg1'), 3);
    expect(V.strength('Abcdefg1!'), 4);
  });

  test('runaway status text', () {
    String t(String k) => k;
    expect(runawayStatus(login: true, total: 2, left: 2, phase: RunPhase.idle, t: t), 'run.fillBoth');
    expect(runawayStatus(login: true, total: 2, left: 1, phase: RunPhase.idle, t: t), 'run.oneToGo');
    expect(runawayStatus(login: false, total: 4, left: 3, phase: RunPhase.idle, t: t), 'run.nToGo');
    expect(runawayStatus(login: true, total: 2, left: 0, phase: RunPhase.idle, t: t), 'run.locked');
    expect(runawayStatus(login: true, total: 2, left: 0, phase: RunPhase.loading, t: t), 'run.signingIn');
  });
}
