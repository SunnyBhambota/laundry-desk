import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'delivery_screen.dart';
import 'more_screen.dart';
import 'new_order_screen.dart';
import 'orders_screen.dart';
import 'staff_screen.dart';

class _Tab {
  const _Tab(this.icon, this.label, this.page, {this.center = false});
  final IconData icon;
  final String label;
  final Widget page;
  final bool center;
}

/// Bottom navigation, different per role:
/// owner/manager: Home · Orders · + New order · Staff · More
/// counter: Home · Orders · + New order · Customers · More
/// washer: Queue · Orders · More
/// delivery: My tasks · Orders · More
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  List<_Tab> _tabs(AppState app) {
    final t = app.t;
    switch (app.role) {
      case Role.washer:
        return [
          _Tab(Icons.local_laundry_service_outlined, t('queue'), const QueueScreen()),
          _Tab(Icons.receipt_long_rounded, t('navOrders'), const OrdersScreen()),
          _Tab(Icons.more_horiz_rounded, t('navMore'), const MoreScreen()),
        ];
      case Role.delivery:
        return [
          _Tab(Icons.delivery_dining_outlined, t('myTasks'), const MyTasksScreen()),
          _Tab(Icons.receipt_long_rounded, t('navOrders'), const OrdersScreen()),
          _Tab(Icons.more_horiz_rounded, t('navMore'), const MoreScreen()),
        ];
      case Role.counter:
        return [
          _Tab(Icons.home_rounded, t('navHome'), const DashboardScreen()),
          _Tab(Icons.receipt_long_rounded, t('navOrders'), const OrdersScreen()),
          _Tab(Icons.add_rounded, t('navNew'), const NewOrderScreen(), center: true),
          _Tab(Icons.people_outline, t('customers'), const CustomersScreen()),
          _Tab(Icons.more_horiz_rounded, t('navMore'), const MoreScreen()),
        ];
      case Role.owner:
      case Role.manager:
        return [
          _Tab(Icons.home_rounded, t('navHome'), const DashboardScreen()),
          _Tab(Icons.receipt_long_rounded, t('navOrders'), const OrdersScreen()),
          _Tab(Icons.add_rounded, t('navNew'), const NewOrderScreen(), center: true),
          _Tab(Icons.groups_rounded, t('navStaff'), const StaffScreen()),
          _Tab(Icons.more_horiz_rounded, t('navMore'), const MoreScreen()),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tabs = _tabs(app);
    if (_tab >= tabs.length) _tab = 0;

    Widget item(int i) {
      final tab = tabs[i];
      final on = _tab == i;
      if (tab.center) {
        return Expanded(
          child: Semantics(
            button: true,
            label: tab.label,
            child: InkWell(
              onTap: () => setState(() => _tab = i),
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
                  Text(tab.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                ]),
              ),
            ),
          ),
        );
      }
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: tab.label,
          child: InkWell(
            onTap: () => setState(() => _tab = i),
            child: SizedBox(
              height: 60,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(tab.icon, size: 24, color: on ? LD.primary : LD.slate),
                const SizedBox(height: 3),
                Text(tab.label,
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
      body: IndexedStack(index: _tab, children: [for (final tab in tabs) tab.page]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: LD.line))),
        child: SafeArea(
          top: false,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [for (var i = 0; i < tabs.length; i++) item(i)]),
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
            Icon(icon, size: 48, color: LD.primary),
            const SizedBox(height: 12),
            Text(t('comingTitle'), style: heading(20)),
            const SizedBox(height: 8),
            Text(t('comingBody'), textAlign: TextAlign.center, style: const TextStyle(color: LD.slate)),
          ]),
        ),
      ),
    );
  }
}
