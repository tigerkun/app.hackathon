import 'package:flutter/material.dart';

class AppTheme {
  // 🌑 Backgrounds
  static const Color bgDark = Color(0xFF0B1220);
  static const Color surfaceDark = Color(0xFF101A33);

  // 🎨 Futuristic palette (teal → purple)
  static const Color teal = Color(0xFF2EE6D6);
  static const Color indigo = Color(0xFF6C7CFF);
  static const Color purple = Color(0xFF9B6DFF);

  static const Color red = Color(0xFFFF6B6B);
  static const Color amber = Color(0xFFFFC857);
  static const Color green = Color(0xFF4ADE80);

  // 📝 Text
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;

  static const Color border = Color(0x22FFFFFF);

  // 🧊 Glass card (NO const)
  static BoxDecoration glassCard = BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: border),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        teal.withValues(alpha: 0.12),
        purple.withValues(alpha: 0.08),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.25),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ],
  );

  // 🟦 Solid card
  static BoxDecoration bgCard = BoxDecoration(
    color: surfaceDark.withValues(alpha: 0.9),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: border),
  );

  // 🎨 App-level Dark Theme
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgDark,
    primaryColor: teal,
    colorScheme: const ColorScheme.dark(
      primary: teal,
      secondary: purple,
      error: red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bgDark,
      elevation: 0,
      foregroundColor: Colors.white,
    ),
  );
}
