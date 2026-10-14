import 'dart:async';

import 'package:dndreader/services/app_shutdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AppShutdown.resetForTest);

  test('runs every registered hook once, even when called twice', () async {
    var a = 0, b = 0;
    AppShutdown.register(() async => a++);
    AppShutdown.register(() async => b++);
    await Future.wait([AppShutdown.run(), AppShutdown.run()]);
    await AppShutdown.run();
    expect((a, b), (1, 1));
  });

  test('a hook that throws does not stop the others or the close', () async {
    var ran = false;
    AppShutdown.register(() async => throw StateError('boom'));
    AppShutdown.register(() async => ran = true);
    await AppShutdown.run();
    expect(ran, isTrue);
  });

  test(
    'a hook that never finishes delays the close by at most the timeout',
    () async {
      AppShutdown.register(() => Completer<void>().future);
      final watch = Stopwatch()..start();
      await AppShutdown.run(timeout: const Duration(milliseconds: 80));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test('with no hooks the close is immediate', () async {
    await AppShutdown.run();
  });

  test('unregistered hooks are not run', () async {
    var ran = false;
    Future<void> hook() async => ran = true;
    AppShutdown.register(hook);
    AppShutdown.unregister(hook);
    await AppShutdown.run();
    expect(ran, isFalse);
  });

  test(
    'the runner\'s prepareToClose call runs the hooks and is answered',
    () async {
      var ran = false;
      AppShutdown.register(() async => ran = true);
      AppShutdown.install();

      const codec = StandardMethodCodec();
      final reply = Completer<ByteData?>();
      unawaited(
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'dndreader/lifecycle',
              codec.encodeMethodCall(const MethodCall('prepareToClose')),
              reply.complete,
            ),
      );
      final data = await reply.future.timeout(const Duration(seconds: 5));
      expect(ran, isTrue);
      // A success envelope (null result), not an error.
      expect(() => codec.decodeEnvelope(data!), returnsNormally);
    },
  );
}
