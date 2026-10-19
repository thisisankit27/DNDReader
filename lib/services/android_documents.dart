import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../features/search/search_profile.dart' show isDirectChildOf;
import 'document_access.dart';

/// Android's [DocumentAccess]: the native side (`MainActivity`, `DocumentImporter`) copies each
/// document into `filesDir/documents/<sha256>/<name>.pdf`; this side keeps that folder tidy.
///
/// Stored copies are named by the SHA-256 of their bytes, so the same attachment shared twice is
/// one folder. [prune] is the only place the app deletes under a derived path, so it is written as
/// a pure decision ([decidePrune]) tested for every refusal, with the IO kept dumb.

/// A folder under `documents/` is exactly 64 lowercase hex digits (a SHA-256).
final RegExp _storedKey = RegExp(r'^[0-9a-f]{64}$');

/// A folder younger than this is never pruned: it may belong to an import whose path has not
/// reached the recents list yet.
const Duration kDocumentMinAge = Duration(seconds: 60);

bool isStoredDocumentKey(String name) => _storedKey.hasMatch(name);

/// The storage keys named by [paths] that live directly under [root]: `<root>/<key>/<file>`.
Set<String> keysToKeep(Iterable<String> paths, String root) {
  final keys = <String>{};
  final prefix = root.endsWith('/') ? root : '$root/';
  for (final path in paths) {
    if (!path.startsWith(prefix)) continue;
    final rest = path.substring(prefix.length).split('/');
    if (rest.length >= 2 && isStoredDocumentKey(rest.first)) {
      keys.add(rest.first);
    }
  }
  return keys;
}

enum PruneVerdict {
  delete,
  rejectName,
  rejectNotDirectory,
  rejectSymlink,
  rejectUnresolved,
  rejectOutsideRoot,
  rejectKept,
  rejectTooNew,
  rejectImporting,
}

/// Decides whether one entry of the documents folder may be deleted. Pure: every fact is passed
/// in; [resolvedPath]/[resolvedRoot] must have had symlinks expanded first. Only
/// [PruneVerdict.delete] permits deletion.
PruneVerdict decidePrune({
  required String name,
  required FileSystemEntityType entryType,
  required String? resolvedPath,
  required String resolvedRoot,
  required Set<String> keep,
  required Duration age,
  required bool importing,
  Duration minAge = kDocumentMinAge,
}) {
  if (!isStoredDocumentKey(name)) return PruneVerdict.rejectName;
  if (importing) return PruneVerdict.rejectImporting;
  if (entryType == FileSystemEntityType.link) return PruneVerdict.rejectSymlink;
  if (entryType != FileSystemEntityType.directory) {
    return PruneVerdict.rejectNotDirectory;
  }
  if (resolvedPath == null) return PruneVerdict.rejectUnresolved;
  if (!isDirectChildOf(
    resolvedPath,
    resolvedRoot,
    name,
    separator: '/',
    caseInsensitive: false,
  )) {
    return PruneVerdict.rejectOutsideRoot;
  }
  if (keep.contains(name)) return PruneVerdict.rejectKept;
  if (age < minAge) return PruneVerdict.rejectTooNew;
  return PruneVerdict.delete;
}

/// What the user is told for each native failure code.
@visibleForTesting
String importErrorMessage(String? code) {
  switch (code) {
    case 'denied':
      return 'DNDReader no longer has access to that file.';
    case 'missing':
      return 'That file is no longer available.';
    case 'no_space':
      return 'There isn’t enough free storage to open that file.';
    case 'too_large':
      return 'That file is too large to open (the limit is 1 GB).';
    default:
      return 'Couldn’t open that file.';
  }
}

class AndroidDocumentAccess implements DocumentAccess {
  AndroidDocumentAccess({MethodChannel? channel, this.minAge = kDocumentMinAge})
    : _channel = channel ?? const MethodChannel('dndreader/documents') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;

  /// See [kDocumentMinAge]; only tests change it.
  final Duration minAge;
  final StreamController<DocumentEvent> _incoming =
      StreamController<DocumentEvent>();
  final ValueNotifier<bool> _importing = ValueNotifier<bool>(false);
  int _inFlight = 0;

  @override
  Stream<DocumentEvent> get incoming => _incoming.stream;

  @override
  ValueListenable<bool> get importing => _importing;

  Future<T> _tracked<T>(Future<T> Function() work) async {
    _inFlight++;
    _importing.value = true;
    try {
      return await work();
    } finally {
      _inFlight--;
      _importing.value = _inFlight > 0;
    }
  }

  static DocumentEvent _eventFrom(Object? raw) {
    if (raw is Map) {
      final path = raw['path'];
      if (path is String && path.isNotEmpty) return DocumentEvent.opened(path);
      final error = raw['error'];
      return DocumentEvent.failed(
        importErrorMessage(error is String ? error : null),
      );
    }
    return DocumentEvent.failed(importErrorMessage(null));
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'incoming') {
      // A document that arrived while running. Its native import already finished, so the
      // folder is fresh and the prune's age guard ([kDocumentMinAge]) protects it.
      _incoming.add(_eventFrom(call.arguments));
    }
  }

  @override
  Future<String?> pick() => _tracked(() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('pick');
      if (raw == null) return null;
      final event = _eventFrom(raw);
      if (event.path == null) throw DocumentImportException(event.error!);
      return event.path;
    } on PlatformException catch (e) {
      throw DocumentImportException(importErrorMessage(e.code));
    }
  });

  @override
  Future<DocumentEvent?> initialDocument() => _tracked(() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('initialDocument');
      if (raw == null) return null;
      return _eventFrom(raw);
    } on PlatformException catch (e) {
      // Delivered with the incoming events so the reader can show it once it is up.
      _incoming.add(DocumentEvent.failed(importErrorMessage(e.code)));
      return null;
    } on MissingPluginException {
      return null;
    }
  });

  @override
  Future<void> prune(Iterable<String> keep) async {
    if (_inFlight > 0) return;
    try {
      final rootPath = await _channel.invokeMethod<String>('documentsDir');
      if (rootPath == null) return;
      final root = Directory(rootPath);
      if (!root.existsSync()) return;
      final String resolvedRoot;
      try {
        resolvedRoot = root.resolveSymbolicLinksSync();
      } on FileSystemException {
        return;
      }
      final keepKeys = keysToKeep(keep, rootPath);
      final now = DateTime.now();
      for (final entry in root.listSync(followLinks: false)) {
        final name = entry.uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => '',
        );
        // Cheapest and most important check first: nothing is stat'ed or resolved for an entry
        // whose name is not a stored-document key.
        if (!isStoredDocumentKey(name)) continue;
        final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
        String? resolved;
        var age = Duration.zero;
        if (type == FileSystemEntityType.directory) {
          try {
            resolved = Directory(entry.path).resolveSymbolicLinksSync();
            age = now.difference(FileStat.statSync(entry.path).modified);
          } on FileSystemException {
            continue;
          }
        }
        final verdict = decidePrune(
          name: name,
          entryType: type,
          resolvedPath: resolved,
          resolvedRoot: resolvedRoot,
          keep: keepKeys,
          age: age,
          importing: _inFlight > 0,
          minAge: minAge,
        );
        if (verdict != PruneVerdict.delete) continue;
        try {
          Directory(entry.path).deleteSync(recursive: true);
        } on FileSystemException {
          // In use; the next open tries again.
        }
      }
    } on PlatformException {
      // Pruning is housekeeping; never surface a failure.
    } on MissingPluginException {
      // No native side (tests).
    }
  }
}
