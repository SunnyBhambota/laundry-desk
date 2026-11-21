import 'ops_models.dart';
import 'rate_card.dart';
import 'shop_data.dart';

/// v0.12: outsource tracking, quality check, wallet, damage / loss claims, party (B2B) bills, alteration jobs.
extension ShopV12 on ShopData {
  // ---------- alteration / tailoring ----------
  bool get hasAlteration => garments.any((g) => g.category == 'Alteration');

  /// Adds the tailoring jobs + default rates (does not touch jobs the owner already made).
  void enableAlteration({double currencyFactor = 1}) {
    for (final g in DefaultRates.alterations) {
      if (garments.every((x) => x.id != g.id)) garments.add(Garment.fromJson(g.toJson()));
      rates.putIfAbsent('${g.id}|Alteration', () => ((DefaultRates.altPrice[g.id] ?? 50) * currencyFactor * 100).round() / 100);
    }
    changed();
  }

  // ---------- outsource ----------
  List<LaundryOrder> get outsideOrders => orders.where((o) => o.outsideNow && o.status != 'cancelled').toList()
    ..sort((a, b) => (a.outSentAt ?? a.createdAt).compareTo(b.outSentAt ?? b.createdAt));

  void sendOutside(LaundryOrder o, String to, double cost, {required String by}) {
    o.outTo = to.trim();
    o.outCost = cost;
    o.outSentAt = DateTime.now();
    o.outBackAt = null;
    o.history.add(StatusEvent(status: 'outside', at: DateTime.now(), by: by, note: o.outTo));
    log(by, 'outside.send', orderId: o.id, text: '${o.code} → ${o.outTo}');
    changed();
  }

  void receiveOutside(LaundryOrder o, {required String by}) {
    o.outBackAt = DateTime.now();
    o.history.add(StatusEvent(status: 'outside_back', at: DateTime.now(), by: by, note: o.outTo));
    log(by, 'outside.back', orderId: o.id, text: '${o.code} ← ${o.outTo}');
    changed();
  }

  /// What outside work cost in a month (owner's own expense, shown in reports).
  double outsideCostIn(DateTime from, DateTime to) => orders
      .where((o) => o.outTo.isNotEmpty && o.status != 'cancelled' && o.outSentAt != null && !o.outSentAt!.isBefore(from) && o.outSentAt!.isBefore(to))
      .fold<double>(0, (s, o) => s + o.outCost);

  // ---------- quality check ----------
  void doQc(LaundryOrder o, {required String by, String note = ''}) {
    o.qcAt = DateTime.now();
    o.qcBy = by;
    o.qcNote = note.trim();
    log(by, 'qc', orderId: o.id, text: '${o.code} QC ok${note.isEmpty ? '' : ': $note'}');
    changed();
  }

  void undoQc(LaundryOrder o, {required String by}) {
    o.qcAt = null;
    o.qcBy = '';
    o.qcNote = '';
    log(by, 'qc.undo', orderId: o.id, text: o.code);
    changed();
  }

  // ---------- wallet ----------
  void walletTopUp(Customer c, double amount, {required String by, String mode = 'cash', String note = ''}) {
    if (amount <= 0) return;
    c.wallet += amount;
    c.walletLog.add({'amount': amount, 'note': note.isEmpty ? 'Top-up ($mode)' : note, 'at': DateTime.now().toIso8601String(), 'by': by});
    log(by, 'wallet.topup', text: '${c.name} +${amount.toStringAsFixed(0)}');
    changed();
  }

  /// Pays as much of the order's due as the wallet allows. Returns the amount used.
  double payFromWallet(LaundryOrder o, {required String by}) {
    final c = customer(o.customerId);
    if (c == null || c.wallet <= 0 || o.due <= 0) return 0;
    final amt = c.wallet < o.due ? c.wallet : o.due;
    c.wallet -= amt;
    c.walletLog.add({'amount': -amt, 'note': 'Paid ${o.code}', 'at': DateTime.now().toIso8601String(), 'by': by});
    o.payments.add(Payment(amount: amt, mode: 'wallet', at: DateTime.now(), by: by, note: 'Wallet'));
    log(by, 'wallet.pay', orderId: o.id, text: '${o.code} −${amt.toStringAsFixed(0)}');
    changed();
    return amt;
  }

  double get walletHeld => customers.fold<double>(0, (s, c) => s + c.wallet);

  // ---------- damage / loss claims ----------
  void addClaim(LaundryOrder o, {required String kind, required String piece, required double amount, String note = '', required String by}) {
    o.claims.add({'kind': kind, 'piece': piece.trim(), 'amount': amount, 'note': note.trim(), 'at': DateTime.now().toIso8601String(), 'by': by});
    // The compensation is taken off this order's bill (as far as it is unpaid).
    if (amount > 0 && o.due > 0) o.discount += amount.clamp(0, o.due).toDouble();
    o.history.add(StatusEvent(status: 'claim', at: DateTime.now(), by: by, note: '$kind ${piece.trim()}'));
    log(by, 'claim', orderId: o.id, text: '${o.code} $kind ${piece.trim()} ${amount.toStringAsFixed(0)}');
    changed();
  }

  List<LaundryOrder> get claimOrders => orders.where((o) => o.claims.isNotEmpty).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // ---------- party (B2B / hotel / hospital) bills ----------
  List<Customer> get partyCustomers => customers.where((c) => c.type == 'business').toList();

  double billedIn(String customerId, DateTime from, DateTime to) => orders
      .where((o) => o.customerId == customerId && o.status != 'cancelled' && !o.createdAt.isBefore(from) && o.createdAt.isBefore(to))
      .fold<double>(0, (s, o) => s + o.total);

  // ---------- estimate text ----------
  String estimateText({required String shopName, required String currency, required List<OrderLine> lines, required double subtotal, required double express, required double tax, required double total, required DateTime due}) {
    final b = StringBuffer('*$shopName - Estimate*\n');
    for (final l in lines) {
      b.writeln('${l.garment} (${l.service}) x${l.qty.toStringAsFixed(l.unit == 'kg' ? 1 : 0)} = $currency ${l.amount.toStringAsFixed(0)}');
    }
    if (express > 0) b.writeln('Express: $currency ${express.toStringAsFixed(0)}');
    if (tax > 0) b.writeln('Tax: $currency ${tax.toStringAsFixed(0)}');
    b.writeln('*Total: $currency ${total.toStringAsFixed(0)}*');
    b.writeln('Ready by: ${due.day}/${due.month}');
    b.write('This is an estimate, final bill after checking the clothes.');
    return b.toString();
  }
}
