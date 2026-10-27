import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const seedColor = Color(0xFF7C3AED);

  // Modern Purple & Brand Palette
  static const primaryPurple = Color(0xFF7C3AED);
  static const primaryPurpleLight = Color(0xFF8B5CF6);
  static const primaryPurpleDark = Color(0xFF6D28D9);
  static const accentLavender = Color(0xFFA78BFA);

  // Dark & AMOLED Tokens
  static const darkBackground = Color(0xFF0D0C18);
  static const darkSurface = Color(0xFF1B1B23);
  static const darkSurfaceBorder = Color(0xFF292932);
  static const darkSurfaceElevated = Color(0xFF22222C);

  // Light Tokens
  static const lightBackground = Color(0xFFF8F9FD);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceBorder = Color(0xFFE5E7EB);
  static const lightSurfaceElevated = Color(0xFFF1F3F9);

  // Text Tokens
  static const textPrimary = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFF8E8EA8);
  static const textSubtle = Color(0xFF5A5A72);

  static const textLightPrimary = Color(0xFF111827);
  static const textLightMuted = Color(0xFF6B7280);
  static const textLightSubtle = Color(0xFF9CA3AF);

  static const primaryGradient = LinearGradient(
    colors: [primaryPurpleLight, primaryPurpleDark],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Platform brand colors
  static const youtubeRed = Color(0xFFFF0000);
  static const facebookBlue = Color(0xFF1877F2);
  static const instagramPink = Color(0xFFE1306C);
  static const instagramPurple = Color(0xFF833AB4);
  static const instagramOrange = Color(0xFFF77737);
}
