import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Directory to write `latest.png` into. Empty (the default) disables capture.
/// Set with `--dart-define=DNDREADER_CAPTURE_DIR=/some/dir`.
const String _captureDir = String.fromEnvironment('DNDREADER_CAPTURE_DIR');

/// Development aid: periodically writes the composited Flutter frame to a PNG so
/// UI changes can be inspected without an external screenshot tool (external
/// capture of a GL window is unreliable on this machine's XWayland).
///
/// Inert — returns [child] unchanged — in release builds and whenever
/// `DNDREADER_CAPTURE_DIR` is not defined.
class DevCapture extends StatefulWidget {
  const DevCapture({super.key, required this.child});

  final Widget child;

  static bool get enabled => !kReleaseMode && _captureDir.isNotEmpty;

  @override
  State<DevCapture> createState() => _DevCaptureState();
}

class _DevCaptureState extends State<DevCapture> {
  final GlobalKey _boundary = GlobalKey();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (DevCapture.enabled) {
      Directory(_captureDir).createSync(recursive: true);
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _capture());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _capture() async {
    try {
      final boundary =
          _boundary.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      await File('$_captureDir/latest.png')
          .writeAsBytes(bytes.buffer.asUint8List());
    } catch (e) {
      // Debug-mode paint race ('!debugNeedsPaint'): the next tick retries.
      debugPrint('DevCapture: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DevCapture.enabled) return widget.child;
    return RepaintBoundary(key: _boundary, child: widget.child);
  }
}
