import '../data/ops_models.dart';
import '../widgets/ui.dart' show money, qtyText, whenText;

/// WhatsApp texts sent to customers.
class Messages {
  Messages._();

  static String bill(LaundryOrder o, {required String shopName, required String customerName, required String currency}) {
    final b = StringBuffer()
      ..writeln('*$shopName*')
      ..writeln('Bill ${o.code} · ${customerName.isEmpty ? '' : customerName}')
      ..writeln('');
    for (final l in o.lines) {
      b.writeln('${l.garment} (${l.service}) ${qtyText(l.qty, l.unit)} = ${money(l.amount, currency)}');
    }
    b.writeln('');
    if (o.express) b.writeln('Express: ${money(o.expressCharge, currency)}');
    if (o.discount > 0) b.writeln('Discount: -${money(o.discount, currency)}');
    if (o.couponAmount > 0) b.writeln('Coupon ${o.couponCode}: -${money(o.couponAmount, currency)}');
    if (o.pointsUsed > 0) b.writeln('Loyalty points: -${money(o.pointsUsed, currency)}');
    if (o.packageValue > 0) b.writeln('Package (${o.packageNote}): -${money(o.packageValue, currency)}');
    if (o.tax > 0) b.writeln('GST ${o.taxPct.toStringAsFixed(0)}%: ${money(o.tax, currency)}');
    b
      ..writeln('*Total: ${money(o.total, currency)}*')
      ..writeln('Paid: ${money(o.paid, currency)}')
      ..writeln('Balance: ${money(o.due, currency)}')
      ..writeln('')
      ..writeln('Ready by: ${whenText(o.dueAt)}')
      ..writeln('Pieces: ${o.pieces}')
      ..writeln('')
      ..write('Thank you! – $shopName');
    return b.toString();
  }

  static String statusUpdate(LaundryOrder o, {required String shopName, required String customerName, required String currency}) {
    final hi = customerName.isEmpty ? 'Namaste' : 'Namaste $customerName';
    switch (o.status) {
      case 'pickup':
        return '$hi, your pickup for order ${o.code} is booked. Our delivery person will reach you soon. – $shopName';
      case 'received':
        return '$hi, we have received ${o.pieces} pieces (order ${o.code}). Ready by ${whenText(o.dueAt)}. Total ${money(o.total, currency)}. – $shopName';
      case 'washing':
        return '$hi, your clothes (order ${o.code}) are being cleaned now. – $shopName';
      case 'ready':
        final pay = o.due > 0 ? ' Amount due: ${money(o.due, currency)}.' : '';
        return o.homeDelivery
            ? '$hi, your clothes (order ${o.code}) are ready and will be delivered soon.$pay – $shopName'
            : '$hi, your clothes (order ${o.code}) are ready for pickup.$pay – $shopName';
      case 'out':
        return '$hi, your order ${o.code} is out for delivery.${o.due > 0 ? ' Please keep ${money(o.due, currency)} ready.' : ''} – $shopName';
      case 'delivered':
        return '$hi, order ${o.code} delivered. Thank you for choosing $shopName!';
      default:
        return '$hi, update on order ${o.code}: ${o.status}. – $shopName';
    }
  }

  static String dueReminder({required String customerName, required double due, required String currency, required String shopName}) =>
      'Namaste $customerName, a friendly reminder: ${money(due, currency)} is pending with $shopName. You can pay by cash or UPI on your next visit. Thank you!';
}
