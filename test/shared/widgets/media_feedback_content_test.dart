import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/shared/widgets/media_feedback_content.dart';

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'long download feedback stays bounded and ellipsizes at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final title = List.filled(
          150,
          'A long video title\nwith more words',
        ).join(' ');
        await tester.pumpWidget(
          MaterialApp(
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed:
                          () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: MediaFeedbackContent(
                                message: 'Download started · 1080p',
                                title: title,
                              ),
                            ),
                          ),
                      child: const Text('Start'),
                    ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();
        final feedback = find.byType(MediaFeedbackContent);
        expect(tester.getSize(feedback).height, lessThan(180));
        final texts =
            tester
                .widgetList<Text>(
                  find.descendant(of: feedback, matching: find.byType(Text)),
                )
                .toList();
        expect(texts.last.maxLines, 2);
        expect(texts.last.overflow, TextOverflow.ellipsis);
        expect(texts.last.data, isNot(contains('\n')));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: feedback, matching: find.byType(RichText)).last,
        );
        expect(paragraph.didExceedMaxLines, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
