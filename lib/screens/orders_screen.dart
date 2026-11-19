import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/ops_models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/branch_switch.dart';
import '../widgets/ui.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.initialFilter = 'open', this.customerId});
  final String initialFilter;
  final String? customerId;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late String _filter = widget.initialFilter;
  String _q = '';

  static const _filters = ['open', 'pickup', 'received', 'washing', 'ready', 'out', 'late', 'delivered', 'all'];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final cur = app.shop!.currency;
    final q = _q.trim().toLowerCase();
    final list = d.ordersIn(app.scopeBranch).where((o) {
      if (widget.customerId != null && o.customerId != widget.customerId) return false;
      switch (_filter) {
        case 'all':
          break;
        case 'open':
          if (!o.open) return false;
          break;
        case 'late':
          if (!o.late) return false;
          break;
        default:
          if (o.status != _filter) return false;
      }
      if (q.isEmpty) return true;
      final c = d.customer(o.customerId);
      return o.code.toLowerCase().contains(q) ||
          '${o.number}' == q ||
          (c?.name.toLowerCase().contains(q) ?? false) ||
          (c?.phone.contains(q) ?? false);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(title: Text(t('orders')), actions: const [BranchSwitch()]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: fieldDeco(t('search'), icon: Icons.search_rounded),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _filters[i];
              final n = d.ordersIn(app.scopeBranch).where((o) => f == 'all'
                  ? true
                  : f == 'open'
                      ? o.open
                      : f == 'late'
                          ? o.late
                          : o.status == f).length;
              return Center(child: Pill(label: '${t(f == 'all' ? 'all' : f)} · $n', on: _filter == f, onTap: () => setState(() => _filter = f)));
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: list.isEmpty
              ? ListView(children: [EmptyState(icon: Icons.receipt_long_rounded, text: t('noOrders'))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => OrderTile(order: list[i], currency: cur),
                ),
        ),
      ]),
    );
  }
}

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, required this.currency});
  final LaundryOrder order;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data!;
    final t = app.t;
    final c = d.customer(order.customerId);
    final multi = d.branches.length > 1;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LD.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(order.code, style: heading(15, weight: FontWeight.w700)),
              if (order.express) ...[
                const SizedBox(width: 6),
                const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFE8742A)),
              ],
              const Spacer(),
              StatusChip(order.status, small: true),
            ]),
            const SizedBox(height: 6),
            Text(c?.name ?? 'Deleted customer', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              '${order.pieces} ${t('pcs')} · ${order.lines.map((l) => l.service).toSet().join(', ')}${multi ? ' · ${d.branch(order.branchId)?.name ?? ''}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: LD.slate),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(order.late ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                  size: 15, color: order.late ? const Color(0xFFB42318) : LD.slate),
              const SizedBox(width: 4),
              Text('${t('dueBy')} ${whenText(order.dueAt)}',
                  style: TextStyle(fontSize: 12, color: order.late ? const Color(0xFFB42318) : LD.slate)),
              const Spacer(),
              Text(money(order.total, currency), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (order.due > 0 && order.status != 'cancelled') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(6)),
                  child: Text('${t('due')} ${money(order.due, currency)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00))),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
