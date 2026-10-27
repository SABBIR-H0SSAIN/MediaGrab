import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/theme/app_theme.dart';

void main() {
  group('AppTheme and getTheme', () {
    test('getTheme returns light theme for Brightness.light', () {
      final theme = getTheme(Brightness.light);
      expect(theme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
    });

    test('getTheme returns dark theme for Brightness.dark', () {
      final theme = getTheme(Brightness.dark);
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, isNot(const Color(0xFF000000)));
    });

    test('AMOLED mode sets pure black scaffold and surface in dark theme', () {
      final amoledTheme = AppTheme.getTheme(Brightness.dark, amoled: true);
      expect(amoledTheme.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(amoledTheme.colorScheme.surface, const Color(0xFF000000));
      expect(
        amoledTheme.colorScheme.surfaceContainerLowest,
        const Color(0xFF000000),
      );
      expect(
        amoledTheme.navigationBarTheme.backgroundColor,
        const Color(0xFF000000),
      );
    });

    test('AMOLED mode does not affect light theme', () {
      final lightTheme = AppTheme.getTheme(Brightness.light, amoled: true);
      expect(lightTheme.brightness, Brightness.light);
      expect(
        lightTheme.scaffoldBackgroundColor,
        isNot(const Color(0xFF000000)),
      );
    });

    test('dynamic accent is applied to navigation and tabs', () {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.green);
      final theme = AppTheme.light(dynamicScheme: scheme);
      expect(theme.tabBarTheme.indicatorColor, scheme.primary);
      expect(
        theme.navigationBarTheme.indicatorColor,
        scheme.secondaryContainer,
      );
      expect(theme.colorScheme.onPrimary, scheme.onPrimary);
      expect(
        theme.filledButtonTheme.style!.minimumSize!.resolve({}),
        const Size(0, 48),
      );
    });

    test('custom seedColor modifies colorScheme', () {
      const customSeed = Color(0xFF00FF00);
      final customTheme = AppTheme.getTheme(
        Brightness.light,
        seedColor: customSeed,
      );
      final defaultTheme = AppTheme.getTheme(Brightness.light);

      expect(
        customTheme.colorScheme.primary,
        isNot(equals(defaultTheme.colorScheme.primary)),
      );
    });
  });
}
