import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/start_time_label.dart';

void main() {
  // Built in local time so the assertions hold wherever the suite runs — the
  // point under test is "same day as now or not", not any one offset.
  DateTime local(int year, int month, int day, int hour, int minute) =>
      DateTime(year, month, day, hour, minute);

  test('no kickoff, no label', () {
    expect(startTimeLabel(null), isNull);
  });

  test('a fixture today shows the time alone', () {
    final now = local(2026, 8, 17, 9, 0);
    expect(startTimeLabel(local(2026, 8, 17, 16, 30), now: now), '16:30');
  });

  test('midnight today is still just a time, not a date', () {
    final now = local(2026, 8, 17, 9, 0);
    expect(startTimeLabel(local(2026, 8, 17, 0, 0), now: now), '00:00');
  });

  test('a fixture on another day carries its date', () {
    final now = local(2026, 8, 17, 9, 0);
    // The case a bare clock made ambiguous: "00:00" on a card that is
    // actually tomorrow.
    expect(startTimeLabel(local(2026, 8, 18, 0, 0), now: now), '18 Aug 00:00');
  });

  test('a date in another month names that month', () {
    final now = local(2026, 8, 17, 9, 0);
    expect(startTimeLabel(local(2026, 9, 1, 20, 5), now: now), '1 Sep 20:05');
  });

  test('same day-of-month in a different month is not "today"', () {
    final now = local(2026, 8, 17, 9, 0);
    expect(startTimeLabel(local(2026, 7, 17, 12, 0), now: now), '17 Jul 12:00');
  });

  test('same date in a different year is not "today"', () {
    final now = local(2026, 8, 17, 9, 0);
    expect(startTimeLabel(local(2025, 8, 17, 12, 0), now: now), '17 Aug 12:00');
  });

  test('a UTC instant is rendered in the device timezone', () {
    // The bug this fixes: the extension used to format UTC hours itself, so a
    // fixture showed the wrong clock everywhere but UTC.
    final utc = DateTime.utc(2026, 8, 17, 16, 0);
    final expected = utc.toLocal();
    final label = startTimeLabel(utc, now: expected);

    expect(
      label,
      '${expected.hour.toString().padLeft(2, '0')}:'
      '${expected.minute.toString().padLeft(2, '0')}',
    );
  });
}
