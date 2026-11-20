import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Phone notifications made by the app itself (free, no server):
/// shown while the app is open or in the background.
class NotifyService {
  NotifyService._();
  static final instance = NotifyService._();
  final _p = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 1;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _p.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {}
  }

  Future<void> show(String title, String body) async {
    if (!_ready) return;
    try {
      await _p.show(
        _id++,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails('ld_main', 'LaundryCase', channelDescription: 'Requests, complaints, work and notices',
              importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (_) {}
  }
}
