import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ops_models.dart';
import '../data/sample_data.dart';
import '../data/shop_data.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/shop_store.dart';
import '../services/tracking_service.dart';

/// Session: who is using the app (owner or a staff member) and which shop.
class AppState extends ChangeNotifier {
  Owner? owner;
  Staff? staffUser;
  String shopOwnerUid = '';
  ShopProfile? shop;
  ShopData? data;
  String lang = 'en';
  bool loaded = false;

  /// Branch filter on owner screens (null = all branches).
  String? branchFilter;

  static const _kStaff = 'ld_staff_session';

  bool get signedIn => owner != null || staffUser != null;
  bool get setupDone => shop != null && (data?.initialised ?? false);
  Role get role => staffUser?.role ?? Role.owner;
  String get actorId => staffUser?.id ?? 'owner';
  String get actorName => staffUser?.name ?? owner?.name ?? '';
  bool get isOwner => staffUser == null;
  bool get canManage => role == Role.owner || role == Role.manager;

  /// Staff (non-owner) only see their own branch.
  String? get scopeBranch => isOwner ? branchFilter : (role == Role.manager ? staffUser!.branchId : staffUser!.branchId);

  String t(String key) => S.of(lang, key);

  bool module(String m) => shop != null && data != null && data!.moduleOn(m, shop!);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    lang = p.getString('ld_lang') ?? 'en';
    owner = await AuthService.instance.currentOwner();
    if (owner != null) {
      await _openShop(owner!.uid);
    } else {
      final raw = p.getStringList(_kStaff);
      if (raw != null && raw.length == 2) {
        await _openShop(raw[0]);
        staffUser = data?.staffBy(raw[1]);
        if (staffUser == null || !staffUser!.active) {
          staffUser = null;
          await p.remove(_kStaff);
        } else {
          _startTracking();
        }
      }
    }
    locked = lockOn;
    loaded = true;
    notifyListeners();
  }

  Future<void> _openShop(String uid) async {
    shopOwnerUid = uid;
    shop = await ShopStore.instance.load(uid);
    data?.removeListener(notifyListeners);
    data = await ShopData.open(uid);
    data!.addListener(notifyListeners);
  }

  Future<void> setLang(String l) async {
    lang = l;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('ld_lang', l);
  }

  Future<void> signedInAs(Owner o) async {
    owner = o;
    staffUser = null;
    await _openShop(o.uid);
    notifyListeners();
  }

  Future<void> saveShop(ShopProfile s, {bool sample = false}) async {
    if (owner == null) return;
    await ShopStore.instance.save(owner!.uid, s);
    shop = s;
    final d = data ?? await ShopData.open(owner!.uid);
    if (data == null) {
      data = d;
      d.addListener(notifyListeners);
    }
    if (!d.initialised) await d.initialise(s);
    if (sample && !d.hasSample) SampleData.fill(d, services: s.services);
    notifyListeners();
  }

  Future<void> updateShop(ShopProfile s) async {
    if (shopOwnerUid.isEmpty) return;
    await ShopStore.instance.save(shopOwnerUid, s);
    shop = s;
    notifyListeners();
  }

  /// Staff login with shop code + mobile + PIN. Returns error key or null.
  Future<String?> staffLogin({required String code, required String mobile, required String pin}) async {
    final uid = await ShopData.ownerForCode(code);
    if (uid == null) return 'err.shopCode';
    await _openShop(uid);
    final digits = mobile.replaceAll(RegExp(r'[^0-9]'), '');
    final s = data!.staff.where((x) => x.active && x.phone.endsWith(digits.length > 10 ? digits.substring(digits.length - 10) : digits) && x.pin == pin);
    if (digits.length < 7 || s.isEmpty) return 'err.staffLogin';
    staffUser = s.first;
    owner = null;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kStaff, [uid, staffUser!.id]);
    data!.checkIn(staffUser!.id);
    _startTracking();
    notifyListeners();
    return null;
  }

  void _startTracking() {
    if (staffUser?.role == Role.delivery && data != null && module('delivery')) {
      TrackingService.instance.start(data!, staffUser!.id);
    }
  }

  // ---------- app lock (owner) ----------
  bool locked = false;

  bool get lockOn => isOwner && (data?.lockHash.isNotEmpty ?? false);

  void lockNow() {
    if (lockOn) {
      locked = true;
      notifyListeners();
    }
  }

  bool unlock(String pin) {
    if (data == null || data!.lockHash != _pinHash(pin)) return false;
    locked = false;
    notifyListeners();
    return true;
  }

  void setLockPin(String? pin) {
    if (data == null) return;
    data!.lockHash = pin == null || pin.isEmpty ? '' : _pinHash(pin);
    data!.changed();
  }

  String _pinHash(String pin) => sha256.convert(utf8.encode('ld-lock:$shopOwnerUid:$pin')).toString();

  void setBranchFilter(String? id) {
    branchFilter = id;
    notifyListeners();
  }

  Future<void> signOut() async {
    TrackingService.instance.stop();
    locked = false;
    if (staffUser != null) {
      data?.checkOut(staffUser!.id);
      final p = await SharedPreferences.getInstance();
      await p.remove(_kStaff);
    } else {
      await AuthService.instance.signOut();
    }
    owner = null;
    staffUser = null;
    shop = null;
    data?.removeListener(notifyListeners);
    data = null;
    branchFilter = null;
    notifyListeners();
  }
}
