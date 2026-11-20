import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';
import '../data/shop_data.dart';

/// BrotriX control: each shop's plan / expiry / modules live in licenses/{ownerUid}.
/// Only BrotriX admins (admins/{uid} in Firestore) can change them; the owner can only read.
class LicenseService {
  LicenseService._();
  static final instance = LicenseService._();
  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  /// Owner phone: read (or create the trial) and apply to the shop. Safe if rules are not set yet.
  Future<void> sync(ShopData d, {required String shopName, String phone = ''}) async {
    if (!d.cloudOn || d.ownerUid.isEmpty) return;
    try {
      final ref = _fs.collection('licenses').doc(d.ownerUid);
      final doc = await ref.get();
      if (!doc.exists) {
        await ref.set({
          'plan': 'trial',
          'until': DateTime.now().add(const Duration(days: AppConfig.trialDays)).toIso8601String(),
          'disabled': <String>[],
          'shopName': shopName,
          'phone': phone,
          'code': d.shopCode,
          'createdAt': DateTime.now().toIso8601String(),
        });
        return;
      }
      final j = doc.data()!;
      final plan = j['plan'] as String? ?? d.plan;
      final until = DateTime.tryParse(j['until'] as String? ?? '');
      final disabled = ((j['disabled'] as List?) ?? []).map((e) => '$e').toSet();
      final changed = plan != d.plan || until?.toIso8601String() != d.planUntil?.toIso8601String() || !_same(disabled, d.disabledModules);
      if (changed) {
        d
          ..plan = plan
          ..planUntil = until
          ..disabledModules = disabled;
        d.changed();
      }
      // keep the shop name / code fresh for the BrotriX list
      if (j['shopName'] != shopName || j['code'] != d.shopCode) {
        await ref.update({'shopName': shopName, 'code': d.shopCode, 'phone': phone});
      }
    } catch (_) {}
  }

  bool _same(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  Future<bool> isAdmin() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return false;
    try {
      return (await _fs.collection('admins').doc(u.uid).get()).exists;
    } catch (_) {
      return false;
    }
  }

  Future<List<(String, Map<String, dynamic>)>> all() async {
    final qs = await _fs.collection('licenses').get();
    final l = qs.docs.map((d) => (d.id, d.data())).toList();
    l.sort((a, b) => '${a.$2['shopName']}'.toLowerCase().compareTo('${b.$2['shopName']}'.toLowerCase()));
    return l;
  }

  Future<void> update(String uid, Map<String, dynamic> changes) async {
    final u = FirebaseAuth.instance.currentUser;
    await _fs.collection('licenses').doc(uid).update({...changes, 'updatedBy': u?.uid ?? '', 'updatedAt': DateTime.now().toIso8601String()});
  }
}
