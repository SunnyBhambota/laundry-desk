import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// App logo (owner's design: phone + washing machine), assets/images/logo_mark.png.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/images/logo_mark.png', width: size, height: size, filterQuality: FilterQuality.medium, semanticLabel: 'Laundry Desk');
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 18, this.light = false});
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Laundry', style: heading(size, color: light ? Colors.white : const Color(0xFF0D3F94))),
        TextSpan(
          text: 'Desk',
          style: heading(size, weight: FontWeight.w700, color: light ? const Color(0xFF6FE0F0) : const Color(0xFF14AFCB)),
        ),
      ]),
    );
  }
}

/// The small drum used as the letter "o" in headings.
class DrumO extends StatelessWidget {
  const DrumO({super.key, this.size = 17});
  final double size;

  static const svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
<defs><clipPath id="o"><circle cx="10" cy="10" r="6.6"/></clipPath></defs>
<circle cx="10" cy="10" r="8.3" fill="none" stroke="#0F2340" stroke-width="2.7"/>
<path clip-path="url(#o)" d="M2 11 q2 -2 4 0 t4 0 t4 0 t4 0 V20 H2Z" fill="#3CC6D8"/>
</svg>''';

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: SvgPicture.string(svg, width: size, height: size),
      );
}

/// "Welc<drum>me back!" in English; plain text in Hindi.
class DrumHeading extends StatelessWidget {
  const DrumHeading({super.key, required this.text, this.size = 28});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = heading(size, weight: FontWeight.w700);
    final i = text.indexOf('o');
    final isLatin = RegExp(r'^[A-Za-z !]+$').hasMatch(text);
    if (i < 0 || !isLatin) return Text(text, style: style, textAlign: TextAlign.center);
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: text.substring(0, i)),
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: DrumO(size: size * .6)),
            TextSpan(text: text.substring(i + 1)),
          ]),
          style: style,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class LangToggle extends StatelessWidget {
  const LangToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget pill(String code, String label) {
      final on = s.lang == code;
      return Semantics(
        button: true,
        selected: on,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => s.setLang(code),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: on ? LD.navy : Colors.transparent, borderRadius: BorderRadius.circular(999)),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: on ? Colors.white : LD.navy)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .7),
        border: Border.all(color: Colors.white.withValues(alpha: .95)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [pill('en', 'EN'), pill('hi', 'हिं')]),
    );
  }
}

class BrotrixFooter extends StatelessWidget {
  const BrotrixFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppState>().t;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '${t('designedBy')} '),
        const TextSpan(text: AppConfig.company, style: TextStyle(fontWeight: FontWeight.w700, color: LD.navy)),
      ]),
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(fontSize: 11, letterSpacing: .4, color: LD.slate),
    );
  }
}

/// Soft pink/blue gloss behind the login screens.
class GlossyBackground extends StatelessWidget {
  const GlossyBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: LD.glossBase,
      child: Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: Alignment(-1, 1), radius: 1.1, colors: [LD.pink, Color(0x00F9D2E8)]),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: Alignment(1, 1), radius: 1.1, colors: [LD.sky, Color(0x00CFE0FF)]),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: Alignment(0, -1), radius: .9, colors: [Color(0xFFDCEBFF), Color(0x00DCEBFF)]),
            ),
          ),
        ),
        child,
      ]),
    );
  }
}

/// Frosted input with leading icon and a ✓ when valid.
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.prefixText,
    this.valid = false,
    this.obscure = false,
    this.trailing,
    this.keyboard,
    this.onChanged,
    this.action = TextInputAction.next,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final String? prefixText;
  final bool valid;
  final bool obscure;
  final Widget? trailing;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  final TextInputAction action;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.only(left: 14, right: trailing == null ? 14 : 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: valid ? LD.softBlue : Colors.white.withValues(alpha: .95), width: valid ? 1.5 : 1),
        boxShadow: const [BoxShadow(color: Color(0x147C6FF5), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 19, color: LD.slate), const SizedBox(width: 10)],
        if (prefixText != null) ...[
          Text(prefixText!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboard,
            textInputAction: action,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 15, color: LD.navy),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF6B7790)),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        if (valid)
          Semantics(
            label: 'OK',
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(color: LD.softBlue, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
            ),
          ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.label, required this.icon, required this.onTap});
  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: .95)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            icon,
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
