import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Animated laundry-shop banner (canvas: "Glossy + Runaway Login").
/// Every layer is drawn in the same 390×270 box, then moved/rotated around its own pivot.
class LaundryScene extends StatefulWidget {
  const LaundryScene({super.key, required this.height});

  final double height;

  @override
  State<LaundryScene> createState() => _LaundrySceneState();
}

class _LaundrySceneState extends State<LaundryScene> with SingleTickerProviderStateMixin {
  static const _vw = 390.0, _vh = 270.0;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 60));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.height),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      builder: (context, h, _) => SizedBox(
        height: h,
        child: LayoutBuilder(builder: (context, box) {
          final w = math.min(box.maxWidth, h * _vw / _vh);
          final s = w / _vw;
          return Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: w,
              height: w * _vh / _vw,
              child: Semantics(
                label: 'Laundry shop: clothes drying on a line, a washing machine spinning, '
                    'a smiling woman loading clothes into a dry-cleaning machine',
                image: true,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => _frame(_c.value * 60, w, s),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ---------------- one frame ----------------

  Widget _frame(double t, double w, double s) {
    final h = w * _vh / _vw;
    Widget layer(String body) => SvgPicture.string(_wrap(body), width: w, height: h);

    Widget xf(Widget child, {double deg = 0, Offset pivot = Offset.zero, double scale = 1, Offset move = Offset.zero}) {
      final m = Matrix4.translationValues((pivot.dx + move.dx) * s, (pivot.dy + move.dy) * s, 0)
          .multiplied(Matrix4.rotationZ(deg * math.pi / 180))
          .multiplied(Matrix4.diagonal3Values(scale, scale, 1))
          .multiplied(Matrix4.translationValues(-pivot.dx * s, -pivot.dy * s, 0));
      return Transform(transform: m, child: child);
    }

    double phase(double period, [double delay = 0]) => ((t + delay) % period) / period;
    double ease(double x) => x < .5 ? 2 * x * x : 1 - math.pow(-2 * x + 2, 2).toDouble() / 2;
    double lerp(double a, double b, double x) => a + (b - a) * x;

    // clothes on the line
    final cloths = <Widget>[];
    for (var i = 0; i < _Svg.cloths.length; i++) {
      final c = _Svg.cloths[i];
      final deg = -4 * math.cos(2 * math.pi * (t + c.delay) / 3);
      cloths.add(xf(layer(c.svg), deg: deg, pivot: c.pivot));
    }

    // bubbles and steam
    final rising = <Widget>[];
    for (final b in _Svg.bubbles) {
      final p = phase(3, b.delay);
      final op = p < .15 ? p / .15 : 1 - (p - .15) / .85;
      rising.add(Opacity(opacity: op.clamp(0, 1).toDouble(), child: xf(layer(b.svg), move: Offset(0, -90 * p * p))));
    }
    for (final st in _Svg.steam) {
      final p = phase(2.6, st.delay);
      final y = -50 * (1 - (1 - p) * (1 - p));
      final op = p < .2 ? .9 * p / .2 : .9 * (1 - (p - .2) / .8);
      rising.add(Opacity(
        opacity: op.clamp(0, 1).toDouble(),
        child: xf(layer(st.svg), pivot: st.pivot, scale: lerp(.6, 1.4, p), move: Offset(0, y)),
      ));
    }

    // washing machine: shake + spinning drum
    final sp = 2 * math.pi * t / .32;
    final washer = xf(
      Stack(children: [
        layer(_Svg.washerBody),
        xf(layer(_Svg.washerDrum), deg: (t / 2.6 * 360) % 360, pivot: const Offset(62, 198)),
        layer(_Svg.washerFront),
      ]),
      move: Offset(1.2 * math.sin(sp), .5 * math.sin(sp + math.pi)),
    );

    // dry-clean drum
    final dcDrum = xf(layer(_Svg.dcDrum), deg: -(t / 5 * 360) % 360, pivot: const Offset(277, 198));

    // woman: arm loads a shirt into the dry-clean machine
    final pa = phase(2.8);
    double arm;
    if (pa < .45) {
      arm = lerp(-22, 4, ease(pa / .45));
    } else if (pa < .6) {
      arm = 4;
    } else {
      arm = lerp(4, -22, ease((pa - .6) / .4));
    }
    double clothOp, clothScale;
    Offset clothMove;
    if (pa < .4) {
      clothOp = 1;
      clothScale = 1;
      clothMove = Offset.zero;
    } else if (pa < .58) {
      final x = (pa - .4) / .18;
      clothOp = 1;
      clothScale = lerp(1, .7, x);
      clothMove = Offset(9 * x, 6 * x);
    } else if (pa < .64) {
      final x = (pa - .58) / .06;
      clothOp = 1 - x;
      clothScale = lerp(.7, .4, x);
      clothMove = Offset(lerp(9, 12, x), lerp(6, 8, x));
    } else if (pa < .88) {
      clothOp = 0;
      clothScale = .4;
      clothMove = const Offset(12, 8);
    } else {
      final x = (pa - .88) / .12;
      clothOp = x;
      clothScale = lerp(.4, 1, x);
      clothMove = Offset(lerp(12, 0, x), lerp(8, 0, x));
    }
    final wave = .5 - .5 * math.cos(2 * math.pi * pa);
    final woman = xf(
      Stack(children: [
        xf(layer(_Svg.hair), deg: 2.5 * wave, pivot: const Offset(176, 92)),
        layer(_Svg.womanBody),
        xf(
          Stack(children: [
            layer(_Svg.arm),
            Opacity(
              opacity: clothOp.clamp(0, 1).toDouble(),
              child: xf(layer(_Svg.heldShirt), pivot: const Offset(243, 165), scale: clothScale, move: clothMove),
            ),
          ]),
          deg: arm,
          pivot: const Offset(193, 124),
        ),
      ]),
      move: Offset(0, 1.5 * wave),
    );

    return Stack(children: [
      layer(_Svg.ground),
      ...cloths,
      ...rising,
      washer,
      layer(_Svg.basket),
      layer(_Svg.dcBody),
      dcDrum,
      layer(_Svg.dcFront),
      layer(_Svg.table),
      woman,
    ]);
  }

  static String _wrap(String body) =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 390 270">$body</svg>';
}

class _Part {
  const _Part(this.svg, {this.pivot = Offset.zero, this.delay = 0});
  final String svg;
  final Offset pivot;
  final double delay;
}

/// Drawing parts, same coordinates as the canvas design.
class _Svg {
  static const ground = '''
<ellipse cx="195" cy="252" rx="192" ry="13" fill="#C9D3F5" fill-opacity="0.55"/>
<path d="M4 14 Q195 40 386 14" fill="none" stroke="#8A93A6" stroke-width="1.6"/>
<circle cx="4" cy="14" r="3" fill="#0F2340"/><circle cx="386" cy="14" r="3" fill="#0F2340"/>''';

  static const cloths = <_Part>[
    _Part('''<rect x="34" y="17" width="3" height="7" rx="1" fill="#9B87F5"/>
<path d="M22 26 l8 -3 h10 l8 3 l6 10 l-6 3 l-2 -4 v26 h-20 v-26 l-2 4 l-6 -3 z" fill="#F3A6C8"/>
<path d="M32 23 l3 5 l3 -5" fill="none" stroke="#FFFFFF" stroke-width="1.4"/>''', pivot: Offset(35.5, 17), delay: 0),
    _Part('''<rect x="78" y="22" width="3" height="7" rx="1" fill="#9B87F5"/>
<rect x="66" y="27" width="28" height="40" rx="3" fill="#FFE08A"/>
<path d="M66 58 h28 M66 62 h28" stroke="#FFFFFF" stroke-width="2"/>''', pivot: Offset(79.5, 22), delay: -.7),
    _Part('''<rect x="124" y="26" width="3" height="7" rx="1" fill="#9B87F5"/>
<path d="M110 34 l9 -3 h12 l9 3 l7 9 l-6 4 l-3 -4 v24 h-26 v-24 l-3 4 l-6 -4 z" fill="#6FD3E0"/>''', pivot: Offset(125.5, 26), delay: -1.4),
    _Part('''<rect x="166" y="28" width="3" height="6" rx="1" fill="#9B87F5"/>
<path d="M160 34 h16 l2 6 l8 22 h-36 l8 -22 z" fill="#B9A6F5"/>
<path d="M152 60 q15 4 32 0" fill="none" stroke="#FFFFFF" stroke-width="1.5"/>''', pivot: Offset(167.5, 28), delay: -2),
    _Part('''<rect x="238" y="27" width="3" height="7" rx="1" fill="#9B87F5"/>
<path d="M226 32 h28 l3 52 h-12 l-5 -34 l-5 34 h-12 z" fill="#3D5A9E"/>
<path d="M226 38 h28" stroke="#6E8CCF" stroke-width="1.5"/>''', pivot: Offset(239.5, 27), delay: -.4),
    _Part('''<rect x="290" y="24" width="3" height="7" rx="1" fill="#9B87F5"/>
<path d="M276 30 l9 -3 h12 l9 3 l7 10 l-6 4 l-3 -4 v26 h-26 v-26 l-3 4 l-6 -4 z" fill="#FFFFFF" stroke="#C3CAE0" stroke-width="1.2"/>
<path d="M288 27 l3 5 l3 -5" fill="none" stroke="#9B87F5" stroke-width="1.4"/>''', pivot: Offset(291.5, 24), delay: -1.1),
    _Part('''<rect x="342" y="19" width="3" height="7" rx="1" fill="#9B87F5"/>
<rect x="332" y="24" width="24" height="36" rx="3" fill="#9FC2F7"/>
<path d="M332 52 h24" stroke="#FFFFFF" stroke-width="2"/>''', pivot: Offset(343.5, 19), delay: -1.8),
  ];

  static const bubbles = <_Part>[
    _Part('<circle cx="20" cy="132" r="5" fill="none" stroke="#9B87F5" stroke-width="2"/>', delay: 0),
    _Part('<circle cx="112" cy="140" r="3.5" fill="#3CC6D8"/>', delay: 1.3),
    _Part('<circle cx="92" cy="128" r="6" fill="none" stroke="#6FA8F5" stroke-width="2"/>', delay: 2.2),
  ];

  static const steam = <_Part>[
    _Part('<circle cx="252" cy="116" r="7" fill="#FFFFFF"/>', pivot: Offset(252, 116), delay: 0),
    _Part('<circle cx="276" cy="112" r="9" fill="#FFFFFF"/>', pivot: Offset(276, 112), delay: .9),
    _Part('<circle cx="300" cy="116" r="6" fill="#FFFFFF"/>', pivot: Offset(300, 116), delay: 1.7),
  ];

  static const washerBody = '''
<rect x="12" y="132" width="100" height="116" rx="16" fill="#FFFFFF" stroke="#D5DCF0" stroke-width="2"/>
<rect x="12" y="132" width="100" height="22" rx="11" fill="#EEF1FC"/>
<circle cx="27" cy="143" r="4" fill="#9B87F5"/><circle cx="39" cy="143" r="4" fill="#3CC6D8"/>
<rect x="70" y="139" width="32" height="7" rx="3.5" fill="#D5DCF0"/>
<circle cx="62" cy="198" r="36" fill="#E9ECF8" stroke="#0F2340" stroke-width="3"/>
<circle cx="62" cy="198" r="30" fill="#E6F1FF"/>''';

  static const washerDrum = '''
<defs><clipPath id="wm"><circle cx="62" cy="198" r="30"/></clipPath></defs>
<g clip-path="url(#wm)">
<rect x="42" y="178" width="20" height="13" rx="5" fill="#F3A6C8"/>
<rect x="65" y="204" width="20" height="12" rx="5" fill="#0F2340"/>
<rect x="45" y="204" width="15" height="15" rx="5" fill="#9B87F5"/>
<rect x="67" y="181" width="14" height="14" rx="5" fill="#FFFFFF" stroke="#B5BDD3" stroke-width="1.5"/>
</g>''';

  static const washerFront = '''
<defs><clipPath id="wf"><circle cx="62" cy="198" r="30"/></clipPath></defs>
<path clip-path="url(#wf)" d="M28 205 q9 -7 18 0 t18 0 t18 0 t18 0 t18 0 V240 H28Z" fill="#6FD3E0" fill-opacity="0.75"/>
<path d="M45 182 a22 22 0 0 1 13 -7" fill="none" stroke="#FFFFFF" stroke-width="3.5" stroke-linecap="round"/>''';

  static const basket = '''
<ellipse cx="128" cy="226" rx="11" ry="7" fill="#F3A6C8"/>
<ellipse cx="143" cy="224" rx="10" ry="8" fill="#FFFFFF" stroke="#B5BDD3" stroke-width="1.5"/>
<path d="M116 228 h40 l-5 20 h-30 z" fill="#9B87F5"/>
<path d="M119 236 h34 M121 242 h30" stroke="#D9D0FF" stroke-width="2"/>
<rect x="113" y="224" width="46" height="6" rx="3" fill="#6E5BD8"/>''';

  static const dcBody = '''
<rect x="236" y="122" width="82" height="126" rx="15" fill="#0F2340"/>
<rect x="244" y="130" width="66" height="20" rx="6" fill="#1D3560"/>
<text x="250" y="143.5" font-family="sans-serif" font-size="7.5" font-weight="700" fill="#6FD3E0" letter-spacing="0.8">DRY CLEAN</text>
<circle cx="302" cy="140" r="3" fill="#F3A6C8"/>
<circle cx="277" cy="198" r="32" fill="#E9ECF8" stroke="#6FD3E0" stroke-width="3"/>
<circle cx="277" cy="198" r="26" fill="#1D3560"/>''';

  static const dcDrum = '''
<defs><clipPath id="dc"><circle cx="277" cy="198" r="26"/></clipPath></defs>
<g clip-path="url(#dc)">
<rect x="260" y="182" width="17" height="11" rx="4" fill="#F3A6C8"/>
<rect x="279" y="201" width="17" height="11" rx="4" fill="#FFFFFF"/>
<rect x="262" y="202" width="13" height="13" rx="4" fill="#6FD3E0"/>
</g>''';

  static const dcFront = '''
<path d="M258 182 a22 22 0 0 1 12 -6" fill="none" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="3" stroke-linecap="round"/>''';

  static const table = '''
<rect x="324" y="182" width="62" height="7" rx="3" fill="#B9A6F5"/>
<rect x="329" y="189" width="5" height="59" rx="2" fill="#9B87F5"/>
<rect x="376" y="189" width="5" height="59" rx="2" fill="#9B87F5"/>
<rect x="331" y="222" width="48" height="4" rx="2" fill="#9B87F5"/>
<rect x="333" y="230" width="20" height="16" rx="3" fill="#FFFFFF" stroke="#C3CAE0" stroke-width="1"/>
<rect x="355" y="232" width="20" height="14" rx="3" fill="#F3A6C8"/>
<rect x="328" y="172" width="30" height="10" rx="3" fill="#6FD3E0"/>
<rect x="329" y="162" width="28" height="10" rx="3" fill="#FFFFFF" stroke="#C3CAE0" stroke-width="1"/>
<rect x="330" y="152" width="26" height="10" rx="3" fill="#F3A6C8"/>
<path d="M362 182 h22 q0 -12 -10 -14 h-6 q-6 2 -6 14 z" fill="#0F2340"/>
<path d="M368 168 q0 -6 6 -6 h4" fill="none" stroke="#0F2340" stroke-width="2.5" stroke-linecap="round"/>
<circle cx="376" cy="176" r="1.8" fill="#6FD3E0"/>''';

  static const hair = '''
<path d="M172 92 C166 112 166 140 172 168 C174 176 178 178 180 172 C176 146 177 116 182 96 Z" fill="#2E1F1A"/>''';

  static const womanBody = '''
<path d="M169 196 L203 196 L207 246 L191 246 L186 208 L181 246 L165 246 Z" fill="#DCD3FF"/>
<path d="M166 244 h14 v4 h-14z M190 244 h14 v4 h-14z" fill="#D9607A"/>
<path d="M173 124 C168 140 166 156 168 172" fill="none" stroke="#F6D5BF" stroke-width="5.5" stroke-linecap="round"/>
<path d="M172 121 C172 128 170 136 169 142" fill="none" stroke="#F3A6C8" stroke-width="8" stroke-linecap="round"/>
<path d="M172 120 C176 116 192 116 196 120 L200 160 L206 198 L166 198 L170 160 Z" fill="#F3A6C8"/>
<path d="M167 194 L205 194" stroke="#FFFFFF" stroke-width="2" stroke-opacity="0.8"/>
<path d="M194 119 C190 134 180 150 168 160 L166 154 C176 146 184 134 189 118 Z" fill="#B9A6F5"/>
<path d="M181 108 h8 v12 h-8 z" fill="#F6D5BF"/>
<ellipse cx="184" cy="96" rx="13" ry="14.5" fill="#F6D5BF"/>
<path d="M170 99 C168 85 179 79 189 81 C196 82 199 88 198 93 C193 88 186 87 179 90 C176 92 174 96 173 104 Z" fill="#2E1F1A"/>
<ellipse cx="174" cy="95" rx="6.5" ry="10" fill="#2E1F1A"/>
<path d="M186.5 97 q2.6 2.2 5.2 0" fill="none" stroke="#2E1F1A" stroke-width="1.5" stroke-linecap="round"/>
<path d="M186 92.5 q3 -1.4 6 0" fill="none" stroke="#2E1F1A" stroke-width="1.1" stroke-linecap="round"/>
<circle cx="189" cy="102.5" r="3.2" fill="#F4A6B8" fill-opacity="0.45"/>
<path d="M190.5 105.5 q2.4 1.8 4.8 -0.2" fill="none" stroke="#C2567A" stroke-width="1.5" stroke-linecap="round"/>
<circle cx="177.5" cy="104" r="1.8" fill="#E8B84A"/>''';

  static const arm = '''
<path d="M193 124 L208 146 L234 164" fill="none" stroke="#F6D5BF" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M193 124 L203 139" stroke="#F3A6C8" stroke-width="8" stroke-linecap="round"/>
<path d="M224 157 l2.5 4 M221 159 l2.5 4" stroke="#E8B84A" stroke-width="1.8" stroke-linecap="round"/>''';

  static const heldShirt = '''
<path d="M232 157 l6 -3 h6 l6 3 l4 7 l-4 3 l-2 -3 v14 h-14 v-14 l-2 3 l-4 -3 z" fill="#FFFFFF" stroke="#B5BDD3" stroke-width="1.4"/>''';
}
