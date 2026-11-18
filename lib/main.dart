import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/business_setup_screen.dart';
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
      title: 'Laundry Desk',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AuthGate(),
    );
  }
}

/// login / sign up → business setup (one time) → app
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.signedIn) return const AuthScreen();
    if (!s.setupDone) return const BusinessSetupScreen();
    return const Shell();
  }
}
