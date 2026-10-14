import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'dev/dev_capture.dart';
import 'services/settings_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsService.load();
  runApp(
    DevCapture(
      child: DndReaderApp(settings: settings, initialPath: _pdfFromArgs(args)),
    ),
  );
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
