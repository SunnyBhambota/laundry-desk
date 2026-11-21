import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'screens/auth_screen.dart';
import 'screens/business_setup_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/shell.dart';
import 'services/auth_service.dart';
import 'services/expiry_service.dart';
import 'state/app_state.dart';
import 'widgets/common.dart';
import 'widgets/ui.dart' show openUrl;
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AuthService.instance.init();
  ExpiryService.instance.check();
  ExpiryService.instance.syncServerTime(); // real time from the web, in the background
  final state = AppState();
  await state.load();
  runApp(ChangeNotifierProvider.value(value: state, child: const LaundryDeskApp()));
}

class LaundryDeskApp extends StatelessWidget {
  const LaundryDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LaundryCase',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AuthGate(),
      // The app lock sits above every screen (also above Settings / order pages that were open).
      builder: (context, child) => Consumer<AppState>(
        builder: (context, s, _) => ColorFiltered(
          colorFilter: s.dark ? const ColorFilter.matrix(darkMatrix) : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
          child: Stack(children: [
          if (child != null)
            _WideFrame(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(MediaQuery.of(context).textScaler.scale(1) * s.textScale)),
                child: child,
              ),
            ),
          if (s.signedIn && s.setupDone && s.locked)
            Positioned.fill(
              // own hero scope: sharing the app's HeroController breaks page "back" after unlocking
              child: HeroControllerScope.none(
                child: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const LockScreen())),
              ),
            ),
          // test build older than 7 days: nothing works until the new version is installed
          ListenableBuilder(
            listenable: ExpiryService.instance,
            builder: (_, __) => ExpiryService.instance.expired ? const Positioned.fill(child: ExpiredScreen()) : const SizedBox.shrink(),
          ),
        ]),
        ),
      ),
    );
  }
}

/// Laptop / big window: the app sits in a rounded "window" on a branded backdrop. Phones are untouched.
class _WideFrame extends StatelessWidget {
  const _WideFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 900) return child;
    final big = w > 1320;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF01245A), Color(0xFF0189D5)]),
      ),
      padding: EdgeInsets.symmetric(vertical: big ? 18 : 0, horizontal: big ? 24 : 0),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: big ? 1400 : double.infinity),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(big ? 22 : 0),
          child: ColoredBox(color: const Color(0xFFF4F8FC), child: child),
        ),
      ),
    );
  }
}

class ExpiredScreen extends StatelessWidget {
  const ExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.update_rounded, size: 72, color: Color(0xFF0189D5)),
              const SizedBox(height: 18),
              const Text('This test version has expired', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF01245A))),
              const SizedBox(height: 8),
              const Text('ये टेस्ट वर्ज़न की तारीख़ ख़त्म हो गई है', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Color(0xFF5B6B82))),
              const SizedBox(height: 16),
              const Text('Test versions work for ${AppConfig.testDays} days. Please install the latest version, or contact ${AppConfig.company}.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF5B6B82))),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => openUrl(kIsWeb ? Uri.base.toString() : AppConfig.latestApkUrl),
                icon: Icon(kIsWeb ? Icons.refresh_rounded : Icons.download_rounded),
                label: Text(kIsWeb ? 'Reload the page' : 'Download latest version'),
              ),
              const SizedBox(height: 14),
              Text('v${AppConfig.version}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            ]),
          ),
        ),
      );
}

/// login / sign up → business setup (one time) → (app lock) → app.
/// The owner's app locks again whenever it goes to the background.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime? _pausedAt;

  /// Locks after 30 s in the background (so WhatsApp / print / share don't lock it at once).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      ExpiryService.instance.check();
      ExpiryService.instance.syncServerTime();
    }
    if (state == AppLifecycleState.resumed && _pausedAt != null) {
      if (DateTime.now().difference(_pausedAt!).inSeconds >= 30) context.read<AppState>().lockNow();
      _pausedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.signedIn) return const AuthScreen();
    if (!s.setupDone) return const BusinessSetupScreen();
    return const Shell();
  }
}
