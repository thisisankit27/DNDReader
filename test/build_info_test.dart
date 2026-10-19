import 'dart:io';

import 'package:dndreader/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// The version a user sees must be one number on every platform.
///
/// Two files decide it independently: `pubspec.yaml`'s `version:` drives the
/// Android `versionName`/`versionCode`, while `kAppVersion` drives the About
/// dialog, the `.deb` and the Windows installer (see `packaging/linux/build-deb.sh`
/// and `packaging/windows/dndreader.iss`). Nothing made them agree until this
/// test, so a release could ship Android 0.3.0 beside a Linux 0.2.2.
void main() {
  group('kAppVersion', () {
    test('matches the version in pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(
        match,
        isNotNull,
        reason: 'pubspec.yaml needs a `version: <major>.<minor>.<patch>+<build>` line',
      );
      expect(kAppVersion, match!.group(1));
    });

    test('is a plain three-part version, with no build suffix', () {
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kAppVersion), isTrue);
    });

    test('fits the Android versionCode formula', () {
      // packaging: major*1e6 + minor*1e4 + patch*100 + build, so patch and
      // build must each stay under 100 or the Gradle build fails outright.
      final parts = kAppVersion.split('.').map(int.parse).toList();
      expect(parts[1], lessThan(100));
      expect(parts[2], lessThan(100));
    });
  });
}
