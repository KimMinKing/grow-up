import 'package:flutter/material.dart';

class AppPalette {
  const AppPalette({
    required this.pine,
    required this.ink,
    required this.paper,
    required this.aqua,
    required this.muted,
    required this.line,
    required this.card,
    required this.subtle,
    required this.mini,
    required this.more,
    required this.max,
    required this.completed,
    required this.selected,
    required this.nav,
    required this.guardian,
    required this.guardianInset,
    required this.guardianText,
  });

  final Color pine;
  final Color ink;
  final Color paper;
  final Color aqua;
  final Color muted;
  final Color line;
  final Color card;
  final Color subtle;
  final Color mini;
  final Color more;
  final Color max;
  final Color completed;
  final Color selected;
  final Color nav;
  final Color guardian;
  final Color guardianInset;
  final Color guardianText;

  static const light = AppPalette(
    pine: Color(0xFF245F9B),
    ink: Color(0xFF1C3049),
    paper: Color(0xFFF1F6FB),
    aqua: Color(0xFF9DD9FF),
    muted: Color(0xFF63788E),
    line: Color(0xFFD3E0EC),
    card: Colors.white,
    subtle: Color(0xFFE9F1F8),
    mini: Color(0xFFEAF4FC),
    more: Color(0xFFE2F0FA),
    max: Color(0xFFD7EAF9),
    completed: Color(0xFFDCEFFB),
    selected: Color(0xFFD1E8F9),
    nav: Colors.white,
    guardian: Color(0xFF1C3049),
    guardianInset: Color(0xFF2B4663),
    guardianText: Color(0xFFD9EBF7),
  );

  static const dark = AppPalette(
    pine: Color(0xFF83C5F5),
    ink: Color(0xFFE8F2FC),
    paper: Color(0xFF0D1724),
    aqua: Color(0xFFA9DEFF),
    muted: Color(0xFFADC0D3),
    line: Color(0xFF34475C),
    card: Color(0xFF19283A),
    subtle: Color(0xFF24374B),
    mini: Color(0xFF203B52),
    more: Color(0xFF24445F),
    max: Color(0xFF2C5070),
    completed: Color(0xFF24516B),
    selected: Color(0xFF315E7A),
    nav: Color(0xFF19283A),
    guardian: Color(0xFF172B40),
    guardianInset: Color(0xFF294766),
    guardianText: Color(0xFFD9EBF7),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
