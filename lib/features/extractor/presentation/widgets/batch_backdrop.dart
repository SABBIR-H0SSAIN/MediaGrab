import 'package:flutter/material.dart';

/// Quiet, theme-aware decoration with no effect on layout or hit testing.
class BatchBackdrop extends StatelessWidget {
  const BatchBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _BatchBackdropPainter(Theme.of(context).colorScheme),
      child: child,
    ),
  );
}

class _BatchBackdropPainter extends CustomPainter {
  const _BatchBackdropPainter(this.colors);
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final intensity = colors.brightness == Brightness.dark ? 1.0 : .6;
    void wash(Offset center, double radius, Color color, double opacity) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: opacity * intensity),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    wash(
      Offset(size.width * .95, size.height * .14),
      size.width * .85,
      colors.primary,
      .09,
    );
    wash(
      Offset(size.width * -.15, size.height * .9),
      size.width * .9,
      colors.secondary,
      .055,
    );

    // Fine contours stay in the bottom corner, away from the input and cards.
    final contour =
        Paint()
          ..color = colors.primary.withValues(alpha: .065 * intensity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final center = Offset(size.width * 1.06, size.height * .98);
    for (final fraction in [.54, .66, .78]) {
      canvas.drawCircle(center, size.width * fraction, contour);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BatchBackdropPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
