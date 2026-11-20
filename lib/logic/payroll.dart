import '../data/issue_models.dart';
import '../data/ops_models.dart';

/// Default commission / incentive rules (owner edits them in Staff → Commission rules).
const defaultRules = <String, dynamic>{
  'counter.salePct': 2.0, // % of booked sales
  'counter.express': 5.0, // per express order
  'washer.dry': 5.0, // per dry-clean piece
  'washer.wash': 2.0, // per wash piece
  'washer.iron': 1.0, // per steam-iron piece
  'washer.kg': 3.0, // per kg
  'delivery.drop': 20.0, // per delivery
  'delivery.pickup': 15.0, // per pickup
  'delivery.cashPct': 0.5, // % of money collected
  'manager.branchPct': 1.0, // % of branch sales
  'target.sale': 100000.0, // branch monthly sales target
  'target.bonus': 1000.0, // bonus to every staff of that branch
  'bonus.zeroIssue': 500.0, // month without any issue on them
  'penalty.complaint': 50.0,
  'penalty.wrong': 50.0,
  'showEarnings': true,
};

double rule(Map<String, dynamic> rules, String k) => ((rules[k] ?? defaultRules[k]) as num?)?.toDouble() ?? 0;

class PayLine {
  PayLine(this.label, this.calc, this.amount);
  final String label;
  final String calc;
  final double amount;
}

/// One staff member's month: work done and money.
class Payslip {
  Payslip(this.staff, this.month);
  final Staff staff;
  final String month;

  double sales = 0;
  int orders = 0;
  int express = 0;
  int dry = 0, wash = 0, iron = 0;
  double kg = 0;
  int drops = 0, pickups = 0;
  double collected = 0;
  double branchSales = 0;
  int complaints = 0, wrongs = 0;
  int days = 0;
  final List<PayLine> lines = [];
  final List<Payout> payouts = [];

  int get pieces => dry + wash + iron;
  double get incentive => lines.where((l) => l.label != 'Salary' && l.amount > 0).fold(0, (s, l) => s + l.amount);
  double get earned => lines.fold(0, (s, l) => s + l.amount); // salary + incentives − penalties
  double get advances => payouts.where((p) => p.kind == 'advance').fold(0, (s, p) => s + p.amount);
  double get bonusManual => payouts.where((p) => p.kind == 'bonus').fold(0, (s, p) => s + p.amount);
  double get deductions => payouts.where((p) => p.kind == 'deduction').fold(0, (s, p) => s + p.amount);
  double get net => earned + bonusManual - deductions - advances;
  double get paid => payouts.where((p) => p.kind == 'paid').fold(0, (s, p) => s + p.amount);
  double get balance => net - paid;
}

bool _inMonth(DateTime d, String month) => monthKey(d) == month;

Payslip buildPayslip({
  required Staff s,
  required String month,
  required List<LaundryOrder> orders,
  required List<Activity> activity,
  required List<Attendance> attendance,
  required List<Issue> issues,
  required List<Payout> payouts,
  required Map<String, dynamic> rules,
}) {
  final p = Payslip(s, month);
  for (final o in orders) {
    if (o.status == 'cancelled') continue;
    if (o.createdBy == s.id && _inMonth(o.createdAt, month)) {
      p.sales += o.total;
      p.orders++;
      if (o.express) p.express++;
    }
    if (o.branchId == s.branchId && _inMonth(o.createdAt, month)) p.branchSales += o.total;
    for (final h in o.history) {
      if (h.by != s.id || !_inMonth(h.at, month)) continue;
      if (h.status == 'washing') {
        for (final l in o.lines.where((l) => l.worker.isEmpty)) {
          if (l.unit == 'kg') {
            p.kg += l.qty;
          } else if (l.service == 'Dry clean') {
            p.dry += l.pieces;
          } else if (l.service == 'Steam iron') {
            p.iron += l.pieces;
          } else {
            p.wash += l.pieces;
          }
        }
      }
      if (h.status == 'delivered' && o.homeDelivery) p.drops++;
      if (h.status == 'received' && o.timeOf('pickup') != null) p.pickups++;
    }
    for (final pay in o.payments) {
      if (pay.by == s.id && _inMonth(pay.at, month)) p.collected += pay.amount;
    }
    // lines given to this person and finished this month
    for (final l in o.lines) {
      if (l.worker != s.id || l.work != 'done' || l.workAt == null || !_inMonth(l.workAt!, month)) continue;
      if (l.unit == 'kg') {
        p.kg += l.qty;
      } else if (l.service == 'Dry clean') {
        p.dry += l.pieces;
      } else if (l.service == 'Steam iron') {
        p.iron += l.pieces;
      } else {
        p.wash += l.pieces;
      }
    }
  }
  for (final i in issues) {
    if (!_inMonth(i.openedAt, month) || !i.fault.contains(s.id)) continue;
    i.kind == 'wrong' ? p.wrongs++ : p.complaints++;
  }
  p.days = attendance.where((a) => a.staffId == s.id && a.day.startsWith(month)).length;
  p.payouts.addAll(payouts.where((x) => x.staffId == s.id && x.month == month));

  String rs(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  void add(String label, String calc, double amt) {
    if (amt != 0) p.lines.add(PayLine(label, calc, amt));
  }

  p.lines.add(PayLine('Salary', 'Fixed monthly', s.salary));
  switch (s.role) {
    case Role.counter:
      add('Sales commission', '${rs(rule(rules, 'counter.salePct'))}% of ${p.sales.round()}', p.sales * rule(rules, 'counter.salePct') / 100);
      add('Express orders', '${p.express} × ${rs(rule(rules, 'counter.express'))}', p.express * rule(rules, 'counter.express'));
    case Role.washer:
      add('Dry clean pieces', '${p.dry} × ${rs(rule(rules, 'washer.dry'))}', p.dry * rule(rules, 'washer.dry'));
      add('Wash pieces', '${p.wash} × ${rs(rule(rules, 'washer.wash'))}', p.wash * rule(rules, 'washer.wash'));
      add('Steam iron pieces', '${p.iron} × ${rs(rule(rules, 'washer.iron'))}', p.iron * rule(rules, 'washer.iron'));
      add('By weight', '${rs(p.kg)} kg × ${rs(rule(rules, 'washer.kg'))}', p.kg * rule(rules, 'washer.kg'));
    case Role.delivery:
      add('Deliveries', '${p.drops} × ${rs(rule(rules, 'delivery.drop'))}', p.drops * rule(rules, 'delivery.drop'));
      add('Pickups', '${p.pickups} × ${rs(rule(rules, 'delivery.pickup'))}', p.pickups * rule(rules, 'delivery.pickup'));
      add('Money collected', '${rs(rule(rules, 'delivery.cashPct'))}% of ${p.collected.round()}', p.collected * rule(rules, 'delivery.cashPct') / 100);
    case Role.manager:
      add('Branch sales', '${rs(rule(rules, 'manager.branchPct'))}% of ${p.branchSales.round()}', p.branchSales * rule(rules, 'manager.branchPct') / 100);
    case Role.owner:
      break;
  }
  final target = rule(rules, 'target.sale');
  if (target > 0 && p.branchSales >= target) add('Target bonus', 'Branch sales ${p.branchSales.round()} ≥ ${target.round()}', rule(rules, 'target.bonus'));
  final ended = DateTime.now().isAfter(DateTime.parse('$month-01').add(const Duration(days: 27)));
  if (p.complaints + p.wrongs == 0 && ended) add('No-issue bonus', 'No complaint or wrong delivery', rule(rules, 'bonus.zeroIssue'));
  add('Penalty: complaints', '${p.complaints} × ${rs(rule(rules, 'penalty.complaint'))}', -p.complaints * rule(rules, 'penalty.complaint'));
  add('Penalty: wrong delivery', '${p.wrongs} × ${rs(rule(rules, 'penalty.wrong'))}', -p.wrongs * rule(rules, 'penalty.wrong'));
  return p;
}
