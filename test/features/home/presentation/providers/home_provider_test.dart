import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/url_parser.dart';
import 'package:mediagrab/features/home/presentation/providers/home_provider.dart';

void main() {
  group('home_provider', () {
    test(
      'initial state has empty url, unknown platform, and isValidUrl false',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(urlInputProvider), '');
        expect(container.read(detectedPlatformProvider), PlatformType.unknown);
        expect(container.read(isValidUrlProvider), isFalse);
      },
    );

    test(
      'detectedPlatformProvider and isValidUrlProvider update when urlInputProvider updates',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(urlInputProvider.notifier).state =
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

        expect(container.read(detectedPlatformProvider), PlatformType.youtube);
        expect(container.read(isValidUrlProvider), isTrue);

        container.read(urlInputProvider.notifier).state =
            'https://www.facebook.com/watch/?v=123';

        expect(container.read(detectedPlatformProvider), PlatformType.facebook);
        expect(container.read(isValidUrlProvider), isTrue);

        container.read(urlInputProvider.notifier).state =
            'https://www.instagram.com/reel/123/';

        expect(
          container.read(detectedPlatformProvider),
          PlatformType.instagram,
        );
        expect(container.read(isValidUrlProvider), isTrue);

        container.read(urlInputProvider.notifier).state = 'https://google.com';

        expect(container.read(detectedPlatformProvider), PlatformType.unknown);
        expect(container.read(isValidUrlProvider), isFalse);
      },
    );

    test('clearUrlInput resets url to empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(urlInputProvider.notifier).state = 'https://youtu.be/123';
      expect(container.read(urlInputProvider), 'https://youtu.be/123');

      // Test clearing through notifier
      container.read(urlInputProvider.notifier).state = '';
      expect(container.read(urlInputProvider), '');
      expect(container.read(isValidUrlProvider), isFalse);
    });
  });
}
