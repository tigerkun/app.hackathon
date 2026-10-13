import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Helper functions for calculating WCAG 2.1 relative luminance and contrast ratios.
class WcagContrast {
  /// Blends a semi-transparent foreground color over an opaque background color.
  static Color composite(Color fg, Color bg) {
    final alpha = fg.opacity;
    if (alpha >= 1.0) return fg;
    final r = (fg.red * alpha + bg.red * (1.0 - alpha)).round().clamp(0, 255);
    final g = (fg.green * alpha + bg.green * (1.0 - alpha)).round().clamp(0, 255);
    final b = (fg.blue * alpha + bg.blue * (1.0 - alpha)).round().clamp(0, 255);
    return Color.fromARGB(255, r, g, b);
  }

  /// Linearizes an 8-bit sRGB channel component according to IEC 61966-2-1 / WCAG 2.1 specs.
  static double linearize(double channel) {
    return channel <= 0.04045
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Calculates the relative luminance of a color according to WCAG 2.1 definition:
  /// L = 0.2126 * R_lin + 0.7152 * G_lin + 0.0722 * B_lin
  static double relativeLuminance(Color color) {
    final r = linearize(color.red / 255.0);
    final g = linearize(color.green / 255.0);
    final b = linearize(color.blue / 255.0);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Calculates the WCAG 2.1 contrast ratio between two colors:
  /// Ratio = (L1 + 0.05) / (L2 + 0.05), where L1 is lighter and L2 is darker.
  /// Automatically composites translucent foreground colors over the background.
  static double contrastRatio(Color foreground, Color background) {
    final effectiveFg = composite(foreground, background);
    final l1 = relativeLuminance(effectiveFg);
    final l2 = relativeLuminance(background);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Returns true if the contrast ratio satisfies WCAG AA for normal body text (>= 4.5:1).
  static bool meetsWcagAaNormal(Color foreground, Color background) {
    return contrastRatio(foreground, background) >= 4.5;
  }

  /// Returns true if the contrast ratio satisfies WCAG AA for large text (>= 3.0:1).
  static bool meetsWcagAaLarge(Color foreground, Color background) {
    return contrastRatio(foreground, background) >= 3.0;
  }
}
