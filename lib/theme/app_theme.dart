import 'package:flutter/material.dart';

/// Premium Editorial Color Palette & Theme Configuration for PYP
class AppColors {
  static const Color obsidian = Color(0xFF080808);
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkSurfaceVariant = Color(0xFF1E1E20);
  static const Color warmIvory = Color(0xFFF1F0EB);
  static const Color warmIvoryDark = Color(0xFFDCD8CF);
  static const Color mutedSilver = Color(0xFFB8B4AA);
  static const Color champagneGold = Color(0xFFC6A76A);
  static const Color champagneGoldDark = Color(0xFFA8894D);
  static const Color borderDark = Color(0xFF2B2824);
  static const Color borderLight = Color(0xFFE2DFD8);

  // Status colors
  static const Color statusRequested = Color(0xFFD97706); // Amber
  static const Color statusAccepted = Color(0xFF2563EB); // Royal Blue
  static const Color statusAwaitingPayment = Color(0xFF0284C7); // Sky Blue
  static const Color statusConfirmed = Color(0xFF059669); // Emerald Green
  static const Color statusCompleted = Color(0xFF10B981); // Bright Emerald
  static const Color statusCancelled = Color(0xFFDC2626); // Crimson Red
  static const Color statusRejected = Color(0xFF991B1B); // Dark Red
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.obsidian,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.champagneGold,
        onPrimary: AppColors.obsidian,
        secondary: AppColors.warmIvory,
        onSecondary: AppColors.obsidian,
        surface: AppColors.darkSurface,
        onSurface: AppColors.warmIvory,
        surfaceContainerHighest: AppColors.darkSurfaceVariant,
        outline: AppColors.borderDark,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.warmIvory,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.warmIvory,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderDark, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceVariant,
        labelStyle: const TextStyle(color: AppColors.mutedSilver, fontSize: 14),
        hintStyle: const TextStyle(color: AppColors.mutedSilver, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.champagneGold,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.statusCancelled),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.champagneGold,
          foregroundColor: AppColors.obsidian,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.warmIvory,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: AppColors.borderDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.champagneGold,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.obsidian,
        selectedItemColor: AppColors.champagneGold,
        unselectedItemColor: AppColors.mutedSilver,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 12),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.obsidian,
        selectedIconTheme: IconThemeData(color: AppColors.champagneGold),
        unselectedIconTheme: IconThemeData(color: AppColors.mutedSilver),
        selectedLabelTextStyle: TextStyle(
          color: AppColors.champagneGold,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelTextStyle: TextStyle(color: AppColors.mutedSilver),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurfaceVariant,
        selectedColor: AppColors.champagneGold,
        secondarySelectedColor: AppColors.champagneGold,
        labelStyle: const TextStyle(color: AppColors.warmIvory, fontSize: 13),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.obsidian,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
        side: const BorderSide(color: AppColors.borderDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderDark),
        ),
      ),
    );
  }
}
