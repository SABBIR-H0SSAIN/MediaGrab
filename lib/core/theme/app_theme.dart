import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'hero_wave_palette.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light({ColorScheme? dynamicScheme, Color? seedColor}) =>
      _build(
        Brightness.light,
        dynamicScheme: dynamicScheme,
        seedColor: seedColor,
      );

  static ThemeData dark({
    ColorScheme? dynamicScheme,
    bool amoled = false,
    Color? seedColor,
  }) => _build(
    Brightness.dark,
    dynamicScheme: dynamicScheme,
    seedColor: seedColor,
    amoled: amoled,
  );

  static ThemeData _build(
    Brightness brightness, {
    ColorScheme? dynamicScheme,
    Color? seedColor,
    bool amoled = false,
  }) {
    final dark = brightness == Brightness.dark;
    var scheme =
        dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor ?? AppColors.seedColor,
          brightness: brightness,
        );
    if (dynamicScheme == null && seedColor == null && dark) {
      scheme = scheme.copyWith(
        primary: const Color(0xFFB99AF5),
        primaryContainer: const Color(0xFF6134B2),
        onPrimary: const Color(0xFF211135),
        onPrimaryContainer: const Color(0xFFF5EEFF),
        secondaryContainer: const Color(0xFF503084),
        onSecondaryContainer: const Color(0xFFE9D9FF),
        onSurface: const Color(0xFFF3F2F7),
        onSurfaceVariant: const Color(0xFFB9B8C5),
        outlineVariant: AppColors.darkSurfaceBorder,
      );
    }
    if (dark) {
      scheme = scheme.copyWith(
        surface: amoled ? Colors.black : AppColors.darkBackground,
        surfaceContainerLowest:
            amoled ? Colors.black : AppColors.darkBackground,
        surfaceContainerLow:
            amoled ? const Color(0xFF0C0C14) : AppColors.darkSurface,
        surfaceContainer: AppColors.darkSurface,
        surfaceContainerHigh: AppColors.darkSurfaceElevated,
        surfaceContainerHighest: const Color(0xFF2D2D38),
      );
    }
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: scheme,
      extensions: [
        HeroWavePalette.themed(
          scheme,
          referenceColors: dynamicScheme == null && seedColor == null,
        ),
      ],
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color:
                states.contains(WidgetState.selected)
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight:
                states.contains(WidgetState.selected)
                    ? FontWeight.w600
                    : FontWeight.w400,
            color:
                states.contains(WidgetState.selected)
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
          ),
        ),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        horizontalTitleGap: 14,
        minLeadingWidth: 24,
        minVerticalPadding: 10,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData getTheme(
    Brightness brightness, {
    bool amoled = false,
    Color? seedColor,
    ColorScheme? dynamicScheme,
  }) => _build(
    brightness,
    amoled: amoled,
    seedColor: seedColor,
    dynamicScheme: dynamicScheme,
  );
}

ThemeData getTheme(
  Brightness brightness, {
  bool amoled = false,
  Color? seedColor,
  ColorScheme? dynamicScheme,
}) => AppTheme.getTheme(
  brightness,
  amoled: amoled,
  seedColor: seedColor,
  dynamicScheme: dynamicScheme,
);
