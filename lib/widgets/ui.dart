import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../data/ops_models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// "₹1,240" with Indian grouping for INR, plain grouping otherwise.
String money(num v, String currency) {
  final sym = AppConfig.currencySymbols[currency] ?? '$currency ';
  final neg = v < 0;
  final whole = v.abs().round();
  final s = whole.toString();
  String grouped;
  if (currency == 'INR' && s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  } else {
    grouped = s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }
  return '${neg ? '-' : ''}$sym$grouped';
}

String qtyText(double q, String unit) {
  final n = q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
  return unit == 'pc' ? '×$n' : '$n $unit';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String hm(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String dmy(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String whenText(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today ${hm(d)}';
  if (diff == -1) return 'Yesterday ${hm(d)}';
  if (diff == 1) return 'Tomorrow ${hm(d)}';
  return '${dmy(d)} ${hm(d)}';
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.small = false});
  final String status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppState>().t;
    final c = LD.statusColors[status] ??
        (status == 'cancelled'
            ? const [Color(0xFFFDE8E8), Color(0xFFB42318)]
            : const [Color(0xFFEDE9FE), Color(0xFF5B3FC4)]); // pickup
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 4),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(99)),
      child: Text(t(status), style: TextStyle(fontSize: small ? 11 : 12, fontWeight: FontWeight.w700, color: c[1])),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.title, this.action, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final String? title;
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: LD.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[
          Row(children: [
            Expanded(child: Text(title!, style: heading(16, weight: FontWeight.w700))),
            if (action != null) action!,
          ]),
          const SizedBox(height: 10),
        ],
        child,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: const Color(0xFFE6EEFC), borderRadius: BorderRadius.circular(22)),
          child: Icon(icon, size: 34, color: LD.primary),
        ),
        const SizedBox(height: 14),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: LD.slate, height: 1.5)),
        if (action != null) ...[const SizedBox(height: 14), action!],
      ]),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.initials, {super.key, this.color = const Color(0xFFE6EEFC), this.size = 40});
  final String initials;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(initials, style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * .34, color: LD.navy)),
      );
}

String initialsOf(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

const avatarColors = [Color(0xFFDDF6F9), Color(0xFFFFF4D6), Color(0xFFE6EEFC), Color(0xFFF9D2E8), Color(0xFFDCF5E8), Color(0xFFEDE9FE)];

Color avatarColor(String id) => avatarColors[id.hashCode.abs() % avatarColors.length];

String roleLabel(Role r, String Function(String) t) => t('role.${r.name}');

IconData roleIcon(Role r) {
  switch (r) {
    case Role.owner:
      return Icons.workspace_premium_outlined;
    case Role.manager:
      return Icons.manage_accounts_outlined;
    case Role.counter:
      return Icons.point_of_sale_outlined;
    case Role.washer:
      return Icons.local_laundry_service_outlined;
    case Role.delivery:
      return Icons.delivery_dining_outlined;
  }
}

// ---------- outside apps ----------

Future<void> openWhatsApp(String phoneDigits, String text, {String dial = '91'}) async {
  var p = phoneDigits.replaceAll(RegExp(r'[^0-9]'), '');
  if (p.length == 10) p = '$dial$p';
  final uri = Uri.parse('https://wa.me/$p?text=${Uri.encodeComponent(text)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> callPhone(String phoneDigits) async {
  await launchUrl(Uri(scheme: 'tel', path: phoneDigits));
}

Future<void> openMaps(String address) async {
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> openUrl(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'OK', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

InputDecoration fieldDeco(String label, {IconData? icon, String? prefix}) => InputDecoration(
      labelText: label,
      prefixText: prefix,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: LD.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: LD.line)),
    );

/// Bottom sheet scaffold with a title.
Future<T?> sheet<T>(BuildContext context, String title, Widget Function(BuildContext) body) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: LD.mist,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: heading(20)),
            const SizedBox(height: 14),
            body(c),
          ]),
        ),
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on ? LD.navy : Colors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: on ? LD.navy : LD.line),
            ),
            child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : LD.navy)),
          ),
        ),
      );
}

/// Simple bar chart (no package): values with labels.
class Bars extends StatelessWidget {
  const Bars({super.key, required this.values, required this.labels, this.height = 120, this.color = LD.primary});
  final List<double> values;
  final List<String> labels;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final mx = values.fold<double>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: height + 22,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Tooltip(
                  message: values[i].toStringAsFixed(0),
                  child: Container(
                    height: mx == 0 ? 2 : (values[i] / mx * height).clamp(2, height).toDouble(),
                    decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 16,
                  child: Text(labels[i], maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 10, color: LD.slate)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Horizontal share bar row: label, bar, value.
class ShareRow extends StatelessWidget {
  const ShareRow({super.key, required this.label, required this.value, required this.max, required this.text, this.color = LD.primary});
  final String label;
  final double value;
  final double max;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : value / max,
                minHeight: 8,
                color: color,
                backgroundColor: const Color(0xFFEDF0F4),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 78, child: Text(text, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        ]),
      );
}
