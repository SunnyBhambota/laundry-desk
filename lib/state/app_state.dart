import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/shop_store.dart';

class AppState extends ChangeNotifier {
  Owner? owner;
  ShopProfile? shop;
  String lang = 'en';
  bool loaded = false;

  bool get signedIn => owner != null;
  bool get setupDone => shop != null;

  String t(String key) => S.of(lang, key);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    lang = p.getString('ld_lang') ?? 'en';
    owner = await AuthService.instance.currentOwner();
    if (owner != null) shop = await ShopStore.instance.load(owner!.uid);
    loaded = true;
    notifyListeners();
  }

  Future<void> setLang(String l) async {
    lang = l;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('ld_lang', l);
  }

  Future<void> signedInAs(Owner o) async {
    owner = o;
    shop = await ShopStore.instance.load(o.uid);
    notifyListeners();
  }

  Future<void> saveShop(ShopProfile s) async {
    if (owner == null) return;
    await ShopStore.instance.save(owner!.uid, s);
    shop = s;
    notifyListeners();
  }

  Future<void> signOut() async {
    await AuthService.instance.signOut();
    owner = null;
    shop = null;
    notifyListeners();
  }
}
