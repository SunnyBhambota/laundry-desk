import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../logic/validators.dart';
import '../models/models.dart';

/// Error codes shown to the user through strings 'err.<code>'.
class AuthError implements Exception {
  AuthError(this.code);
  final String code; // wrong | exists | network | generic
  @override
  String toString() => 'AuthError($code)';
}

/// Owner login.
/// - Cloud mode (Firebase set up in AppConfig): Firebase Auth with the mobile number as the
///   login (stored as <digits>@phone.laundrydesk.app), profile + shop in Firestore.
/// - Demo mode (no Firebase yet): accounts are kept on this phone, password stored as a
///   salted SHA-256 hash, never as plain text.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _kAccounts = 'ld_accounts';
  static const _kSession = 'ld_session';

  bool _cloud = false;
  bool get cloud => _cloud;

  Future<void> init() async {
    if (!AppConfig.firebaseReady) return;
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
          storageBucket: AppConfig.firebaseStorageBucket.isEmpty ? null : AppConfig.firebaseStorageBucket,
        ),
      );
      _cloud = true;
    } catch (_) {
      _cloud = false;
    }
  }

  static String phoneEmail(String mobileDigits) => '$mobileDigits@phone.laundrydesk.app';

  static String fullMobile(String input, {String dial = '+91'}) => V.digits(dial) + V.digits(input);

  // ---------- session ----------

  Future<Owner?> currentOwner() async {
    if (_cloud) {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return null;
      try {
        final doc = await FirebaseFirestore.instance.collection('owners').doc(u.uid).get();
        if (doc.exists) return Owner.fromJson({...doc.data()!, 'uid': u.uid});
      } catch (_) {}
      return Owner(uid: u.uid, name: u.displayName ?? '', mobile: (u.email ?? '').split('@').first);
    }
    final p = await SharedPreferences.getInstance();
    final uid = p.getString(_kSession);
    if (uid == null) return null;
    final acc = _accounts(p).where((a) => a['uid'] == uid);
    if (acc.isEmpty) return null;
    return Owner.fromJson(acc.first);
  }

  Future<void> signOut() async {
    if (_cloud) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSession);
  }

  // ---------- register ----------

  Future<Owner> register({
    required String name,
    required String mobile,
    required String password,
    String email = '',
    String dial = '+91',
  }) async {
    final full = fullMobile(mobile, dial: dial);
    if (_cloud) {
      try {
        final cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: phoneEmail(full), password: password);
        final u = cred.user!;
        await u.updateDisplayName(name.trim());
        final owner = Owner(uid: u.uid, name: name.trim(), mobile: full, email: email.trim());
        await FirebaseFirestore.instance.collection('owners').doc(u.uid).set({
          ...owner.toJson(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        return owner;
      } on FirebaseAuthException catch (e) {
        throw AuthError(_mapFirebase(e.code));
      } catch (_) {
        throw AuthError('generic');
      }
    }
    final p = await SharedPreferences.getInstance();
    final list = _accounts(p);
    if (list.any((a) => a['mobile'] == full)) throw AuthError('exists');
    final salt = _salt();
    final owner = Owner(uid: 'local_${DateTime.now().millisecondsSinceEpoch}', name: name.trim(), mobile: full, email: email.trim());
    list.add({...owner.toJson(), 'salt': salt, 'hash': _hash(password, salt)});
    await p.setString(_kAccounts, jsonEncode(list));
    await p.setString(_kSession, owner.uid);
    return owner;
  }

  // ---------- login ----------

  Future<Owner> signIn({required String loginId, required String password, String dial = '+91'}) async {
    final isMail = V.isEmail(loginId);
    if (_cloud) {
      try {
        final email = isMail ? loginId.trim().toLowerCase() : phoneEmail(fullMobile(loginId, dial: dial));
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
        final o = await currentOwner();
        if (o == null) throw AuthError('generic');
        return o;
      } on FirebaseAuthException catch (e) {
        throw AuthError(_mapFirebase(e.code));
      }
    }
    final p = await SharedPreferences.getInstance();
    final want = isMail ? loginId.trim().toLowerCase() : fullMobile(loginId, dial: dial);
    for (final a in _accounts(p)) {
      final match = isMail ? (a['email'] as String? ?? '').toLowerCase() == want : a['mobile'] == want;
      if (match && a['hash'] == _hash(password, a['salt'] as String)) {
        await p.setString(_kSession, a['uid'] as String);
        return Owner.fromJson(a);
      }
    }
    throw AuthError('wrong');
  }

  // ---------- helpers ----------

  static List<Map<String, dynamic>> _accounts(SharedPreferences p) {
    final raw = p.getString(_kAccounts);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static String _salt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static String _hash(String password, String salt) => sha256.convert(utf8.encode('$salt:$password')).toString();

  static String _mapFirebase(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'exists';
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-credential':
      case 'invalid-email':
        return 'wrong';
      case 'network-request-failed':
        return 'network';
      default:
        return 'generic';
    }
  }
}
