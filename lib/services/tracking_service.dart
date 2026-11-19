import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/ops_models.dart';
import '../data/shop_data.dart';

/// While a delivery person has the app open and is on duty, saves their GPS position
/// every 2 minutes (and at each pickup / delivery as proof). The owner sees the trail
/// on the Delivery board. In cloud mode the points sync with the shop data.
class TrackingService {
  TrackingService._();
  static final TrackingService instance = TrackingService._();

  Timer? _timer;
  StreamSubscription<Position>? _stream;
  DateTime _lastSaved = DateTime(2000);
  String? _staffId;
  ShopData? _data;
  bool denied = false;

  bool get running => _timer != null;

  Future<bool> _allowed() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      denied = p == LocationPermission.denied || p == LocationPermission.deniedForever;
      return !denied;
    } catch (_) {
      return false;
    }
  }

  Future<Ping?> current({String orderId = ''}) async {
    if (!await _allowed()) return null;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      return Ping(lat: pos.latitude, lng: pos.longitude, at: DateTime.now(), orderId: orderId);
    } catch (_) {
      return null;
    }
  }

  Future<void> start(ShopData data, String staffId) async {
    if (_staffId == staffId && running) return;
    stop();
    _data = data;
    _staffId = staffId;
    await _tick();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _tick());
    _background();
  }

  /// Keeps location coming while the phone is locked / app in background.
  /// Android shows a small "Laundry Desk is sharing duty location" notification.
  void _background() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
        intervalDuration: const Duration(minutes: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Laundry Desk · on duty',
          notificationText: 'Sharing your location with the shop while on duty',
          enableWakeLock: true,
        ),
      );
      _stream = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
        final d = _data, id = _staffId;
        if (d == null || id == null) return;
        final a = d.todayAttendance(id);
        if (a == null || a.outAt != null) return;
        if (DateTime.now().difference(_lastSaved).inSeconds < 90) return;
        _lastSaved = DateTime.now();
        d.addPing(id, Ping(lat: pos.latitude, lng: pos.longitude, at: DateTime.now()));
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _tick() async {
    final d = _data, id = _staffId;
    if (d == null || id == null) return;
    final a = d.todayAttendance(id);
    if (a == null || a.outAt != null) return; // only while on duty
    if (DateTime.now().difference(_lastSaved).inSeconds < 90) return;
    final p = await current();
    if (p != null) {
      _lastSaved = DateTime.now();
      d.addPing(id, p);
    }
  }

  /// Location at handover, saved on the order as proof.
  Future<void> proof(ShopData d, LaundryOrder o, String staffId) async {
    final p = await current(orderId: o.id);
    if (p == null) return;
    o.proof = p;
    d.addPing(staffId, p);
    // first handover at a customer's door also pins their address on the map
    d.setCustomerLocation(o.customerId, p.lat, p.lng, onlyIfMissing: true);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _stream?.cancel();
    _stream = null;
    _staffId = null;
    _data = null;
  }
}
