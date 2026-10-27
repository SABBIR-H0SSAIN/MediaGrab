import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/hero_wave_palette.dart';

/// Static vector backdrop. Its child determines height, including in a scroll view.
/// Decorative painting never participates in hit testing or semantics.
class HeroBackground extends StatelessWidget {
  const HeroBackground({super.key, this.child, this.palette});

  final Widget? child;
  final HeroWavePalette? palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors =
        palette ??
        theme.extension<HeroWavePalette>() ??
        HeroWavePalette.themed(theme.colorScheme);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: HeroWavePainter(palette: colors),
                  isComplex: true,
                ),
              ),
            ),
          ),
        ),
        child ?? const SizedBox.expand(),
      ],
    );
  }
}

/// Three asymmetric Bézier surfaces traced from the supplied 1280×719 reference.
/// The composition keeps a bounded height on tall canvases instead of stretching
/// its curves into a portrait sine wave. All geometry and blur radii scale with
/// the canvas. Static painting is isolated in its own RepaintBoundary.
class HeroWavePainter extends CustomPainter {
  const HeroWavePainter({this.palette = HeroWavePalette.reference});
  final HeroWavePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    final bounds = Offset.zero & size;
    final w = size.width;
    final h = math.min(size.height, w * .85);
    final top = size.height - h;
    final art = Rect.fromLTWH(0, top, w, h);
    final strength = palette.intensity;
    Offset at(double x, double y) => Offset(w * x, top + h * y);
    void cubic(
      Path p,
      double x1,
      double y1,
      double x2,
      double y2,
      double x3,
      double y3,
    ) {
      p.cubicTo(
        w * x1,
        top + h * y1,
        w * x2,
        top + h * y2,
        w * x3,
        top + h * y3,
      );
    }

    Path boundary(int layer) {
      final start = at(-.08, .79 + layer * .015);
      final p = Path()..moveTo(start.dx, start.dy);
      switch (layer) {
        case 0:
          cubic(p, .18, .80, .34, .87, .48, .81);
          cubic(p, .70, .75, .89, .46, .925, .13);
          cubic(p, .94, -.03, .96, -.10, 1.08, -.14);
        case 1:
          cubic(p, .23, .84, .49, .95, .77, .77);
          cubic(p, .9, .68, 1.02, .55, 1.08, .45);
        default:
          cubic(p, .23, .89, .54, .91, .78, .84);
          cubic(p, .91, .79, 1.02, .74, 1.08, .69);
      }
      return p;
    }

    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRect(bounds, Paint()..color = palette.base);
    canvas.drawRect(
      art,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.36, .12),
          radius: .64,
          colors: [
            palette.violet.withValues(alpha: .18 * strength),
            palette.darkPurple.withValues(alpha: .1 * strength),
            palette.base.withValues(alpha: 0),
          ],
          stops: const [0, .48, 1],
        ).createShader(art),
    );

    // One blurred light pool; the wave contours themselves remain crisp.
    canvas.drawOval(
      Rect.fromCenter(center: at(.84, .72), width: w * .55, height: h * .34),
      Paint()
        ..color = palette.violet.withValues(alpha: .13 * strength)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.min(w, h) * .075),
    );

    for (var layer = 0; layer < 3; layer++) {
      final edge = boundary(layer);
      final shape =
          Path.from(edge)
            ..lineTo(w * 1.08, top + h * 1.14)
            ..lineTo(-w * .08, top + h * 1.14)
            ..close();
      final gradient = switch (layer) {
        0 => LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [palette.deepNavy, palette.darkPurple, palette.base],
          stops: const [0, .56, 1],
        ),
        1 => LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [palette.darkPurple, palette.deepNavy, palette.base],
          stops: const [0, .68, 1],
        ),
        _ => LinearGradient(
          begin: const Alignment(.6, -.2),
          end: Alignment.bottomCenter,
          colors: [palette.darkPurple, palette.deepNavy, palette.base],
          stops: const [0, .52, 1],
        ),
      };
      canvas.drawPath(
        shape,
        Paint()
          ..shader = gradient.createShader(art)
          ..color = Color.fromRGBO(255, 255, 255, strength),
      );
      // Light is concentrated along the right-hand turn, not painted as a
      // uniform bright stripe. Each lower surface has a quieter light pool.
      final light = RadialGradient(
        center:
            layer == 0 ? const Alignment(.7, .16) : const Alignment(.6, .52),
        radius: layer == 0 ? .72 : .68,
        colors: [
          (layer == 0 ? palette.accent : palette.violet).withValues(
            alpha:
                (layer == 0
                    ? .2
                    : layer == 1
                    ? .14
                    : .06) *
                strength,
          ),
          palette.violet.withValues(
            alpha:
                (layer == 0
                    ? .12
                    : layer == 1
                    ? .08
                    : .03) *
                strength,
          ),
          palette.violet.withValues(alpha: 0),
        ],
        stops: const [0, .35, 1],
      );
      canvas.drawPath(shape, Paint()..shader = light.createShader(art));
      canvas.save();
      canvas.clipPath(shape);
      canvas.drawPath(
        edge,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [
              palette.accent.withValues(alpha: 0),
              palette.violet.withValues(alpha: .08 * strength),
              palette.accent.withValues(
                alpha:
                    (layer == 0
                        ? .55
                        : layer == 1
                        ? .38
                        : .14) *
                    strength,
              ),
              palette.darkPurple.withValues(alpha: .05 * strength),
            ],
            stops: const [0, .35, .66, 1],
          ).createShader(art)
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * (layer == 0 ? .18 : .12)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.min(w, h) * .045,
          ),
      );
      canvas.restore();

      canvas.drawPath(
        edge,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [
              palette.highlight.withValues(alpha: 0),
              palette.highlight.withValues(alpha: .03 * strength),
              palette.accent.withValues(alpha: .28 * strength),
              palette.highlight.withValues(alpha: 0),
            ],
            stops: const [0, .38, .76, 1],
          ).createShader(art)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.min(w, h) * .0014,
      );
    }
    // Let the wave emerge below the header and dissolve before the URL card.
    // Fade to the theme surface rather than exposing the painter's rectangle.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.base,
            palette.base,
            palette.base.withValues(alpha: 0),
            palette.base.withValues(alpha: 0),
            palette.base,
          ],
          stops: const [0, .28, .58, .80, 1],
        ).createShader(bounds),
    );
    // Keep the left side quiet behind the headline; light gathers on the turn.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          colors: [palette.base, palette.base.withValues(alpha: 0)],
          stops: const [0, .65],
        ).createShader(bounds),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HeroWavePainter oldDelegate) =>
      oldDelegate.palette != palette;
}
