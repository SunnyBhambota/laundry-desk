import 'ops_models.dart';

enum Period { today, week, month, all }

class DateRange {
  DateRange(this.from, this.to);
  final DateTime from;
  final DateTime to;
  bool has(DateTime d) => !d.isBefore(from) && d.isBefore(to);

  static DateRange of(Period p, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final end = today.add(const Duration(days: 1));
    switch (p) {
      case Period.today:
        return DateRange(today, end);
      case Period.week:
        return DateRange(today.subtract(const Duration(days: 6)), end);
      case Period.month:
        return DateRange(DateTime(n.year, n.month, 1), end);
      case Period.all:
        return DateRange(DateTime(2000), end);
    }
  }
}

/// All report numbers for one period (and optionally one branch). Pure; tested.
class Report {
  Report({
    required List<LaundryOrder> orders,
    required List<Expense> expenses,
    required this.range,
    String? branchId,
  }) {
    final inBranch = branchId == null ? orders : orders.where((o) => o.branchId == branchId).toList();
    booked = inBranch.where((o) => range.has(o.createdAt) && o.status != 'cancelled').toList();
    cancelled = inBranch.where((o) => range.has(o.createdAt) && o.status == 'cancelled').length;
    for (final o in inBranch) {
      for (final p in o.payments) {
        if (range.has(p.at)) {
          collected += p.amount;
          byMode[p.mode] = (byMode[p.mode] ?? 0) + p.amount;
          final k = dayKey(p.at);
          daily[k] = (daily[k] ?? 0) + p.amount;
        }
      }
      if (o.status != 'cancelled') pendingDues += o.due;
    }
    sales = booked.fold(0, (s, o) => s + o.total);
    pieces = booked.fold(0, (s, o) => s + o.pieces);
    for (final o in booked) {
      for (final l in o.lines) {
        services[l.service] = (services[l.service] ?? 0) + l.amount;
      }
      customerSpend[o.customerId] = (customerSpend[o.customerId] ?? 0) + o.total;
      branchSales[o.branchId] = (branchSales[o.branchId] ?? 0) + o.total;
    }
    final ex = branchId == null ? expenses : expenses.where((e) => e.branchId == branchId);
    for (final e in ex.where((e) => range.has(e.at))) {
      expense += e.amount;
      expenseByCat[e.category] = (expenseByCat[e.category] ?? 0) + e.amount;
    }
  }

  final DateRange range;
  late final List<LaundryOrder> booked;
  late final int cancelled;
  double sales = 0;
  double collected = 0;
  double pendingDues = 0;
  double expense = 0;
  int pieces = 0;
  final Map<String, double> byMode = {};
  final Map<String, double> daily = {};
  final Map<String, double> services = {};
  final Map<String, double> customerSpend = {};
  final Map<String, double> branchSales = {};
  final Map<String, double> expenseByCat = {};

  int get orderCount => booked.length;
  double get avgOrder => booked.isEmpty ? 0 : sales / booked.length;
  double get profit => collected - expense;

  List<MapEntry<String, double>> top(Map<String, double> m, [int n = 5]) {
    final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return l.take(n).toList();
  }
}

/// Per-staff numbers for a period.
class StaffStats {
  int ordersBooked = 0;
  int statusUpdates = 0;
  int deliveries = 0;
  int pickups = 0;
  double cashCollected = 0;
  int daysPresent = 0;

  static Map<String, StaffStats> build({
    required List<Activity> activity,
    required List<LaundryOrder> orders,
    required List<Attendance> attendance,
    required DateRange range,
  }) {
    final m = <String, StaffStats>{};
    StaffStats of(String id) => m.putIfAbsent(id, StaffStats.new);
    for (final a in activity.where((a) => range.has(a.at))) {
      final s = of(a.by);
      if (a.kind == 'order.new') s.ordersBooked++;
      if (a.kind.startsWith('status.')) s.statusUpdates++;
      if (a.kind == 'delivery.done') s.deliveries++;
      if (a.kind == 'pickup.done') s.pickups++;
    }
    for (final o in orders) {
      for (final p in o.payments.where((p) => range.has(p.at))) {
        of(p.by).cashCollected += p.amount;
      }
      // sample data marks home deliveries through history
      final d = o.timeOf('delivered');
      if (o.homeDelivery && d != null && range.has(d)) {
        final by = o.history.lastWhere((h) => h.status == 'delivered').by;
        final hasLog = activity.any((a) => a.orderId == o.id && a.kind == 'delivery.done');
        if (!hasLog) of(by).deliveries++;
      }
    }
    for (final a in attendance) {
      final d = DateTime.tryParse(a.day);
      if (d != null && range.has(d)) of(a.staffId).daysPresent++;
    }
    return m;
  }
}
