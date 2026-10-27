import 'package:flutter/material.dart';

/// Theme tokens for the reference's dark, translucent violet surfaces.
@immutable
class HeroWavePalette extends ThemeExtension<HeroWavePalette> {
  const HeroWavePalette({
    this.base = const Color(0xFF0D0C18),
    this.deepNavy = const Color(0xFF121020),
    this.darkPurple = const Color(0xFF211044),
    this.violet = const Color(0xFF6030C8),
    this.accent = const Color(0xFF7946E8),
    this.highlight = const Color(0xFF9B70FF),
    this.intensity = 1,
  });

  static const reference = HeroWavePalette();
  final Color base, deepNavy, darkPurple, violet, accent, highlight;
  final double intensity;

  factory HeroWavePalette.themed(
    ColorScheme scheme, {
    bool referenceColors = false,
  }) {
    if (referenceColors && scheme.brightness == Brightness.dark) {
      return reference.copyWith(base: scheme.surface);
    }
    return HeroWavePalette(
      base: scheme.surface,
      deepNavy: Color.lerp(scheme.surface, scheme.primaryContainer, .1)!,
      darkPurple: Color.lerp(scheme.surface, scheme.primaryContainer, .45)!,
      violet: Color.lerp(scheme.primaryContainer, scheme.primary, .2)!,
      accent: scheme.primary,
      highlight: Color.lerp(scheme.primary, scheme.onSurface, .25)!,
      intensity: scheme.brightness == Brightness.dark ? .85 : .25,
    );
  }

  @override
  HeroWavePalette copyWith({
    Color? base,
    Color? deepNavy,
    Color? darkPurple,
    Color? violet,
    Color? accent,
    Color? highlight,
    double? intensity,
  }) => HeroWavePalette(
    base: base ?? this.base,
    deepNavy: deepNavy ?? this.deepNavy,
    darkPurple: darkPurple ?? this.darkPurple,
    violet: violet ?? this.violet,
    accent: accent ?? this.accent,
    highlight: highlight ?? this.highlight,
    intensity: intensity ?? this.intensity,
  );

  @override
  HeroWavePalette lerp(covariant HeroWavePalette? other, double t) {
    if (other == null) return this;
    return HeroWavePalette(
      base: Color.lerp(base, other.base, t)!,
      deepNavy: Color.lerp(deepNavy, other.deepNavy, t)!,
      darkPurple: Color.lerp(darkPurple, other.darkPurple, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      intensity: intensity + (other.intensity - intensity) * t,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HeroWavePalette &&
      other.base == base &&
      other.deepNavy == deepNavy &&
      other.darkPurple == darkPurple &&
      other.violet == violet &&
      other.accent == accent &&
      other.highlight == highlight &&
      other.intensity == intensity;

  @override
  int get hashCode => Object.hash(
    base,
    deepNavy,
    darkPurple,
    violet,
    accent,
    highlight,
    intensity,
  );
}
