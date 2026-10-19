import 'dart:async';
import 'dart:io';

import 'package:dndreader/services/android_documents.dart';
import 'package:dndreader/services/document_access.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _keyA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _keyB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('keysToKeep', () {
    test('takes the folder name of paths directly under the root', () {
      expect(
        keysToKeep([
          '/r/documents/$_keyA/Book.pdf',
          '/r/documents/$_keyB/x.pdf',
        ], '/r/documents'),
        {_keyA, _keyB},
      );
    });

    test('ignores paths outside the root and folders that are not keys', () {
      expect(
        keysToKeep([
          '/elsewhere/$_keyA/Book.pdf',
          '/r/documents/notakey/Book.pdf',
          '/r/documents/$_keyA', // no file segment
          '/home/me/Book.pdf',
        ], '/r/documents'),
        isEmpty,
      );
    });
  });

  group(
    'decidePrune refuses everything but an old, unreferenced stored folder',
    () {
      PruneVerdict decide({
        String name = _keyA,
        FileSystemEntityType type = FileSystemEntityType.directory,
        String? resolved = '/r/documents/$_keyA',
        Set<String> keep = const {},
        Duration age = const Duration(hours: 2),
        bool importing = false,
      }) => decidePrune(
        name: name,
        entryType: type,
        resolvedPath: resolved,
        resolvedRoot: '/r/documents',
        keep: keep,
        age: age,
        importing: importing,
      );

      test(
        'deletes the plain case',
        () => expect(decide(), PruneVerdict.delete),
      );
      test('a name that is not a SHA-256 key', () {
        expect(decide(name: '.import-1.tmp'), PruneVerdict.rejectName);
        expect(decide(name: 'documents'), PruneVerdict.rejectName);
        expect(decide(name: _keyA.toUpperCase()), PruneVerdict.rejectName);
      });
      test(
        'an import in flight',
        () => expect(decide(importing: true), PruneVerdict.rejectImporting),
      );
      test(
        'a symlink',
        () => expect(
          decide(type: FileSystemEntityType.link),
          PruneVerdict.rejectSymlink,
        ),
      );
      test(
        'not a directory',
        () => expect(
          decide(type: FileSystemEntityType.file),
          PruneVerdict.rejectNotDirectory,
        ),
      );
      test(
        'unresolved',
        () => expect(decide(resolved: null), PruneVerdict.rejectUnresolved),
      );
      test('resolves outside the root', () {
        expect(
          decide(resolved: '/somewhere/else/$_keyA'),
          PruneVerdict.rejectOutsideRoot,
        );
        expect(
          decide(resolved: '/r/documents/x/$_keyA'),
          PruneVerdict.rejectOutsideRoot,
        );
      });
      test(
        'referenced by recents or the open document',
        () => expect(decide(keep: {_keyA}), PruneVerdict.rejectKept),
      );
      test(
        'too new',
        () => expect(
          decide(age: const Duration(seconds: 5)),
          PruneVerdict.rejectTooNew,
        ),
      );
    },
  );

  group('error messages', () {
    test('each native code has a calm sentence, unknown codes fall back', () {
      for (final code in [
        'denied',
        'missing',
        'no_space',
        'too_large',
        'failed',
        null,
        'zzz',
      ]) {
        final m = importErrorMessage(code);
        expect(m, isNotEmpty);
        expect(m.toLowerCase(), isNot(contains('exception')));
      }
      expect(importErrorMessage('missing'), contains('no longer available'));
      expect(importErrorMessage('zzz'), importErrorMessage(null));
    });
  });

  group('AndroidDocumentAccess over the channel', () {
    const channel = MethodChannel('dndreader/documents');
    late Directory tmp;
    late Map<String, Future<Object?> Function(MethodCall)> handlers;
    late AndroidDocumentAccess access;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('dnd-docs-test');
      handlers = {'documentsDir': (_) async => tmp.path};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final h = handlers[call.method];
            if (h == null) throw MissingPluginException();
            return h(call);
          });
      access = AndroidDocumentAccess(channel: channel, minAge: Duration.zero);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      tmp.deleteSync(recursive: true);
    });

    test('pick returns the stored path, or null when cancelled', () async {
      handlers['pick'] = (_) async => {'path': '/r/a.pdf', 'name': 'a.pdf'};
      expect(await access.pick(), '/r/a.pdf');
      handlers['pick'] = (_) async => null;
      expect(await access.pick(), isNull);
    });

    test(
      'pick turns a native failure into a calm DocumentImportException',
      () async {
        handlers['pick'] = (_) async =>
            throw PlatformException(code: 'no_space');
        await expectLater(
          access.pick(),
          throwsA(
            isA<DocumentImportException>().having(
              (e) => e.message,
              'message',
              importErrorMessage('no_space'),
            ),
          ),
        );
        handlers['pick'] = (_) async => throw PlatformException(code: 'denied');
        await expectLater(
          access.pick(),
          throwsA(isA<DocumentImportException>()),
        );
      },
    );

    test('initialDocument: a document, nothing, and a failure delivered on incoming', () async {
      handlers['initialDocument'] = (_) async => {
        'path': '/r/a.pdf',
        'name': 'a.pdf',
      };
      expect((await access.initialDocument())?.path, '/r/a.pdf');
      handlers['initialDocument'] = (_) async => null;
      expect(await access.initialDocument(), isNull);

      final events = <DocumentEvent>[];
      final sub = access.incoming.listen(events.add);
      handlers['initialDocument'] = (_) async =>
          throw PlatformException(code: 'missing');
      expect(await access.initialDocument(), isNull);
      await pumpEventQueue();
      expect(events.single.error, importErrorMessage('missing'));
      await sub.cancel();
    });

    test(
      'a second intent arrives on incoming, buffered until listened to',
      () async {
        Future<void> deliver(Object? args) => TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              channel.codec.encodeMethodCall(MethodCall('incoming', args)),
              (_) {},
            );
        await deliver({'path': '/r/b.pdf', 'name': 'b.pdf'});
        await deliver({'error': 'denied'});
        final events = await access.incoming.take(2).toList();
        expect(events[0].path, '/r/b.pdf');
        expect(events[1].path, isNull);
        expect(events[1].error, importErrorMessage('denied'));
      },
    );

    test(
      'prune removes only unreferenced stored folders, and nothing else',
      () async {
        Directory('${tmp.path}/$_keyA').createSync();
        File('${tmp.path}/$_keyA/Keep.pdf').writeAsStringSync('x');
        Directory('${tmp.path}/$_keyB').createSync();
        File('${tmp.path}/$_keyB/Drop.pdf').writeAsStringSync('x');
        Directory('${tmp.path}/not-a-key').createSync();
        File('${tmp.path}/.import-1.tmp').writeAsStringSync('x');

        await access.prune(['${tmp.path}/$_keyA/Keep.pdf']);

        expect(Directory('${tmp.path}/$_keyA').existsSync(), isTrue);
        expect(Directory('${tmp.path}/$_keyB').existsSync(), isFalse);
        expect(Directory('${tmp.path}/not-a-key').existsSync(), isTrue);
        expect(File('${tmp.path}/.import-1.tmp').existsSync(), isTrue);
      },
    );

    test('prune does nothing while an import is in flight', () async {
      Directory('${tmp.path}/$_keyB').createSync();
      final gate = Completer<Object?>();
      handlers['pick'] = (_) => gate.future;
      final picking = access.pick();
      await pumpEventQueue();
      expect(access.importing.value, isTrue);

      await access.prune(const []);
      expect(Directory('${tmp.path}/$_keyB').existsSync(), isTrue);

      gate.complete(null);
      await picking;
      expect(access.importing.value, isFalse);
      await access.prune(const []);
      expect(Directory('${tmp.path}/$_keyB').existsSync(), isFalse);
    });

    test('prune never throws without a native side', () async {
      handlers.remove('documentsDir');
      await access.prune(const []);
    });
  });
}
