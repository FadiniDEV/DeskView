import 'package:flutter/material.dart';

/// Paleta de cores oficial da nova identidade visual Material Design 3 do DeskView.
/// Características principais:
/// - Fundo em tons de cinza-azulado claro.
/// - Áreas de conteúdo contrastantes (branco e cinza-gelo).
/// - Contornos escuros bem definidos (#1E293B).
/// - Verde vibrante como cor de destaque (#10B981 / #00E676).
class AppColors {
  AppColors._();

  // Fundos em tons de cinza-azulado claro
  static const Color scaffoldBackground = Color(0xFFE5ECF4);
  static const Color secondaryBackground = Color(0xFFD9E3F0);
  static const Color sidebarBackground = Color(0xFFEDF2F8);

  // Superfícies de conteúdo contrastantes
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color elevatedSurface = Color(0xFFF8FAFC);
  static const Color inputSurface = Color(0xFFF1F5F9);
  static const Color canvasDarkBackground = Color(0xFF0F172A);

  // Contornos escuros bem definidos
  static const Color darkOutline = Color(0xFF1E293B);
  static const Color subtleOutline = Color(0xFF64748B);
  static const Color hardShadow = Color(0xFF1E293B);

  // Verde vibrante (Cor de Destaque Principal)
  static const Color vibrantGreen = Color(0xFF00D66C);
  static const Color vibrantGreenDark = Color(0xFF059669);
  static const Color vibrantGreenSoft = Color(0xFFD1FAE5);
  static const Color onVibrantGreen = Color(0xFF062819);

  // Cores secundárias e semânticas
  static const Color accentBlue = Color(0xFF2563EB);
  static const Color accentBlueSoft = Color(0xFFDBEAFE);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color warningAmberSoft = Color(0xFFFEF3C7);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color dangerRedSoft = Color(0xFFFEE2E2);

  // Tipografia hierarquizada de alto contraste
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF334155);
  static const Color textMuted = Color(0xFF64748B);
}
