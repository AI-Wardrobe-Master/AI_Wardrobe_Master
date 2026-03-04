import 'package:flutter/material.dart';

class AppColors {
  // ---- Light ----
  static const background = Color(0xFFF5F3EE);
  static const surface = Colors.white;
  static const accentYellow = Color(0xFFFBD914);
  static const accentBlue = Color(0xFF0058A3);
  static const textPrimary = Color(0xFF161616);
  static const textSecondary = Color(0xFF5F5F5F);
  static const divider = Color(0xFFE0DED8);

  // ---- Dark ----
  static const darkBackground = Color(0xFF121212);
  static const darkSurface = Color(0xFF1E1E24);
  static const darkAccentBlue = Color(0xFF4DA6FF);
  static const darkTextPrimary = Color(0xFFE8E8E8);
  static const darkTextSecondary = Color(0xFF9E9E9E);
  static const darkDivider = Color(0x1FFFFFFF); // white 12%
}

ThemeData buildLightTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accentBlue,
      background: AppColors.background,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: AppColors.textPrimary,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 0.3,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.accentBlue,
      unselectedItemColor: AppColors.textSecondary,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
    dividerColor: AppColors.divider,
  );
}

ThemeData buildDarkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.darkAccentBlue,
      brightness: Brightness.dark,
      background: AppColors.darkBackground,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: AppColors.darkTextPrimary,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.darkTextPrimary,
        letterSpacing: 0.3,
      ),
    ),
    cardColor: AppColors.darkSurface,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      selectedItemColor: AppColors.accentYellow,
      unselectedItemColor: AppColors.darkTextSecondary,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
    dividerColor: AppColors.darkDivider,
  );
}
