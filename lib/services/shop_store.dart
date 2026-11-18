import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'auth_service.dart';

/// Saves the shop profile on the phone, and in Firestore (shops/{ownerUid}) in cloud mode.
class ShopStore {
  ShopStore._();
  static final ShopStore instance = ShopStore._();

  String _key(String uid) => 'ld_shop_$uid';

  Future<ShopProfile?> load(String uid) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(uid));
    if (raw != null) {
      try {
        return ShopProfile.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    if (AuthService.instance.cloud) {
      try {
        final doc = await FirebaseFirestore.instance.collection('shops').doc(uid).get();
        if (doc.exists) {
          final shop = ShopProfile.fromJson(doc.data()!);
          await p.setString(_key(uid), jsonEncode(shop.toJson()));
          return shop;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> save(String uid, ShopProfile shop) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(uid), jsonEncode(shop.toJson()));
    if (AuthService.instance.cloud) {
      try {
        await FirebaseFirestore.instance.collection('shops').doc(uid).set({...shop.toJson(), 'ownerUid': uid});
      } catch (_) {
        // Kept on the phone; cloud copy is retried on the next save.
      }
    }
  }
}
