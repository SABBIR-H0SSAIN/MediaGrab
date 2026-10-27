import 'package:flutter/material.dart';

/// Shared app logo, retaining the supplied artwork's original colors.
class MediaGrabMark extends StatelessWidget {
  const MediaGrabMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/icon/app_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    ),
  );
}

class MediaStackArtwork extends StatelessWidget {
  const MediaStackArtwork({
    super.key,
    this.size = 132,
    this.icon = Icons.file_download_rounded,
  });
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size * .82,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: size * .04,
              right: size * .06,
              child: Transform.rotate(
                angle: .13,
                child: Container(
                  width: size * .62,
                  height: size * .48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        c.primaryContainer,
                        Color.lerp(c.primaryContainer, c.surface, .45)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(size * .11),
                    border: Border.all(color: c.primary.withValues(alpha: .18)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: size * .03,
              bottom: size * .02,
              child: Container(
                width: size * .76,
                height: size * .55,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.lerp(
                        c.surfaceContainerHigh,
                        c.primaryContainer,
                        .3,
                      )!,
                      c.surfaceContainerLow,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(size * .1),
                  border: Border.all(
                    color: c.primary.withValues(alpha: .65),
                    width: 1.7,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.primaryContainer.withValues(alpha: .18),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: size * .29, color: c.primary),
                    if (icon == Icons.file_download_rounded)
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: size * .45,
                        height: 3,
                        decoration: BoxDecoration(
                          color: c.primary.withValues(alpha: .22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Familiar platform marks, kept separate from the app's theme colors.
class PlatformLogo extends StatelessWidget {
  const PlatformLogo({super.key, required this.platform, this.size = 25});
  final String platform;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child:
          platform == 'facebook'
              ? Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: size * .78,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.facebook,
                    size: size,
                    color: const Color(0xFF0866FF),
                  ),
                ],
              )
              : CustomPaint(painter: _PlatformPainter(platform)),
    ),
  );
}

class _PlatformPainter extends CustomPainter {
  const _PlatformPainter(this.platform);
  final String platform;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    if (platform == 'youtube') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 5, 32, 22),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFFFF0033),
      );
      canvas.drawPath(
        Path()
          ..moveTo(13, 10)
          ..lineTo(23, 16)
          ..lineTo(13, 22)
          ..close(),
        Paint()..color = Colors.white,
      );
    } else if (platform == 'instagram') {
      final rect = const Rect.fromLTWH(0, 0, 32, 32);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF833AB4), Color(0xFFE1306C), Color(0xFFFCAF45)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ).createShader(rect),
      );
      final outline =
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(6, 6, 20, 20),
          const Radius.circular(6),
        ),
        outline,
      );
      canvas.drawCircle(const Offset(16, 16), 5, outline);
      canvas.drawCircle(
        const Offset(22, 10),
        1.4,
        Paint()..color = Colors.white,
      );
    } else {
      canvas.drawCircle(const Offset(16, 16), 3, Paint()..color = Colors.grey);
    }
  }

  @override
  bool shouldRepaint(_PlatformPainter oldDelegate) =>
      oldDelegate.platform != platform;
}
