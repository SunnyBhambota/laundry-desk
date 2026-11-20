import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/shop_data.dart';

/// Small photo of a garment (stain / tear / damage) taken at intake.
class GarmentPhoto {
  GarmentPhoto({required this.id, required this.orderId, required this.by, required this.at, required this.bytes, this.note = ''});
  final String id;
  final String orderId;
  final String by;
  final DateTime at;
  final Uint8List bytes;
  final String note;
}

/// Photos are kept out of the normal sync (they are big): saved straight to
/// shops/{owner}/photos and read only when an order is opened. Free: ~60–120 KB each.
class PhotoService {
  PhotoService._();
  static final instance = PhotoService._();
  final _picker = ImagePicker();

  Future<Uint8List?> take({bool camera = true}) async {
    final x = await _picker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 900, maxHeight: 900, imageQuality: 45);
    if (x == null) return null;
    return x.readAsBytes();
  }

  Future<void> add(ShopData d, String orderId, Uint8List bytes, {required String by, String note = ''}) async {
    final id = d.newId('ph');
    final j = {'id': id, 'orderId': orderId, 'by': by, 'at': DateTime.now().toIso8601String(), 'note': note, 'data': base64Encode(bytes)};
    if (d.cloudOn) {
      await FirebaseFirestore.instance.collection('shops').doc(d.ownerUid).collection('photos').doc(id).set(j);
    } else {
      final p = await SharedPreferences.getInstance();
      final l = p.getStringList('ld_photos_$orderId') ?? [];
      l.add(jsonEncode(j));
      await p.setStringList('ld_photos_$orderId', l);
    }
    d.log(by, 'photo', orderId: orderId, text: note);
  }

  Future<List<GarmentPhoto>> list(ShopData d, String orderId) async {
    final out = <GarmentPhoto>[];
    try {
      List<Map<String, dynamic>> raw;
      if (d.cloudOn) {
        final qs = await FirebaseFirestore.instance.collection('shops').doc(d.ownerUid).collection('photos').where('orderId', isEqualTo: orderId).get();
        raw = qs.docs.map((e) => e.data()).toList();
      } else {
        final p = await SharedPreferences.getInstance();
        raw = (p.getStringList('ld_photos_$orderId') ?? []).map((e) => Map<String, dynamic>.from(jsonDecode(e) as Map)).toList();
      }
      for (final j in raw) {
        out.add(GarmentPhoto(
          id: j['id'] as String,
          orderId: orderId,
          by: j['by'] as String? ?? '',
          at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
          bytes: base64Decode(j['data'] as String? ?? ''),
          note: j['note'] as String? ?? '',
        ));
      }
    } catch (_) {}
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> remove(ShopData d, GarmentPhoto ph) async {
    if (d.cloudOn) {
      await FirebaseFirestore.instance.collection('shops').doc(d.ownerUid).collection('photos').doc(ph.id).delete();
    } else {
      final p = await SharedPreferences.getInstance();
      final l = (p.getStringList('ld_photos_${ph.orderId}') ?? []).where((e) => !e.contains('"id":"${ph.id}"')).toList();
      await p.setStringList('ld_photos_${ph.orderId}', l);
    }
  }
}
