import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'dev/dev_capture.dart';

void main(List<String> args) {
  runApp(DevCapture(child: DndReaderApp(initialPath: _pdfFromArgs(args))));
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
