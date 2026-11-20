import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../data/ops_models.dart';
import '../data/sample_data.dart';
import '../data/shop_data.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/notify_service.dart';
import '../services/license_service.dart';
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

  /// Owner-set yes/no rights (discount, refund, editOrder, cancel, deleteCustomer, expenses, reports, rates).
  bool can(String key) => data?.can(staffUser, key) ?? isOwner;

  /// Staff (non-owner) only see their own branch.
  String? get scopeBranch => isOwner ? branchFilter : (role == Role.manager ? staffUser!.branchId : staffUser!.branchId);

  String t(String key) => S.of(lang, key);

  bool get premium => shop != null && data != null && data!.premiumActive(shop!);

  /// Free-plan limit hit? Returns a message key or null. kind: order | staff | branch
  String? limit(String kind) {
    if (premium || data == null) return null;
    final d = data!;
    switch (kind) {
      case 'order':
        final now = DateTime.now();
        final n = d.orders.where((o) => o.createdAt.year == now.year && o.createdAt.month == now.month).length;
        return n >= AppConfig.freeOrdersPerMonth ? 'limit.order' : null;
      case 'staff':
        return d.staff.where((s) => s.active).length >= AppConfig.freeMaxStaff ? 'limit.staff' : null;
      case 'branch':
        return d.branches.length >= AppConfig.freeMaxBranches ? 'limit.branch' : null;
    }
    return null;
  }

  bool module(String m) => shop != null && data != null && data!.moduleOn(m, shop!);

  Future<void> load() async {
    await loadBio();
    final p = await SharedPreferences.getInstance();
    lang = p.getString('ld_lang') ?? 'en';
    textScale = p.getDouble('ld_text_scale') ?? 1.0;
    dark = p.getBool('ld_dark') ?? false;
    owner = await AuthService.instance.currentOwner();
    if (owner != null) {
      await _openShop(owner!.uid);
      if (shop != null && data != null) LicenseService.instance.sync(data!, shopName: shop!.shopName, phone: owner!.mobile);
    } else {
      final raw = p.getStringList(_kStaff);
      if (raw != null && raw.length == 2) {
        if (AuthService.instance.cloud) await AuthService.instance.ensureStaffSession();
        await _openShop(raw[0], admin: false);
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

  Future<void> _openShop(String uid, {bool admin = true}) async {
    shopOwnerUid = uid;
    shop = await ShopStore.instance.load(uid);
    data?.removeListener(notifyListeners);
    data?.dispose();
    data = await ShopData.open(uid, admin: admin);
    data!.addListener(notifyListeners);
    data!.onRemote = _onRemote;
    _seen = null;
    NotifyService.instance.init();
  }

  // ---------- phone notifications (new request / complaint / work / notice) ----------
  Set<String>? _seen;

  Map<String, (String, String)> _alertKeys() {
    final d = data;
    final m = <String, (String, String)>{};
    if (d == null) return m;
    final me = actorId;
    final myBranch = staffUser?.branchId;
    if (canManage) {
      for (final r in d.requests.where((r) => r.status == 'pending' && (myBranch == null || r.branchId == myBranch))) {
        m['rq${r.id}'] = (
          r.kind == 'leave' ? 'Leave request – ${d.nameOf(r.by)}' : 'Staff request${r.urgent ? ' (URGENT)' : ''} – ${d.nameOf(r.by)}',
          r.kind == 'leave' ? '${r.leaveDays} day(s) ${r.note}' : '${r.item} × ${r.qty.toStringAsFixed(0)} ${r.unit}'
        );
      }
      for (final i in d.issues.where((i) => i.open && (myBranch == null || i.branchId == myBranch))) {
        m['is${i.id}'] = ('New complaint ${i.code}', i.reason);
      }
      for (final a in d.activity.where((a) => a.kind == 'count.mismatch' && DateTime.now().difference(a.at).inHours < 24)) {
        m['ac${a.id}'] = ('Piece count did not match', a.text);
      }
    }
    if (staffUser != null) {
      for (final n in d.noticesFor(me, staffUser!.branchId).where((n) => !n.readBy.contains(me))) {
        m['nt${n.id}'] = ('Notice from the boss', n.text);
      }
      for (final w in d.openWork(me)) {
        m['wk${w.$1.id}#${w.$2}'] = ('New work for you', '${w.$1.code}: ${w.$1.lines[w.$2].garment} – ${w.$1.lines[w.$2].service}');
      }
      for (final o in d.orders.where((o) => o.open && (o.deliveryAgent == me || o.pickupAgent == me))) {
        m['dl${o.id}${o.status}'] = (o.status == 'pickup' ? 'New pickup' : 'Delivery task', '${o.code} · ${d.customer(o.customerId)?.name ?? ''}');
      }
      for (final r in d.requests.where((r) => r.by == me && r.status != 'pending')) {
        m['rs${r.id}${r.status}'] = ('Your request: ${r.status}', '${r.item}${r.reply.isEmpty ? '' : ' – ${r.reply}'}');
      }
    }
    return m;
  }

  void _onRemote() {
    final now = _alertKeys();
    final seen = _seen;
    _seen = now.keys.toSet();
    if (seen == null) return; // first look: don't flood
    for (final e in now.entries) {
      if (!seen.contains(e.key)) NotifyService.instance.show(e.value.$1, e.value.$2);
    }
  }

  /// Call when the shop is ready (after login) so old items don't notify.
  void resetAlerts() => _seen = _alertKeys().keys.toSet();

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
    resetAlerts();
    if (shop != null && data != null) LicenseService.instance.sync(data!, shopName: shop!.shopName, phone: o.mobile);
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
    LicenseService.instance.sync(d, shopName: s.shopName, phone: owner?.mobile ?? '');
    notifyListeners();
  }

  Future<void> updateShop(ShopProfile s) async {
    if (shopOwnerUid.isEmpty) return;
    await ShopStore.instance.save(shopOwnerUid, s);
    shop = s;
    notifyListeners();
  }

  /// Staff login with shop code + mobile + PIN. Returns error key or null.
  /// Cloud: anonymous sign-in, then a members/{uid} record that Firestore rules accept
  /// only with the right PIN hash. Demo: checked against this phone's data.
  Future<String?> staffLogin({required String code, required String mobile, required String pin}) async {
    final c = code.trim().toUpperCase();
    final p10 = phone10(mobile);
    if (c.length < 4 || p10.length < 7 || pin.length != 4) return 'err.staffLogin';
    try {
      if (AuthService.instance.cloud) {
        final uid = await AuthService.instance.ensureStaffSession();
        final ownerUid = await ShopData.ownerForCode(c);
        if (ownerUid == null || uid == null) return 'err.shopCode';
        try {
          await FirebaseFirestore.instance.collection('members').doc(uid).set({
            'ownerUid': ownerUid,
            'code': c,
            'phone': p10,
            'key': ShopData.staffKey(c, p10, pin),
            'at': DateTime.now().toIso8601String(),
          });
        } catch (_) {
          return 'err.staffLogin';
        }
        await _openShop(ownerUid, admin: false);
        final s = data!.staff.where((x) => x.active && phone10(x.phone) == p10);
        if (s.isEmpty) return 'err.staffLogin';
        staffUser = s.first;
      } else {
        final ownerUid = await ShopData.ownerForCode(c);
        if (ownerUid == null) return 'err.shopCode';
        await _openShop(ownerUid, admin: false);
        final s = data!.verifyStaff(p10, pin);
        if (s == null) return 'err.staffLogin';
        staffUser = s;
      }
    } catch (_) {
      return 'err.network';
    }
    owner = null;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kStaff, [shopOwnerUid, staffUser!.id]);
    data!.checkIn(staffUser!.id);
    _startTracking();
    resetAlerts();
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

  // dark mode (this phone only)
  bool dark = false;

  Future<void> setDark(bool v) async {
    dark = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('ld_dark', v);
  }

  // big text for older staff (this phone only)
  double textScale = 1.0;

  Future<void> setTextScale(double v) async {
    textScale = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('ld_text_scale', v);
  }

  // fingerprint / face unlock: a choice of this phone only (PIN stays as the backup)
  static const _kBio = 'ld_bio_unlock';
  bool bioOn = false;

  Future<void> loadBio() async {
    final p = await SharedPreferences.getInstance();
    bioOn = p.getBool(_kBio) ?? false;
  }

  Future<void> setBio(bool on) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBio, on);
    bioOn = on;
    notifyListeners();
  }

  void unlockWithBio() {
    locked = false;
    notifyListeners();
  }

  void setLockPin(String? pin) {
    if (data == null) return;
    data!.lockHash = pin == null || pin.isEmpty ? '' : _pinHash(pin);
    data!.changed();
  }

  String _pinHash(String pin) => sha256.convert(utf8.encode('ld-lock:$shopOwnerUid:$pin')).toString();

  void refresh() => notifyListeners();

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
    }
    await data?.flush(); // send last changes while still signed in
    data?.sync?.stop();
    await AuthService.instance.signOut();
    owner = null;
    staffUser = null;
    shop = null;
    data?.removeListener(notifyListeners);
    data?.dispose();
    data = null;
    branchFilter = null;
    notifyListeners();
  }
}
