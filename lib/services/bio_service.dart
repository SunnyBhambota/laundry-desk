import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Fingerprint / face unlock using the phone's own screen-lock sensors.
class BioService {
  BioService._();
  static final instance = BioService._();
  final _auth = LocalAuthentication();

  /// Phone has a fingerprint/face sensor with something enrolled.
  Future<bool> available() async {
    if (kIsWeb) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlock(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    }
  }
}
