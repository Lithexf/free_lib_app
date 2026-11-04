import 'package:flutter/material.dart';

/// Egyszerű, letisztult sötét színpaletta az alkalmazáshoz.
class AppColors {
  AppColors._();

  // Alap felületek (sötét téma)
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceLight = Color(0xFF2A2A2A);
  static const Color surfaceBorder = Color(0xFF333333);

  // Kiemelő színek
  static const Color primary = Color(0xFF64B5F6); // Egyszerű világoskék
  static const Color secondary = Color(0xFF90CAF9);
  static const Color accent = Color(0xFF4DB6AC); // Visszafogott türkiz

  // Szövegszínek
  static const Color textPrimary = Color(0xFFEEEEEE);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textMuted = Color(0xFF757575);

  // Állapotjelző színek
  static const Color error = Color(0xFFEF5350);
  static const Color success = Color(0xFF66BB6A);
}
