import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'order_detail_screen.dart';

/// Road route + distance/time between two points (OSRM public server, no key).
class RouteInfo {
  RouteInfo(this.points, this.meters, this.seconds, {this.road = true});
  final List<LatLng> points;
  final double meters;
  final double seconds;
  final bool road; // false = straight line (no internet / no route)

  static const _ua = {'User-Agent': 'LaundryCase/0.6 (com.brotrix.laundry)'};

  static Future<RouteInfo> fetch(LatLng a, LatLng b) async {
    try {
      final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
          '${a.longitude},${a.latitude};${b.longitude},${b.latitude}?overview=full&geometries=geojson');
      final r = await http.get(url, headers: _ua).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final routes = j['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final rt = routes.first as Map<String, dynamic>;
          final coords = (rt['geometry']['coordinates'] as List)
              .map((c) => LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          return RouteInfo(coords, (rt['distance'] as num).toDouble(), (rt['duration'] as num).toDouble());
        }
      }
    } catch (_) {}
    final m = const Distance().as(LengthUnit.Meter, a, b);
    return RouteInfo([a, b], m, m / 6.5, road: false); // ~23 km/h city speed
  }

  /// Address → map point (OpenStreetMap Nominatim, no key). Used once per customer.
  static Future<LatLng?> geocode(String address) async {
    if (address.trim().length < 4) return null;
    try {
      final url = Uri.https('nominatim.openstreetmap.org', '/search', {'q': address, 'format': 'json', 'limit': '1', 'countrycodes': 'in'});
      final r = await http.get(url, headers: _ua).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final l = jsonDecode(r.body) as List;
        if (l.isNotEmpty) {
          final m = l.first as Map<String, dynamic>;
          return LatLng(double.parse(m['lat'] as String), double.parse(m['lon'] as String));
        }
      }
    } catch (_) {}
    return null;
  }
}

String kmText(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
String minText(double s) {
  final m = (s / 60).ceil();
  return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
}

/// In-app live map (like food-delivery apps): customer pin, delivery person,
/// road route with distance and time – without leaving the app.
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key, required this.customerId, this.orderId});
  final String customerId;
  final String? orderId;

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final _map = MapController();
  StreamSubscription<Position>? _gps;
  LatLng? _me; // this phone (delivery person)
  LatLng? _dest;
  bool _guessed = false; // destination found from the address text
  RouteInfo? _route;
  LatLng? _routedFrom;
  bool _loading = true;
  bool _follow = true;
  String _note = '';

  bool get _isAgent => context.read<AppState>().role == Role.delivery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _gps?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final app = context.read<AppState>();
    final d = app.data!;
    final c = d.customer(widget.customerId);
    if (c == null) return;
    if (c.hasLocation) {
      _dest = LatLng(c.lat!, c.lng!);
    } else if (c.address.isNotEmpty) {
      _dest = await RouteInfo.geocode(c.address);
      _guessed = _dest != null;
    }
    if (_isAgent) {
      await _startGps();
    }
    await _reroute(force: true);
    if (mounted) setState(() => _loading = false);
    _fit();
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _note = L(context.read<AppState>(), 'Turn on phone location (GPS).', 'फ़ोन की लोकेशन (GPS) चालू करें।');
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        _note = L(context.read<AppState>(), 'Allow location for LaundryCase.', 'LaundryCase को लोकेशन की इजाज़त दें।');
        return;
      }
      final now = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 12));
      _me = LatLng(now.latitude, now.longitude);
      _gps = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15)).listen((pos) {
        if (!mounted) return;
        setState(() => _me = LatLng(pos.latitude, pos.longitude));
        if (_follow) _map.move(_me!, _map.camera.zoom);
        _reroute();
      });
    } catch (_) {}
  }

  /// Start of the route: this phone for the delivery person, else the agent's last location.
  LatLng? _from([AppState? a]) {
    if (_me != null) return _me;
    final app = a ?? context.read<AppState>();
    final d = app.data!;
    final o = widget.orderId == null ? null : d.order(widget.orderId!);
    final agent = o == null ? '' : (o.status == 'pickup' ? o.pickupAgent : o.deliveryAgent);
    final p = agent.isEmpty ? null : d.lastPing(agent);
    return p == null ? null : LatLng(p.lat, p.lng);
  }

  Future<void> _reroute({bool force = false}) async {
    final a = _from(), b = _dest;
    if (a == null || b == null) return;
    // new route only after moving 150 m (saves data, keeps the free server happy)
    if (!force && _routedFrom != null && const Distance().as(LengthUnit.Meter, a, _routedFrom!) < 150) return;
    _routedFrom = a;
    final r = await RouteInfo.fetch(a, b);
    if (mounted) setState(() => _route = r);
  }

  void _fit() {
    final pts = [if (_from() != null) _from()!, if (_dest != null) _dest!];
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _map.move(pts.first, 15);
      } else {
        _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.fromLTRB(50, 80, 50, 260)));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isAgent = app.role == Role.delivery;
    final d = app.data!;
    final c = d.customer(widget.customerId);
    final o = widget.orderId == null ? null : d.order(widget.orderId!);
    final cur = app.shop!.currency;
    final from = _from(app);
    final agentId = o == null ? '' : (o.status == 'pickup' ? o.pickupAgent : o.deliveryAgent);
    final agentPing = agentId.isEmpty ? null : d.lastPing(agentId);
    // owner/counter: follow the agent's new pings as they sync in
    if (!isAgent && from != null && _routedFrom != null && const Distance().as(LengthUnit.Meter, from, _routedFrom!) >= 150) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reroute());
    }
    if (c == null) return const Scaffold(body: Center(child: Text('—')));

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _dest ?? from ?? const LatLng(19.076, 72.8777),
            initialZoom: 14,
            onPositionChanged: (_, byUser) {
              if (byUser && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.brotrix.laundry'),
            if (_route != null)
              PolylineLayer(polylines: [
                Polyline(points: _route!.points, strokeWidth: 7, color: Colors.white),
                Polyline(points: _route!.points, strokeWidth: 4.5, color: LD.primary, pattern: _route!.road ? const StrokePattern.solid() : StrokePattern.dashed(segments: const [10, 8])),
              ]),
            MarkerLayer(markers: [
              if (_dest != null)
                Marker(
                  point: _dest!,
                  width: 46,
                  height: 56,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on, size: 52, color: Color(0xFFE8742A), shadows: [Shadow(blurRadius: 6, color: Colors.black26)]),
                ),
              if (from != null)
                Marker(
                  point: from,
                  width: 44,
                  height: 44,
                  child: Container(
                    decoration: BoxDecoration(
                      color: LD.navy,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: const Icon(Icons.delivery_dining, color: Colors.white, size: 22),
                  ),
                ),
            ]),
            const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors'), TextSourceAttribution('OSRM')]),
          ],
        ),
        // top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _round(Icons.arrow_back, () => Navigator.pop(context)),
              const Spacer(),
              _round(Icons.center_focus_strong_outlined, () {
                setState(() => _follow = true);
                _fit();
              }),
            ]),
          ),
        ),
        // bottom card
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_loading)
                  const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(minHeight: 3))
                else if (_route != null)
                  Row(children: [
                    Text(minText(_route!.seconds), style: heading(24, color: LD.success)),
                    const SizedBox(width: 10),
                    Text('· ${kmText(_route!.meters)}', style: heading(16, weight: FontWeight.w600, color: LD.slate)),
                    const Spacer(),
                    if (!_route!.road) Text(L(app, 'straight line', 'सीधी दूरी'), style: const TextStyle(fontSize: 11, color: LD.slate)),
                  ]),
                if (_note.isNotEmpty) Text(_note, style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w600)),
                if (!isAgent && agentId.isNotEmpty)
                  Text(
                      agentPing == null
                          ? '${d.nameOf(agentId)}: ${L(app, 'location not shared yet', 'लोकेशन अभी नहीं मिली')}'
                          : '${d.nameOf(agentId)} · ${L(app, 'updated', 'अपडेट')} ${hm(agentPing.at)}',
                      style: const TextStyle(fontSize: 12, color: LD.slate, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(c.name, style: heading(17, weight: FontWeight.w700)),
                Text(c.address.isEmpty ? '+${c.phone}' : c.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: LD.slate)),
                if (_dest == null)
                  Text(L(app, 'No map pin for this customer yet. At the door, tap "Save pin here".', 'इस ग्राहक का पिन नहीं है। दरवाज़े पर "यहाँ पिन सेव करें" दबाएँ।'),
                      style: const TextStyle(color: Color(0xFF8A5A00), fontSize: 12, fontWeight: FontWeight.w600))
                else if (_guessed)
                  Text(L(app, 'Pin found from the address – save the exact pin at the door.', 'पिन पते से ढूँढा है – दरवाज़े पर सही पिन सेव करें।'),
                      style: const TextStyle(color: Color(0xFF8A5A00), fontSize: 12)),
                if (o != null && o.due > 0 && o.status != 'pickup')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${L(app, 'Collect', 'लेना है')} ${money(o.due, cur)}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5A00))),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () => callPhone(c.phone), icon: const Icon(Icons.call_outlined, size: 18), label: Text(app.t('call')))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => openWhatsApp(c.phone, ''), icon: const Icon(Icons.chat_outlined, size: 18), label: const Text('WhatsApp')),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  if (isAgent)
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _me == null
                            ? null
                            : () {
                                d.setCustomerLocation(c.id, _me!.latitude, _me!.longitude);
                                setState(() {
                                  _dest = _me;
                                  _guessed = false;
                                });
                                toast(context, L(app, 'Customer pin saved.', 'ग्राहक का पिन सेव हो गया।'));
                              },
                        icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                        label: Text(L(app, 'Save pin here', 'यहाँ पिन सेव करें')),
                      ),
                    ),
                  if (isAgent) const SizedBox(width: 8),
                  if (o != null)
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: LD.navy),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id))),
                        child: Text('${app.t('open2')} ${o.code}'),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _round(IconData i, VoidCallback onTap) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(10), child: Icon(i, color: LD.navy))),
      );
}
