import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Laundry Desk colours (canvas: "Colour palette & type").
class LD {
  LD._();
  static const primary = Color(0xFF1F5FD1);
  static const navy = Color(0xFF0F2340);
  static const aqua = Color(0xFF3CC6D8);
  static const sun = Color(0xFFFFC845);
  static const mist = Color(0xFFF4F8FC);
  static const slate = Color(0xFF5B6B82);
  static const line = Color(0xFFDCE5F0);
  static const field = Color(0xFFF1F4F8);

  // Glossy login
  static const glossBase = Color(0xFFF7F8FF);
  static const pink = Color(0xFFF9D2E8);
  static const sky = Color(0xFFCFE0FF);
  static const lilac = Color(0xFF9B87F5);
  static const softBlue = Color(0xFF6FA8F5);
  static const success = Color(0xFF22A06B);

  // Order status chips: background / text
  static const statusColors = <String, List<Color>>{
    'received': [Color(0xFFE6EEFC), Color(0xFF1F4FB0)],
    'washing': [Color(0xFFDDF6F9), Color(0xFF0B6774)],
    'ready': [Color(0xFFDCF5E8), Color(0xFF146C43)],
    'out': [Color(0xFFFFEBDD), Color(0xFFA8430F)],
    'delivered': [Color(0xFFEDF0F4), Color(0xFF475569)],
    'pending': [Color(0xFFFFF4D6), Color(0xFF8A5A00)],
  };
}

TextStyle heading(double size, {FontWeight weight = FontWeight.w800, Color color = LD.navy}) =>
    GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: LD.primary, primary: LD.primary, surface: Colors.white),
    scaffoldBackgroundColor: LD.mist,
  );
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: LD.navy, displayColor: LD.navy),
    appBarTheme: AppBarTheme(
      backgroundColor: LD.mist,
      foregroundColor: LD.navy,
      elevation: 0,
      titleTextStyle: heading(18, weight: FontWeight.w700),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
