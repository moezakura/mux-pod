import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_progress_tracker.dart';

void main() {
  group('DownloadProgressTracker 間引き判定', () {
    test('初回サンプルは publish され速度 0 のラベルになる', () {
      final tracker = DownloadProgressTracker();
      final t = DateTime(2024, 1, 1, 0, 0, 0);

      final sample = tracker.update(1024, 1024, t);

      expect(sample.shouldPublish, isTrue);
      expect(sample.cumulative, 1024);
      expect(sample.speedLabel, '0.0 B/s');
    });

    test('間引き窓（100ms）内のサンプルは publish されない', () {
      final tracker = DownloadProgressTracker(
        progressThrottle: const Duration(milliseconds: 100),
      );
      var t = DateTime(2024, 1, 1, 0, 0, 0);
      tracker.update(0, 0, t);

      // 99ms 後: 未 publish。
      t = t.add(const Duration(milliseconds: 99));
      final sample = tracker.update(1024, 1024, t);

      expect(sample.shouldPublish, isFalse);
      expect(sample.speedLabel, isEmpty);
      expect(sample.cumulative, 1024);
    });

    test('間引き窓（100ms）経過後のサンプルは publish され速度が計算される', () {
      final tracker = DownloadProgressTracker(
        progressThrottle: const Duration(milliseconds: 100),
      );
      var t = DateTime(2024, 1, 1, 0, 0, 0);
      tracker.update(0, 0, t);

      // 1000ms 後に 500 bytes: 500 B/s。
      t = t.add(const Duration(milliseconds: 1000));
      final sample = tracker.update(500, 500, t);

      expect(sample.shouldPublish, isTrue);
      expect(sample.speedLabel, '500.0 B/s');
    });

    test('EMA は α=0.3 で平滑化される（2 サンプル目の値は実測）', () {
      final tracker = DownloadProgressTracker(progressThrottle: Duration.zero);
      var t = DateTime(2024, 1, 1, 0, 0, 0);
      tracker.update(0, 0, t);

      t = t.add(const Duration(milliseconds: 1000));
      final s1 = tracker.update(500, 500, t);
      // 初回実サンプルは instant をそのまま採用（500 B/s）。
      expect(s1.speedLabel, '500.0 B/s');

      t = t.add(const Duration(milliseconds: 1000));
      final s2 = tracker.update(1050, 1050, t);
      // 2 回目: instant=550、EMA=0.3*550+0.7*500=515。
      expect(s2.speedLabel, '515.0 B/s');
    });

    test('reset 後は初回扱いになり速度 0 から再開する', () {
      final tracker = DownloadProgressTracker(progressThrottle: Duration.zero);
      var t = DateTime(2024, 1, 1, 0, 0, 0);
      tracker.update(0, 0, t);
      t = t.add(const Duration(milliseconds: 1000));
      tracker.update(500, 500, t);

      tracker.reset();
      t = t.add(const Duration(milliseconds: 1000));
      final sample = tracker.update(1000, 1000, t);

      // reset 直後の初回サンプルは速度 0。
      expect(sample.shouldPublish, isTrue);
      expect(sample.speedLabel, '0.0 B/s');
    });
  });
}
