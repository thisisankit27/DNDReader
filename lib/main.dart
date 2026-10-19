import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'dev/dev_capture.dart';
import 'features/search/search_profile.dart';
import 'services/app_shutdown.dart';
import 'services/document_access.dart';
import 'services/settings_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lets the native runner run clean-up (e.g. the search profile) before the
  // window is destroyed; see services/app_shutdown.dart.
  AppShutdown.install();
  final settings = await SettingsService.load();
  // Null off Android, where documents are plain files and nothing changes.
  final documents = DocumentAccess.create();
  runApp(
    DevCapture(
      child: DndReaderApp(
        settings: settings,
        initialPath:
            _pdfFromArgs(args) ?? (await documents?.initialDocument())?.path,
        documents: documents,
      ),
    ),
  );
  // After the first frame is scheduled and off the UI isolate: clears a search
  // profile a crashed run left behind (Windows only; guarded, never throws).
  unawaited(sweepStaleProfilesAtLaunch());
}

/// The first command-line argument that names an existing `.pdf` file
/// (from "Open With" or `dndreader file.pdf`), or null.
String? _pdfFromArgs(List<String> args) {
  for (final arg in args) {
    if (arg.toLowerCase().endsWith('.pdf') && File(arg).existsSync()) {
      return File(arg).absolute.path;
    }
  }
  return null;
}
