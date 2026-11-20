import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/business_setup_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/shell.dart';
import 'services/auth_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AuthService.instance.init();
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
        builder: (context, s, _) => Stack(children: [
          if (child != null) child,
          if (s.signedIn && s.setupDone && s.locked)
            Positioned.fill(
              child: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const LockScreen())),
            ),
        ]),
      ),
    );
  }
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
