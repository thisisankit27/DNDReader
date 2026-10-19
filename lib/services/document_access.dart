import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'android_documents.dart';

/// A document the system handed us, or why it could not be opened.
@immutable
class DocumentEvent {
  const DocumentEvent.opened(String this.path) : error = null;
  const DocumentEvent.failed(String this.error) : path = null;

  /// A real file path the reader can open (see [DocumentAccess]).
  final String? path;

  /// A calm, user-presentable reason, when [path] is null.
  final String? error;
}

/// A document could not be brought in; [message] is user-presentable.
class DocumentImportException implements Exception {
  const DocumentImportException(this.message);

  final String message;

  @override
  String toString() => 'DocumentImportException: $message';
}

/// Where documents come from on a platform whose documents are not durable file paths.
///
/// Android has no stable paths for user documents: they are `content://` URIs, often one-shot
/// grants. Every document is therefore copied into app-private storage and the reader keeps
/// working with a plain path, exactly as on desktop. Null elsewhere: desktop reads files in place
/// (the native file chooser, a command-line path), and nothing about it changes.
abstract class DocumentAccess {
  /// The implementation for this platform, or null where documents are ordinary files.
  static DocumentAccess? create() =>
      Platform.isAndroid ? AndroidDocumentAccess() : null;

  /// Shows the system picker. Null when cancelled; throws [DocumentImportException] when the
  /// chosen document could not be brought in.
  Future<String?> pick();

  /// The document the app was launched with (ACTION_VIEW / ACTION_SEND), once; null otherwise. A
  /// failure is delivered on [incoming] so it can be shown once the UI is up.
  Future<DocumentEvent?> initialDocument();

  /// Documents that arrive while the app is running (warm start, or a second intent).
  Stream<DocumentEvent> get incoming;

  /// True while a document is being copied in (a large or cloud file can take a while).
  ValueListenable<bool> get importing;

  /// Removes stored copies no longer referenced by [keep] (recents, last document, the open one).
  Future<void> prune(Iterable<String> keep);
}
