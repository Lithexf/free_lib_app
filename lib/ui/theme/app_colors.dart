import 'package:flutter/material.dart';

/// FreeLib curated color palette — premium dark theme
class AppColors {
  AppColors._();

  // ── Base surfaces ──
  static const Color background = Color(0xFF0F1123);
  static const Color surface = Color(0xFF1A1D36);
  static const Color surfaceLight = Color(0xFF252842);
  static const Color surfaceBorder = Color(0xFF2E3154);

  // ── Brand accents ──
  static const Color primary = Color(0xFFE8A838);
  static const Color primaryLight = Color(0xFFF2C56B);
  static const Color secondary = Color(0xFF6C63FF);
  static const Color secondaryLight = Color(0xFF8B84FF);
  static const Color accent = Color(0xFF00D9A6);
  static const Color accentLight = Color(0xFF33E4BD);

  // ── Text ──
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF9598B0);
  static const Color textMuted = Color(0xFF6B6E85);

  // ── Status colors (reading statuses) ──
  static const Color statusPlanToRead = Color(0xFF5B8DEF);
  static const Color statusReading = Color(0xFF00D9A6);
  static const Color statusCompleted = Color(0xFFE8A838);
  static const Color statusOnHold = Color(0xFFFF9F43);
  static const Color statusDropped = Color(0xFFFF6B6B);
  static const Color statusRereading = Color(0xFFAB7AFF);

  // ── Utility ──
  static const Color error = Color(0xFFFF6B6B);
  static const Color success = Color(0xFF00D9A6);
  static const Color shimmerBase = Color(0xFF1A1D36);
  static const Color shimmerHighlight = Color(0xFF252842);

  // ── Glass effect ──
  static const Color glassBackground = Color(0x1AFFFFFF); // 10% white
  static const Color glassBorder = Color(0x33FFFFFF); // 20% white
}
