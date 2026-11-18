import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../logic/messages.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'new_order_screen.dart';
import 'orders_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _q = '';
  bool _dueOnly = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final q = _q.toLowerCase();
    final list = d.customers
        .where((c) => (q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.contains(_q)) && (!_dueOnly || d.dueOf(c.id) > 0))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final totalDue = d.customers.fold<double>(0, (s, c) => s + d.dueOf(c.id));

    return Scaffold(
      appBar: AppBar(title: Text(t('customers'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => customerForm(context, app),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(t('addCustomer')),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(decoration: fieldDeco(t('search'), icon: Icons.search_rounded), onChanged: (v) => setState(() => _q = v)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Pill(label: '${t('all')} · ${d.customers.length}', on: !_dueOnly, onTap: () => setState(() => _dueOnly = false)),
            const SizedBox(width: 8),
            Pill(label: '${t('pendingUdhaar')} · ${money(totalDue, cur)}', on: _dueOnly, onTap: () => setState(() => _dueOnly = true)),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? ListView(children: [EmptyState(icon: Icons.people_outline, text: t('noCustomers'))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final due = d.dueOf(c.id);
                    final n = d.orders.where((o) => o.customerId == c.id).length;
                    return Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: LD.line)),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: Avatar(initialsOf(c.name), color: avatarColor(c.id)),
                        title: Row(children: [
                          Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                          if (c.type != 'regular') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(6)),
                              child: Text(t('type.${c.type}'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF5B3FC4))),
                            ),
                          ],
                        ]),
                        subtitle: Text('+${c.phone} · ${t('ordersCount').replaceAll('{n}', '$n')}'),
                        trailing: due > 0
                            ? Text(money(due, cur), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5A00)))
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id))),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final c = d.customer(customerId);
    if (c == null) return Scaffold(appBar: AppBar());
    final cur = app.shop!.currency;
    final orders = d.ordersOf(c.id);
    final spent = orders.where((o) => o.status != 'cancelled').fold<double>(0, (s, o) => s + o.total);
    final due = d.dueOf(c.id);

    Widget stat(String label, String value, [Color? color]) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: LD.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: LD.slate)),
              const SizedBox(height: 4),
              Text(value, style: heading(18, color: color ?? LD.navy)),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [IconButton(tooltip: t('edit'), onPressed: () => customerForm(context, app, edit: c), icon: const Icon(Icons.edit_outlined))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewOrderScreen(customerId: c.id))),
        icon: const Icon(Icons.add_rounded),
        label: Text(t('newOrder')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('+${c.phone}', style: heading(16, weight: FontWeight.w700)),
            if (c.address.isNotEmpty) ...[const SizedBox(height: 4), Text(c.address, style: const TextStyle(color: LD.slate))],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: () => callPhone(c.phone), icon: const Icon(Icons.call_outlined, size: 18), label: Text(t('call'))),
              OutlinedButton.icon(
                onPressed: () => openWhatsApp(c.phone, 'Namaste ${c.name}, '),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('WhatsApp'),
              ),
              if (c.address.isNotEmpty)
                OutlinedButton.icon(onPressed: () => openMaps(c.address), icon: const Icon(Icons.map_outlined, size: 18), label: Text(t('map'))),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          stat(t('orders'), '${orders.length}'),
          const SizedBox(width: 8),
          stat(t('spent'), money(spent, cur)),
          const SizedBox(width: 8),
          stat(t('due'), money(due, cur), due > 0 ? const Color(0xFF8A5A00) : null),
        ]),
        if (due > 0) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => openWhatsApp(
              c.phone,
              Messages.dueReminder(customerName: c.name, due: due, currency: cur, shopName: app.shop!.shopName),
            ),
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(t('remind')),
          ),
        ],
        const SizedBox(height: 14),
        Text(t('orders'), style: heading(16, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final o in orders) ...[OrderTile(order: o, currency: cur), const SizedBox(height: 8)],
        if (orders.isEmpty) EmptyState(icon: Icons.receipt_long_rounded, text: t('noOrders')),
      ]),
    );
  }
}

/// Used by tests and reports.
double customerSpend(List<LaundryOrder> orders) => orders.where((o) => o.status != 'cancelled').fold(0, (s, o) => s + o.total);
