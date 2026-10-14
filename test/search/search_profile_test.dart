import 'dart:io';

import 'package:dndreader/features/search/search_profile.dart';
import 'package:flutter_test/flutter_test.dart';

SweepVerdict _decide({
  String name = 'dndreader-search-4242',
  FileSystemEntityType type = FileSystemEntityType.directory,
  String? resolved = '/tmp/x/dndreader-search-4242',
  String temp = '/tmp/x',
  String separator = '/',
  bool caseInsensitive = false,
  int ownPid = 1,
  LockState lock = LockState.free,
  Duration age = const Duration(hours: 1),
}) => decideSweep(
  name: name,
  entryType: type,
  resolvedPath: resolved,
  resolvedTempPath: temp,
  separator: separator,
  caseInsensitive: caseInsensitive,
  ownPid: ownPid,
  lock: lock,
  age: age,
);

void main() {
  _launchSweepTests();

  group('isOwnedProfileName', () {
    test('accepts exactly dndreader-search-<digits>', () {
      expect(isOwnedProfileName('dndreader-search-1'), isTrue);
      expect(isOwnedProfileName('dndreader-search-4242'), isTrue);
      expect(isOwnedProfileName(profileDirName(987654)), isTrue);
    });

    test('rejects everything else', () {
      for (final bad in [
        '',
        'dndreader-search-',
        'dndreader-search-12a',
        'dndreader-search-a12',
        'dndreader-search-12 ',
        ' dndreader-search-12',
        'dndreader-search-12\n',
        'dndreader-search-12/',
        'dndreader-search-12/..',
        'dndreader-search-12\\..',
        'dndreader-search-1-2',
        'dndreader-search--1',
        'dndreader-search-１２', // full-width digits
        'xdndreader-search-12',
        'dndreader-search-12-old',
        'DNDREADER-SEARCH-12',
        'dndreader-search',
        '..',
        '.',
      ]) {
        expect(isOwnedProfileName(bad), isFalse, reason: 'name: "$bad"');
      }
    });
  });

  group('isDirectChildOf', () {
    test('is an exact match, not a prefix test', () {
      bool child(String r, String p, String n) =>
          isDirectChildOf(r, p, n, separator: '/', caseInsensitive: false);
      expect(
        child('/tmp/dndreader-search-1', '/tmp', 'dndreader-search-1'),
        isTrue,
      );
      expect(
        child('/tmp/dndreader-search-1', '/tmp/', 'dndreader-search-1'),
        isTrue,
      );
      expect(
        child('/tmpevil/dndreader-search-1', '/tmp', 'dndreader-search-1'),
        isFalse,
      );
      expect(
        child('/tmp/sub/dndreader-search-1', '/tmp', 'dndreader-search-1'),
        isFalse,
      );
      expect(
        child('/elsewhere/dndreader-search-1', '/tmp', 'dndreader-search-1'),
        isFalse,
      );
      expect(
        child('/tmp/dndreader-search-1/x', '/tmp', 'dndreader-search-1'),
        isFalse,
      );
    });

    test('compares case-insensitively only when told to (Windows)', () {
      expect(
        isDirectChildOf(
          r'C:\USERS\X\TEMP\dndreader-search-1',
          r'C:\Users\x\Temp',
          'dndreader-search-1',
          separator: r'\',
          caseInsensitive: true,
        ),
        isTrue,
      );
      expect(
        isDirectChildOf(
          r'C:\USERS\X\TEMP\dndreader-search-1',
          r'C:\Users\x\Temp',
          'dndreader-search-1',
          separator: r'\',
          caseInsensitive: false,
        ),
        isFalse,
      );
    });
  });

  group('decideSweep', () {
    test('deletes a stale directory of ours', () {
      expect(_decide(), SweepVerdict.delete);
      expect(_decide(lock: LockState.absent), SweepVerdict.delete);
    });

    test('refuses a name that is not ours', () {
      expect(_decide(name: 'Documents'), SweepVerdict.rejectName);
      expect(_decide(name: 'dndreader-search-12x'), SweepVerdict.rejectName);
      expect(_decide(name: 'dndreader-search-'), SweepVerdict.rejectName);
    });

    test('refuses a symlink, without needing to resolve it', () {
      expect(
        _decide(type: FileSystemEntityType.link),
        SweepVerdict.rejectSymlink,
      );
    });

    test('refuses a file or anything not a directory', () {
      expect(
        _decide(type: FileSystemEntityType.file),
        SweepVerdict.rejectNotDirectory,
      );
      expect(
        _decide(type: FileSystemEntityType.notFound),
        SweepVerdict.rejectNotDirectory,
      );
    });

    test('refuses when the path could not be resolved', () {
      expect(_decide(resolved: null), SweepVerdict.rejectUnresolved);
    });

    test('refuses a path that resolves outside the temp directory', () {
      expect(
        _decide(resolved: '/home/user/dndreader-search-4242'),
        SweepVerdict.rejectOutsideTemp,
      );
      expect(
        _decide(resolved: '/tmp/x/other/dndreader-search-4242'),
        SweepVerdict.rejectOutsideTemp,
      );
      expect(
        _decide(resolved: '/tmp/xx/dndreader-search-4242'),
        SweepVerdict.rejectOutsideTemp,
      );
      // Resolves to a different name than the entry claims.
      expect(
        _decide(resolved: '/tmp/x/precious'),
        SweepVerdict.rejectOutsideTemp,
      );
    });

    test('refuses this process\'s own profile', () {
      expect(_decide(ownPid: 4242), SweepVerdict.rejectOwnProfile);
    });

    test('refuses a profile another live instance holds', () {
      expect(_decide(lock: LockState.held), SweepVerdict.rejectInUse);
    });

    test('refuses a lock-less folder that is too new to be stale', () {
      expect(
        _decide(lock: LockState.absent, age: const Duration(seconds: 5)),
        SweepVerdict.rejectTooNew,
      );
    });
  });

  group('SearchProfileStore on a real directory', () {
    late Directory root;
    late Directory temp;
    late Directory outside;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dndreader-test-');
      temp = Directory('${root.path}/temp')..createSync();
      outside = Directory('${root.path}/outside')..createSync();
    });

    tearDown(() => root.deleteSync(recursive: true));

    SearchProfileStore store({int pid = 100, LockProbe? probe}) =>
        SearchProfileStore(
          tempDir: temp,
          ownPid: pid,
          caseInsensitive: false,
          lockProbe: probe ?? (_) => LockState.free,
        );

    test('profile path is <temp><sep>dndreader-search-<pid>', () {
      expect(
        store(pid: 77).profileDir.path,
        '${temp.path}${Platform.pathSeparator}dndreader-search-77',
      );
    });

    test(
      'create makes the folder and its lock file; delete removes it',
      () async {
        final s = store(pid: 101);
        final dir = s.create();
        expect(dir.existsSync(), isTrue);
        expect(
          File('${dir.path}/$kSearchProfileLockName').existsSync(),
          isTrue,
        );
        File('${dir.path}/Cookies').writeAsStringSync('x');
        expect(await s.delete(), isTrue);
        expect(dir.existsSync(), isFalse);
        expect(temp.existsSync(), isTrue);
      },
    );

    test('sweeps stale folders of ours, and only those', () {
      final stale = Directory('${temp.path}/dndreader-search-5')..createSync();
      File('${stale.path}/a').writeAsStringSync('a');
      final stale2 = Directory('${temp.path}/dndreader-search-6')..createSync();
      final other = Directory('${temp.path}/Documents')..createSync();
      final lookalike = Directory('${temp.path}/dndreader-search-6x')
        ..createSync();
      final prefixOnly = Directory('${temp.path}/dndreader-search-')
        ..createSync();
      final file = File('${temp.path}/dndreader-search-7')
        ..writeAsStringSync('not a directory');
      final own = Directory('${temp.path}/dndreader-search-100')..createSync();

      final removed = store(pid: 100)
          .sweepStale(now: DateTime.now().add(const Duration(days: 1)));

      expect(removed, 2);
      expect(stale.existsSync(), isFalse);
      expect(stale2.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
      expect(lookalike.existsSync(), isTrue);
      expect(prefixOnly.existsSync(), isTrue);
      expect(file.existsSync(), isTrue);
      expect(own.existsSync(), isTrue, reason: 'own pid is never swept');
    });

    test(
      'does not follow a symlink that points outside the temp directory',
      () {
        File('${outside.path}/precious.txt').writeAsStringSync('keep me');
        Directory('${outside.path}/dndreader-search-9').createSync();
        File('${outside.path}/dndreader-search-9/inner')
            .writeAsStringSync('keep');
        final link = Link('${temp.path}/dndreader-search-9')
          ..createSync(outside.path);

        final removed = store().sweepStale(
          now: DateTime.now().add(const Duration(days: 1)),
        );

        expect(removed, 0);
        expect(File('${outside.path}/precious.txt').existsSync(), isTrue);
        expect(
          File('${outside.path}/dndreader-search-9/inner').existsSync(),
          isTrue,
        );
        expect(link.existsSync(), isTrue);
        expect(FileSystemEntity.isLinkSync(link.path), isTrue);
      },
    );

    test('does not delete through a symlink to a same-named directory', () {
      // The link's name is ours and its target is a real directory, but the
      // entry is a link, so it must be refused before it is ever resolved.
      final target = Directory('${outside.path}/dndreader-search-12')
        ..createSync();
      File('${target.path}/data').writeAsStringSync('keep');
      Link('${temp.path}/dndreader-search-12').createSync(target.path);

      expect(
        store().sweepStale(now: DateTime.now().add(const Duration(days: 1))),
        0,
      );
      expect(File('${target.path}/data').existsSync(), isTrue);
    });

    test('leaves a profile a live instance holds', () {
      final live = Directory('${temp.path}/dndreader-search-55')..createSync();
      final removed = store(probe: (_) => LockState.held)
          .sweepStale(now: DateTime.now().add(const Duration(days: 1)));
      expect(removed, 0);
      expect(live.existsSync(), isTrue);
    });

    test('leaves a brand-new lock-less folder alone', () {
      final fresh = Directory('${temp.path}/dndreader-search-56')..createSync();
      final removed = store(probe: (_) => LockState.absent).sweepStale();
      expect(removed, 0);
      expect(fresh.existsSync(), isTrue);
    });

    test('a missing temp directory sweeps nothing and does not throw', () {
      final s = SearchProfileStore(
        tempDir: Directory('${root.path}/does-not-exist'),
        ownPid: 1,
      );
      expect(s.sweepStale(), 0);
    });

    test('probeLockFile reports absent when there is no lock file', () {
      final d = Directory('${temp.path}/dndreader-search-60')..createSync();
      expect(probeLockFile(d), LockState.absent);
      File('${d.path}/$kSearchProfileLockName').writeAsStringSync('');
      expect(probeLockFile(d), LockState.free);
    });

    test('delete refuses a profile path that is a symlink', () async {
      File('${outside.path}/precious.txt').writeAsStringSync('keep');
      Link('${temp.path}/dndreader-search-200').createSync(outside.path);
      final s = store(pid: 200);
      expect(await s.delete(attempts: 1), isFalse);
      expect(File('${outside.path}/precious.txt').existsSync(), isTrue);
    });
  });
}

void _launchSweepTests() {
  group('sweepStaleProfilesAtLaunch (D2)', () {
    late Directory root;
    late Directory temp;
    late Directory outside;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dndreader-launch-');
      temp = Directory('${root.path}/temp')..createSync();
      outside = Directory('${root.path}/outside')..createSync();
    });

    tearDown(() => root.deleteSync(recursive: true));

    // A leftover of a crashed run: its lock file is still there, but no process
    // holds it. (The lock-less case is covered by the age rule's own tests.)
    Directory leftover(String name) {
      final d = Directory('${temp.path}/$name')..createSync();
      File('${d.path}/$kSearchProfileLockName').writeAsStringSync('');
      File('${d.path}/Cookies').writeAsStringSync('x');
      return d;
    }

    test(
      'does nothing when not enabled (every non-Windows platform)',
      () async {
        final d = leftover('dndreader-search-31');
        expect(
          await sweepStaleProfilesAtLaunch(
            tempDir: temp,
            ownPid: 1,
            enabled: false,
          ),
          0,
        );
        expect(d.existsSync(), isTrue);
      },
    );

    test(
      'removes a crashed run\'s folder at launch, off the UI isolate',
      () async {
        final d = leftover('dndreader-search-32');
        final removed = await sweepStaleProfilesAtLaunch(
          tempDir: temp,
          ownPid: 1,
          enabled: true,
        );
        expect(removed, 1);
        expect(d.existsSync(), isFalse);
        expect(temp.existsSync(), isTrue);
      },
    );

    test('keeps every guard: names, own pid, files, symlinks, new lock-less folders', () async {
      final stale = leftover('dndreader-search-40');
      final lookalike = leftover('dndreader-search-40x');
      final other = leftover('Documents');
      final own = leftover('dndreader-search-777');
      final file = File('${temp.path}/dndreader-search-41')
        ..writeAsStringSync('a file');
      final fresh = Directory('${temp.path}/dndreader-search-42')..createSync();
      File('${outside.path}/precious').writeAsStringSync('keep');
      Link('${temp.path}/dndreader-search-43').createSync(outside.path);

      final removed = await sweepStaleProfilesAtLaunch(
        tempDir: temp,
        ownPid: 777,
        enabled: true,
      );

      expect(removed, 1);
      expect(stale.existsSync(), isFalse);
      expect(lookalike.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
      expect(own.existsSync(), isTrue);
      expect(file.existsSync(), isTrue);
      expect(fresh.existsSync(), isTrue);
      expect(File('${outside.path}/precious').existsSync(), isTrue);
      expect(Link('${temp.path}/dndreader-search-43').existsSync(), isTrue);
    });

    test('a missing temp directory is not an error', () async {
      expect(
        await sweepStaleProfilesAtLaunch(
          tempDir: Directory('${root.path}/nope'),
          ownPid: 1,
          enabled: true,
        ),
        0,
      );
    });
  });
}
