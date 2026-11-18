import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../logic/messages.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'order_detail_screen.dart';

/// Owner/counter view: pickups and deliveries with the assigned person.
class DeliveryBoardScreen extends StatelessWidget {
  const DeliveryBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final scoped = d.ordersIn(app.scopeBranch);
    final pickups = scoped.where((o) => o.status == 'pickup').toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final deliver = scoped.where((o) => o.homeDelivery && (o.status == 'ready' || o.status == 'out')).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final agents = d.staff.where((s) => s.active && s.role == Role.delivery && (app.scopeBranch == null || s.branchId == app.scopeBranch)).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('delivery')),
          bottom: TabBar(tabs: [Tab(text: '${t('pickups')} · ${pickups.length}'), Tab(text: '${t('toDeliver')} · ${deliver.length}')]),
        ),
        body: Column(children: [
          if (agents.isNotEmpty)
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                children: [
                  for (final s in agents) ...[
                    Container(
                      width: 170,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: LD.line)),
                      child: Row(children: [
                        Avatar(s.initials, color: avatarColor(s.id), size: 34),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(
                              '${scoped.where((o) => o.open && (o.deliveryAgent == s.id || o.pickupAgent == s.id) && (o.status == 'out' || o.status == 'pickup' || o.status == 'ready')).length} · ${d.todayAttendance(s.id) == null ? t('absent') : t('onDuty')}',
                              style: const TextStyle(fontSize: 11, color: LD.slate),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 16, color: LD.slate),
              const SizedBox(width: 6),
              Expanded(child: Text(t('liveSoon'), style: const TextStyle(fontSize: 11, color: LD.slate))),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              _TaskList(orders: pickups, pickup: true),
              _TaskList(orders: deliver, pickup: false),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.orders, required this.pickup});
  final List<LaundryOrder> orders;
  final bool pickup;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppState>().t;
    if (orders.isEmpty) return ListView(children: [EmptyState(icon: Icons.delivery_dining_outlined, text: t('noTasks'))]);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => TaskCard(order: orders[i], pickup: pickup),
    );
  }
}

/// One stop: customer, address, actions. Used by the board and by the delivery person.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.order, required this.pickup});
  final LaundryOrder order;
  final bool pickup;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final c = d.customer(order.customerId);
    final agent = pickup ? order.pickupAgent : order.deliveryAgent;
    final isAgent = app.role == Role.delivery;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: LD.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(order.code, style: heading(15, weight: FontWeight.w700)),
          const SizedBox(width: 8),
          StatusChip(order.status, small: true),
          const Spacer(),
          if (!pickup && order.due > 0)
            Text(t('collect').replaceAll('{a}', money(order.due, cur)),
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5A00))),
        ]),
        const SizedBox(height: 8),
        Text(c?.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
        Text((c?.address ?? '').isEmpty ? '+${c?.phone ?? ''}' : c!.address, style: const TextStyle(color: LD.slate, fontSize: 13)),
        if (!isAgent) ...[
          const SizedBox(height: 4),
          Text('${pickup ? t('pickupBy') : t('deliveryBy')}: ${agent.isEmpty ? t('notAssigned') : d.nameOf(agent)}',
              style: TextStyle(fontSize: 12, color: agent.isEmpty ? const Color(0xFFB42318) : LD.slate, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => callPhone(c?.phone ?? ''), icon: const Icon(Icons.call_outlined, size: 18), label: Text(t('call'))),
          if ((c?.address ?? '').isNotEmpty)
            OutlinedButton.icon(onPressed: () => openMaps(c!.address), icon: const Icon(Icons.navigation_outlined, size: 18), label: Text(t('map'))),
          OutlinedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id))),
            child: Text(t('open2')),
          ),
          if (pickup && order.status == 'pickup')
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: LD.navy),
              onPressed: () => d.setStatus(order, 'received', by: app.actorId),
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: Text(t('pickedUp')),
            ),
          if (!pickup && order.status == 'ready')
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: LD.primary),
              onPressed: () {
                if (order.deliveryAgent.isEmpty && isAgent) d.assign(order, deliveryAgent: app.actorId, by: app.actorId);
                d.setStatus(order, 'out', by: app.actorId);
                if (app.module('whatsapp')) {
                  openWhatsApp(c?.phone ?? '', Messages.statusUpdate(order, shopName: app.shop!.shopName, customerName: c?.name ?? '', currency: cur));
                }
              },
              icon: const Icon(Icons.delivery_dining_outlined, size: 18),
              label: Text(t('out')),
            ),
          if (!pickup && order.status == 'out')
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: LD.success),
              onPressed: () async {
                if (order.due > 0) {
                  final paid = await payDialog(context, order);
                  if (paid == null) return;
                }
                d.setStatus(order, 'delivered', by: app.actorId);
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(t('deliveredBtn')),
            ),
        ]),
      ]),
    );
  }
}

/// Delivery person home: only stops assigned to them.
class MyTasksScreen extends StatelessWidget {
  const MyTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final me = app.actorId;
    final pickups = d.orders.where((o) => o.status == 'pickup' && (o.pickupAgent == me || o.pickupAgent.isEmpty) && o.branchId == app.staffUser?.branchId).toList();
    final drops = d.orders.where((o) => o.homeDelivery && (o.status == 'out' || o.status == 'ready') && (o.deliveryAgent == me)).toList();
    final cur = app.shop!.currency;
    final toCollect = drops.fold<double>(0, (s, o) => s + o.due);

    return Scaffold(
      appBar: AppBar(title: Text(t('myTasks'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        _DutyCard(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _stat(t('pickups'), '${pickups.length}')),
          const SizedBox(width: 8),
          Expanded(child: _stat(t('toDeliver'), '${drops.length}')),
          const SizedBox(width: 8),
          Expanded(child: _stat(t('collect').replaceAll(' {a}', '').replaceAll('{a} ', ''), money(toCollect, cur))),
        ]),
        const SizedBox(height: 14),
        if (pickups.isEmpty && drops.isEmpty) EmptyState(icon: Icons.delivery_dining_outlined, text: t('noTasks')),
        if (pickups.isNotEmpty) ...[
          Text(t('pickups'), style: heading(16, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final o in pickups) ...[TaskCard(order: o, pickup: true), const SizedBox(height: 10)],
        ],
        if (drops.isNotEmpty) ...[
          Text(t('toDeliver'), style: heading(16, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final o in drops) ...[TaskCard(order: o, pickup: false), const SizedBox(height: 10)],
        ],
      ]),
    );
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: LD.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: LD.slate)),
          const SizedBox(height: 4),
          Text(value, style: heading(18)),
        ]),
      );
}

/// Washing / ironing staff: orders to process.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final list = d.orders
        .where((o) => (o.status == 'received' || o.status == 'washing') && o.branchId == (app.staffUser?.branchId ?? o.branchId))
        .toList()
      ..sort((a, b) => (b.express ? 1 : 0).compareTo(a.express ? 1 : 0) != 0
          ? (b.express ? 1 : 0).compareTo(a.express ? 1 : 0)
          : a.dueAt.compareTo(b.dueAt));
    return Scaffold(
      appBar: AppBar(title: Text(t('queue'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        _DutyCard(),
        const SizedBox(height: 12),
        if (list.isEmpty) EmptyState(icon: Icons.local_laundry_service_outlined, text: t('noTasks')),
        for (final o in list) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: o.late ? const Color(0xFFB42318) : LD.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text(o.code, style: heading(15, weight: FontWeight.w700)),
                if (o.express) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.bolt_rounded, color: Color(0xFFE8742A), size: 18)),
                const Spacer(),
                StatusChip(o.status, small: true),
              ]),
              const SizedBox(height: 6),
              for (final l in o.lines)
                Text('• ${l.garment} ${qtyText(l.qty, l.unit)} — ${l.service}${l.note.isEmpty ? '' : '  ⚠ ${l.note}'}', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text('${t('dueBy')} ${whenText(o.dueAt)}', style: TextStyle(fontSize: 12, color: o.late ? const Color(0xFFB42318) : LD.slate)),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: o.status == 'received' ? LD.primary : LD.success, minimumSize: const Size.fromHeight(46)),
                onPressed: () => d.setStatus(o, o.status == 'received' ? 'washing' : 'ready', by: app.actorId),
                child: Text(o.status == 'received' ? t('startWash') : t('markReady')),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }
}

/// Check-in / check-out card for staff.
class _DutyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.staffUser;
    if (s == null) return const SizedBox.shrink();
    final d = app.data!;
    final t = app.t;
    final a = d.todayAttendance(s.id);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: LD.navy, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Avatar(s.initials, color: LD.aqua, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: heading(16, color: Colors.white)),
            Text(
              a == null ? t('absent') : (a.outAt == null ? t('inAt').replaceAll('{t}', hm(a.inAt)) : t('outAt').replaceAll('{t}', hm(a.outAt!))),
              style: const TextStyle(color: Color(0xFFC9D6EA), fontSize: 12),
            ),
          ]),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: LD.sun, foregroundColor: LD.navy),
          onPressed: a == null ? () => d.checkIn(s.id) : (a.outAt == null ? () => d.checkOut(s.id) : null),
          child: Text(a == null ? t('checkIn') : t('checkOut')),
        ),
      ]),
    );
  }
}
