import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Brand ───────────────────────────────────────────────────────────────────
  static const sertecRed  = Color(0xFF8B1E2D);
  static const darkRed    = Color(0xFF6E1723);

  // ── Neutral ─────────────────────────────────────────────────────────────────
  static const neutralGray = Color(0xFF7A7A7A);
  static const lightGray   = Color(0xFFF5F5F5);
  static const bgDark      = Color(0xFF121212);

  // ── Semantic ────────────────────────────────────────────────────────────────
  static const success  = Color(0xFF2E7D32);
  static const warning  = Color(0xFFF57F17);
  static const error    = Color(0xFFB00020);

  // ── Sensor chart ────────────────────────────────────────────────────────────
  static const chartPressure    = sertecRed;
  static const chartTemperature = Color(0xFF6E1723);
}
