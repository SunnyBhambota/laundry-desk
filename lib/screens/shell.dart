import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'more_screen.dart';

/// Bottom navigation: Home, Orders, + New order, Staff, More.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppState>().t;
    final pages = <Widget>[
      const DashboardScreen(),
      ComingSoon(title: t('navOrders'), icon: Icons.receipt_long_rounded),
      ComingSoon(title: t('navNew'), icon: Icons.add_circle_outline_rounded),
      ComingSoon(title: t('navStaff'), icon: Icons.groups_rounded),
      const MoreScreen(),
    ];
    Widget item(int i, IconData icon, String label) {
      final on = _tab == i;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: InkWell(
            onTap: () => setState(() => _tab = i),
            child: SizedBox(
              height: 60,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 24, color: on ? LD.primary : LD.slate),
                const SizedBox(height: 3),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: on ? LD.primary : LD.slate)),
              ]),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: LD.line))),
        child: SafeArea(
          top: false,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            item(0, Icons.home_rounded, t('navHome')),
            item(1, Icons.receipt_long_rounded, t('navOrders')),
            Expanded(
              child: Semantics(
                button: true,
                label: t('navNew'),
                child: InkWell(
                  onTap: () => setState(() => _tab = 2),
                  child: SizedBox(
                    height: 72,
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: LD.primary,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [BoxShadow(color: Color(0x591F5FD1), blurRadius: 16, offset: Offset(0, 6))],
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 3),
                      Text(t('navNew'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                    ]),
                  ),
                ),
              ),
            ),
            item(3, Icons.groups_rounded, t('navStaff')),
            item(4, Icons.more_horiz_rounded, t('navMore')),
          ]),
        ),
      ),
    );
  }
}

class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppState>().t;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: const Color(0xFFE6EEFC), borderRadius: BorderRadius.circular(26)),
              child: Icon(icon, size: 40, color: LD.primary),
            ),
            const SizedBox(height: 16),
            Text(t('comingTitle'), style: heading(20)),
            const SizedBox(height: 8),
            Text(t('comingBody'), textAlign: TextAlign.center, style: const TextStyle(color: LD.slate, height: 1.5)),
          ]),
        ),
      ),
    );
  }
}
