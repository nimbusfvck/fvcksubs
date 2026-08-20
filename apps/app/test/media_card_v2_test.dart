import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/media_card_v2.dart';
import 'package:fvcksubs_app/theme/tokens.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'item',
  );

  testWidgets('video renders without event-specific data', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: VideoItemV2(ref: ref, title: 'Standalone video'),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Standalone video'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('rounds a rating in the card metadata', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: VideoItemV2(ref: ref, title: 'Rated video', rating: 8.76),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.text('★ 8.8'), findsOneWidget);
    final metadata = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == '★ 8.8',
      ),
    );
    TextSpan? star;
    void findStar(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == '★') star = span;
        for (final child in span.children ?? const <InlineSpan>[]) {
          findStar(child);
        }
      }
    }

    findStar(metadata.text);
    expect(star?.style?.color, AppColors.ratingAccent);
  });

  testWidgets('event renders schedule and participants', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: EventItemV2(
                ref: ref,
                title: 'Main event',
                schedule: Schedule(
                  startsAt: DateTime.utc(2026, 8, 20),
                  state: ScheduleState.live,
                  label: 'In progress',
                ),
                participants: const [
                  Participant(name: 'Side A'),
                  Participant(name: 'Side B'),
                ],
              ),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Main event'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
  });
}

void _noop() {}
