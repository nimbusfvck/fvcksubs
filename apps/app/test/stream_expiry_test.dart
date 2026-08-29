import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/stream_expiry.dart';

void main() {
  group('streamExpiry', () {
    test('reads Tencent Cloud Live txTime as hexadecimal Unix seconds', () {
      // The real Cricfy "Cricfy Live" link shape. 0x6A92CE93 = 1788006035 =
      // 2026-08-29T12:20:35Z, the instant that source starts answering 403.
      final expiry = streamExpiry(
        'https://live.vivo200.com/live/hd-en-1-4558499.m3u8'
        '?txSecret=ffa52f0dccaae0642dc247b94bd40a55&txTime=6A92CE93',
      );
      expect(expiry, DateTime.utc(2026, 8, 29, 12, 20, 35));
    });

    test('reads a decimal exp parameter', () {
      expect(
        streamExpiry('https://a15.kora-plus.li/live/x.m3u8?token=a&exp=1786814302'),
        DateTime.fromMillisecondsSinceEpoch(1786814302 * 1000, isUtc: true),
      );
    });

    test('combines AWS SigV4 lifetime with its issue time', () {
      final expiry = streamExpiry(
        'https://bucket.r2.cloudflarestorage.com/seg_1581.txt'
        '?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20260829T131034Z'
        '&X-Amz-Expires=300&X-Amz-Signature=abc',
      );
      expect(expiry, DateTime.utc(2026, 8, 29, 13, 15, 34));
    });

    test('a SigV4 lifetime with no issue date yields no deadline', () {
      expect(
        streamExpiry('https://cdn.tld/a.m3u8?X-Amz-Expires=300'),
        isNull,
      );
    });

    test('ignores a small integer sharing an expiry parameter name', () {
      expect(streamExpiry('https://cdn.tld/a.m3u8?e=2'), isNull);
    });

    test('an unsigned url carries no deadline', () {
      expect(
        streamExpiry(
          'https://live.kinescopecdn.net/on-air/abc/def/master.m3u8',
        ),
        isNull,
      );
    });

    test('a query-less url carries no deadline', () {
      expect(streamExpiry('https://cdn.tld/live.m3u8'), isNull);
    });

    test('a malformed url is not a deadline', () {
      expect(streamExpiry('::::'), isNull);
    });
  });

  group('streamTimeToExpiry', () {
    test('measures the remaining window from now', () {
      final remaining = streamTimeToExpiry(
        'https://cdn.tld/a.m3u8?exp=1788006035',
        now: DateTime.fromMillisecondsSinceEpoch(1788005735 * 1000, isUtc: true),
      );
      expect(remaining, const Duration(minutes: 5));
    });

    test('an already expired url reports zero, never a negative span', () {
      final remaining = streamTimeToExpiry(
        'https://cdn.tld/a.m3u8?exp=1788006035',
        now: DateTime.fromMillisecondsSinceEpoch(1788009007 * 1000, isUtc: true),
      );
      expect(remaining, Duration.zero);
    });
  });

  group('renewalDelayFor', () {
    test('renews a full margin before a comfortable deadline', () {
      expect(
        renewalDelayFor(const Duration(minutes: 15)),
        const Duration(minutes: 15) - const Duration(seconds: 45),
      );
    });

    test('halves the margin rather than consuming a short window', () {
      expect(
        renewalDelayFor(const Duration(seconds: 60)),
        const Duration(seconds: 30),
      );
    });

    test('never schedules sooner than the floor', () {
      expect(renewalDelayFor(Duration.zero), const Duration(seconds: 5));
      expect(
        renewalDelayFor(const Duration(seconds: 4)),
        const Duration(seconds: 5),
      );
    });
  });
}
