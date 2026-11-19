import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  static String fullMobile(String input, {String dial = '+91'}) => V.digits(dial) + V.local(input, dial: dial);

  // ---------- session ----------

  Future<Owner?> currentOwner() async {
    if (_cloud) {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null || u.isAnonymous) return null; // anonymous = a staff phone
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

  /// Staff phones sign in anonymously; access to a shop then comes from members/{uid}.
  Future<String?> ensureStaffSession() async {
    if (!_cloud) return null;
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null || !auth.currentUser!.isAnonymous) {
      if (auth.currentUser != null) await auth.signOut();
      await auth.signInAnonymously();
    }
    return auth.currentUser?.uid;
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
        await _saveEmailLogin(owner);
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
        var email = isMail ? loginId.trim().toLowerCase() : phoneEmail(fullMobile(loginId, dial: dial));
        if (isMail && !email.endsWith('@phone.laundrydesk.app')) {
          // Accounts are made with the mobile number; the email is only a second way in.
          final login = await _loginForEmail(email);
          if (login == null) throw AuthError('emailUnknown');
          email = login;
        }
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
        final o = await currentOwner();
        if (o == null) throw AuthError('generic');
        await _saveEmailLogin(o);
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

  // ---------- email as a second login id ----------

  static String _mailKey(String email) => 'mail_${sha256.convert(utf8.encode(email.trim().toLowerCase())).toString().substring(0, 40)}';

  Future<void> _saveEmailLogin(Owner o) async {
    final u = FirebaseAuth.instance.currentUser;
    if (!_cloud || u == null || u.isAnonymous || !V.isEmail(o.email) || (u.email ?? '').isEmpty) return;
    if (!(u.email ?? '').endsWith('@phone.laundrydesk.app')) return; // Google accounts
    try {
      await FirebaseFirestore.instance.collection('shopCodes').doc(_mailKey(o.email)).set({'ownerUid': u.uid, 'login': u.email});
    } catch (_) {}
  }

  Future<String?> _loginForEmail(String email) async {
    final auth = FirebaseAuth.instance;
    try {
      if (auth.currentUser == null) await auth.signInAnonymously();
      final doc = await FirebaseFirestore.instance.collection('shopCodes').doc(_mailKey(email)).get();
      return doc.data()?['login'] as String?;
    } catch (_) {
      throw AuthError('network');
    }
  }

  // ---------- Google ----------

  /// Owner sign-in / sign-up with a Google account (cloud mode only).
  /// Returns null when the user closes the Google chooser.
  Future<Owner?> signInWithGoogle() async {
    if (!_cloud) throw AuthError('cloudOnly');
    try {
      final g = GoogleSignIn(serverClientId: AppConfig.googleWebClientId, scopes: const ['email']);
      try {
        await g.signOut(); // always show the account chooser
      } catch (_) {}
      final acc = await g.signIn();
      if (acc == null) return null;
      final auth = await acc.authentication;
      final cred = GoogleAuthProvider.credential(idToken: auth.idToken, accessToken: auth.accessToken);
      final res = await FirebaseAuth.instance.signInWithCredential(cred);
      final u = res.user!;
      final ref = FirebaseFirestore.instance.collection('owners').doc(u.uid);
      final doc = await ref.get();
      if (!doc.exists) {
        final owner = Owner(uid: u.uid, name: u.displayName ?? acc.displayName ?? '', mobile: '', email: u.email ?? acc.email);
        await ref.set({...owner.toJson(), 'via': 'google', 'createdAt': FieldValue.serverTimestamp()});
        return owner;
      }
      return Owner.fromJson({...doc.data()!, 'uid': u.uid});
    } on FirebaseAuthException catch (e) {
      throw AuthError(e.code == 'operation-not-allowed' ? 'googleOff' : _mapFirebase(e.code));
    } on AuthError {
      rethrow;
    } catch (e) {
      final m = e.toString();
      if (m.contains('network')) throw AuthError('network');
      if (m.contains('ApiException: 10') || m.contains('sign_in_failed')) throw AuthError('googleOff');
      throw AuthError('generic');
    }
  }

  /// Change the owner's password (needs the current one).
  Future<void> changePassword(String current, String next) async {
    if (!_cloud) {
      final p = await SharedPreferences.getInstance();
      final uid = p.getString(_kSession);
      final list = _accounts(p);
      final i = list.indexWhere((a) => a['uid'] == uid);
      if (i < 0 || list[i]['hash'] != _hash(current, list[i]['salt'] as String)) throw AuthError('wrong');
      final salt = _salt();
      list[i] = {...list[i], 'salt': salt, 'hash': _hash(next, salt)};
      await p.setString(_kAccounts, jsonEncode(list));
      return;
    }
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.email == null) throw AuthError('generic');
    try {
      final hasPw = u.providerData.any((p) => p.providerId == 'password');
      if (hasPw) {
        await u.reauthenticateWithCredential(EmailAuthProvider.credential(email: u.email!, password: current));
        await u.updatePassword(next);
      } else {
        throw AuthError('generic');
      }
    } on FirebaseAuthException catch (e) {
      throw AuthError(_mapFirebase(e.code));
    }
  }

  /// Link a Google account to a mobile+password owner: if the password is ever
  /// forgotten, "Continue with Google" opens the same shop, then set a new password.
  Future<bool> linkGoogle() async {
    if (!_cloud) throw AuthError('cloudOnly');
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw AuthError('generic');
    try {
      final g = GoogleSignIn(serverClientId: AppConfig.googleWebClientId, scopes: const ['email']);
      try {
        await g.signOut();
      } catch (_) {}
      final acc = await g.signIn();
      if (acc == null) return false;
      final a = await acc.authentication;
      await u.linkWithCredential(GoogleAuthProvider.credential(idToken: a.idToken, accessToken: a.accessToken));
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' || e.code == 'provider-already-linked') throw AuthError('googleUsed');
      throw AuthError(_mapFirebase(e.code));
    }
  }

  /// Google account linked to the signed-in owner (or '' if none).
  String get linkedGoogle {
    if (!_cloud) return '';
    final u = FirebaseAuth.instance.currentUser;
    final g = u?.providerData.where((p) => p.providerId == 'google.com');
    return (g == null || g.isEmpty) ? '' : (g.first.email ?? 'Google');
  }

  /// Signed in with Google only (no password set yet).
  bool get hasPassword {
    if (!_cloud) return true;
    return FirebaseAuth.instance.currentUser?.providerData.any((p) => p.providerId == 'password') ?? false;
  }

  /// Owner who came by Google sets a password so mobile login also works.
  Future<void> addPassword(String mobileFull, String next) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw AuthError('generic');
    try {
      await u.linkWithCredential(EmailAuthProvider.credential(email: phoneEmail(mobileFull), password: next));
    } on FirebaseAuthException catch (e) {
      throw AuthError(e.code == 'email-already-in-use' || e.code == 'credential-already-in-use' ? 'exists' : _mapFirebase(e.code));
    }
  }

  /// Saves the mobile number for owners who joined with Google.
  Future<void> saveOwnerMobile(Owner o, String mobile) async {
    if (_cloud) {
      await FirebaseFirestore.instance.collection('owners').doc(o.uid).set({'mobile': mobile}, SetOptions(merge: true));
    }
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
