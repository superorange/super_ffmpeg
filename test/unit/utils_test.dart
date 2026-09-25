import 'package:flutter_test/flutter_test.dart';
import 'package:super_ffmpeg/core/utils/file_naming.dart';
import 'package:super_ffmpeg/core/utils/format.dart';
import 'package:super_ffmpeg/core/utils/shell_words.dart';

void main() {
  group('Fmt', () {
    test('parseTimecode accepts seconds, mm:ss and hh:mm:ss with fractions', () {
      expect(Fmt.parseTimecode('90'), const Duration(seconds: 90));
      expect(Fmt.parseTimecode('1:30'), const Duration(seconds: 90));
      expect(Fmt.parseTimecode('01:30.25'), const Duration(seconds: 90, milliseconds: 250));
      expect(Fmt.parseTimecode('1:02:03.5'), const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500));
      expect(Fmt.parseTimecode(' 5.5 '), const Duration(seconds: 5, milliseconds: 500));
    });

    test('parseTimecode rejects junk and out-of-range fields', () {
      for (final bad in ['', 'abc', '1:60', '1:2:3:4', '-5', '1.5:00', '1::2']) {
        expect(Fmt.parseTimecode(bad), isNull, reason: bad);
      }
    });

    test('timecode round-trips through parseTimecode', () {
      const d = Duration(hours: 2, minutes: 3, seconds: 4, milliseconds: 56);
      expect(Fmt.timecode(d), '02:03:04.056');
      expect(Fmt.parseTimecode(Fmt.timecode(d)), d);
    });

    test('seconds is compact and precise', () {
      expect(Fmt.seconds(const Duration(seconds: 12)), '12');
      expect(Fmt.seconds(const Duration(seconds: 12, milliseconds: 500)), '12.5');
      expect(Fmt.seconds(const Duration(milliseconds: 1005)), '1.005');
    });

    test('bytes / bitrate / duration', () {
      expect(Fmt.bytes(0), '0 B');
      expect(Fmt.bytes(512), '512 B');
      expect(Fmt.bytes(1536), '1.5 KB');
      expect(Fmt.bytes(8 * 1024 * 1024), '8.0 MB');
      expect(Fmt.bitrate(2500000), '2.5 Mbps');
      expect(Fmt.bitrate(128000), '128 kbps');
      expect(Fmt.duration(const Duration(seconds: 65)), '01:05');
      expect(Fmt.duration(const Duration(hours: 1, seconds: 5)), '1:00:05');
    });
  });

  group('ShellWords', () {
    test('splits quotes and escapes like a POSIX shell', () {
      expect(
        ShellWords.split(r'''-i "my file.mp4" -vf 'scale=1280:-2' a\ b "say \"hi\""'''),
        ['-i', 'my file.mp4', '-vf', 'scale=1280:-2', 'a b', 'say "hi"'],
      );
      expect(ShellWords.split('  a   b\n c '), ['a', 'b', 'c']);
      expect(ShellWords.split('""'), ['']);
    });

    test('rejects unterminated quotes', () {
      expect(() => ShellWords.split('-i "oops'), throwsFormatException);
    });

    test('quote/join produce args that split back identically', () {
      final args = ['-i', "it's here.mp4", r'$HOME', '中文 名', 'plain', ''];
      expect(ShellWords.split(ShellWords.join(args)), args);
    });
  });

  group('FileNaming', () {
    test('derive builds name with suffix, extension and optional dir', () {
      expect(
        FileNaming.derive(inputPath: '/a/clip.mov', extension: 'mp4', suffix: 'compressed'),
        '/a/clip_compressed.mp4',
      );
      expect(FileNaming.derive(inputPath: '/a/clip.mov', extension: '.mp3', outputDir: '/out'), '/out/clip.mp3');
    });

    test('unique never returns an existing or reserved path', () {
      final existing = {'/a/x.mp4', '/a/x (1).mp4'};
      bool exists(String p) => existing.contains(p);
      expect(FileNaming.unique('/a/y.mp4', exists: exists), '/a/y.mp4');
      expect(FileNaming.unique('/a/x.mp4', exists: exists), '/a/x (2).mp4');
      expect(FileNaming.unique('/a/x.mp4', exists: exists, reserved: {'/a/x (2).mp4'}), '/a/x (3).mp4');
    });
  });
}
