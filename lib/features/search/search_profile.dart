import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;

/// The throwaway WebView2 user-data folder used on Windows (plan §4).
///
/// WebView2 cannot keep a profile purely in memory, so the search panel's
/// cookies and storage live in `%TEMP%\dndreader-search-<pid>` for the length of
/// the session and the folder is deleted on quit. A crash can leave one behind;
/// the next launch sweeps it.
///
/// The sweep is the one place in the app that deletes directories under a path
/// derived at runtime, so it is written as a pure decision ([decideSweep]) that
/// is tested for every refusal, with the IO kept separate and dumb
/// (plan W2.1). **Every** check must pass before a directory is touched.

const String kSearchProfilePrefix = 'dndreader-search-';

/// A file inside each live profile folder, locked for the life of the process
/// that owns it. A sweeper that cannot take the lock treats the folder as in
/// use. (Process ids are reused, so "is that pid alive" is not good enough.)
const String kSearchProfileLockName = '.dndreader-lock';

/// A folder with no lock file is only swept once it is this old, so a live
/// instance that has created its folder but not yet its lock file is safe.
const Duration kSearchProfileMinAge = Duration(seconds: 60);

// Anchored, digits only, nothing else. `[0-9]`, not `\d`, to be explicit.
final RegExp _ownedName = RegExp(r'^dndreader-search-[0-9]+$');

/// Whether [name] is exactly `dndreader-search-<digits>`.
bool isOwnedProfileName(String name) => _ownedName.hasMatch(name);

/// The folder name for process [pid].
String profileDirName(int pid) => '$kSearchProfilePrefix$pid';

/// What the lock probe found inside a candidate folder.
enum LockState {
  /// No lock file.
  absent,

  /// The lock file exists and nobody holds it: its owner is gone.
  free,

  /// Another process holds it: a live instance.
  held,
}

/// The outcome of [decideSweep]. Only [delete] permits deletion.
enum SweepVerdict {
  delete,
  rejectName,
  rejectNotDirectory,
  rejectSymlink,
  rejectUnresolved,
  rejectOutsideTemp,
  rejectOwnProfile,
  rejectInUse,
  rejectTooNew,
}

/// Decides whether one entry of the temp directory may be deleted.
///
/// Pure: every fact it needs is passed in. [entryType] must have been read
/// *without* following links; [resolvedPath] and [resolvedTempPath] must be
/// fully resolved (symlinks and junctions expanded) *before* this is called, so
/// the comparison is made on real locations, not on strings that merely look
/// right.
SweepVerdict decideSweep({
  required String name,
  required FileSystemEntityType entryType,
  required String? resolvedPath,
  required String resolvedTempPath,
  required String separator,
  required bool caseInsensitive,
  required int ownPid,
  required LockState lock,
  required Duration age,
  Duration minAge = kSearchProfileMinAge,
}) {
  if (!isOwnedProfileName(name)) return SweepVerdict.rejectName;
  if (entryType == FileSystemEntityType.link) return SweepVerdict.rejectSymlink;
  if (entryType != FileSystemEntityType.directory) {
    return SweepVerdict.rejectNotDirectory;
  }
  if (resolvedPath == null) return SweepVerdict.rejectUnresolved;
  if (!isDirectChildOf(
    resolvedPath,
    resolvedTempPath,
    name,
    separator: separator,
    caseInsensitive: caseInsensitive,
  )) {
    return SweepVerdict.rejectOutsideTemp;
  }
  if (name == profileDirName(ownPid)) return SweepVerdict.rejectOwnProfile;
  switch (lock) {
    case LockState.held:
      return SweepVerdict.rejectInUse;
    case LockState.absent:
      if (age < minAge) return SweepVerdict.rejectTooNew;
    case LockState.free:
      break;
  }
  return SweepVerdict.delete;
}

/// Whether [resolved] is exactly `<resolvedParent><separator><name>`.
///
/// An exact match, not a prefix test: a sibling such as `<temp>-evil` or a
/// path that merely starts with the temp path is not a child.
bool isDirectChildOf(
  String resolved,
  String resolvedParent,
  String name, {
  required String separator,
  required bool caseInsensitive,
}) {
  var parent = resolvedParent;
  if (parent.endsWith(separator)) {
    parent = parent.substring(0, parent.length - separator.length);
  }
  final expected = '$parent$separator$name';
  if (caseInsensitive) {
    return resolved.toLowerCase() == expected.toLowerCase();
  }
  return resolved == expected;
}

/// Reports whether another process holds a profile's lock.
typedef LockProbe = LockState Function(Directory profile);

/// Probes by trying to take the lock file's exclusive lock without blocking.
LockState probeLockFile(Directory profile) {
  final file = File(
    '${profile.path}${Platform.pathSeparator}$kSearchProfileLockName',
  );
  if (!file.existsSync()) return LockState.absent;
  RandomAccessFile? handle;
  try {
    handle = file.openSync(mode: FileMode.append);
    handle.lockSync(FileLock.exclusive);
    return LockState.free;
  } on FileSystemException {
    return LockState.held;
  } finally {
    try {
      handle?.closeSync();
    } on FileSystemException {
      // Nothing to release.
    }
  }
}

/// The owner of this process's throwaway profile folder.
class SearchProfileStore {
  SearchProfileStore({
    Directory? tempDir,
    int? ownPid,
    bool? caseInsensitive,
    LockProbe? lockProbe,
  }) : tempDir = tempDir ?? Directory.systemTemp,
       ownPid = ownPid ?? pid,
       caseInsensitive = caseInsensitive ?? Platform.isWindows,
       _lockProbe = lockProbe ?? probeLockFile;

  /// The OS temp directory (`%TEMP%` on Windows).
  final Directory tempDir;

  /// This process's id; names the folder and is never swept.
  final int ownPid;
  final bool caseInsensitive;
  final LockProbe _lockProbe;

  RandomAccessFile? _lock;

  /// `<temp>\dndreader-search-<pid>`.
  Directory get profileDir => Directory(
    '${tempDir.path}${Platform.pathSeparator}${profileDirName(ownPid)}',
  );

  /// Creates the folder and takes its lock. Idempotent for a live store.
  Directory create() {
    final dir = profileDir..createSync(recursive: true);
    if (_lock == null) {
      final file = File(
        '${dir.path}${Platform.pathSeparator}$kSearchProfileLockName',
      );
      final handle = file.openSync(mode: FileMode.append);
      try {
        handle.lockSync(FileLock.exclusive);
      } on FileSystemException {
        handle.closeSync();
        rethrow;
      }
      _lock = handle;
    }
    return dir;
  }

  /// Deletes stale profile folders left by earlier runs. Returns how many.
  ///
  /// Best effort and never throws: a folder that cannot be removed is left for
  /// the next launch.
  int sweepStale({DateTime? now}) {
    final clock = now ?? DateTime.now();
    final String resolvedTemp;
    try {
      resolvedTemp = tempDir.resolveSymbolicLinksSync();
    } on FileSystemException {
      return 0;
    }
    var removed = 0;
    List<FileSystemEntity> entries;
    try {
      entries = tempDir.listSync(followLinks: false);
    } on FileSystemException {
      return 0;
    }
    for (final entry in entries) {
      final name = _baseName(entry.path);
      // Cheapest and most important check first: nothing is stat'ed, resolved
      // or opened for an entry whose name is not exactly ours.
      if (!isOwnedProfileName(name)) continue;
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      String? resolved;
      var lock = LockState.held;
      var age = Duration.zero;
      if (type == FileSystemEntityType.directory) {
        try {
          resolved = Directory(entry.path).resolveSymbolicLinksSync();
          lock = _lockProbe(Directory(entry.path));
          age = clock.difference(FileStat.statSync(entry.path).modified);
        } on FileSystemException {
          continue;
        }
      }
      final verdict = decideSweep(
        name: name,
        entryType: type,
        resolvedPath: resolved,
        resolvedTempPath: resolvedTemp,
        separator: Platform.pathSeparator,
        caseInsensitive: caseInsensitive,
        ownPid: ownPid,
        lock: lock,
        age: age,
      );
      if (verdict != SweepVerdict.delete) continue;
      try {
        Directory(entry.path).deleteSync(recursive: true);
        removed++;
      } on FileSystemException {
        // In use or locked by something else; try again next launch.
      }
    }
    return removed;
  }

  /// Releases the lock and deletes this process's profile folder, retrying
  /// while WebView2's processes finish exiting. Returns whether it is gone.
  ///
  /// Only ever deletes the folder this store created, and only after
  /// re-checking that it is a direct child of the resolved temp directory.
  Future<bool> delete({
    int attempts = 10,
    Duration retryDelay = const Duration(milliseconds: 300),
  }) async {
    try {
      _lock?.closeSync();
    } on FileSystemException {
      // Already closed.
    }
    _lock = null;
    final dir = profileDir;
    for (var i = 0; i < attempts; i++) {
      if (!dir.existsSync()) return true;
      if (FileSystemEntity.typeSync(dir.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return false;
      }
      try {
        final resolved = dir.resolveSymbolicLinksSync();
        final resolvedTemp = tempDir.resolveSymbolicLinksSync();
        if (!isDirectChildOf(
          resolved,
          resolvedTemp,
          profileDirName(ownPid),
          separator: Platform.pathSeparator,
          caseInsensitive: caseInsensitive,
        )) {
          return false;
        }
        dir.deleteSync(recursive: true);
        return true;
      } on FileSystemException {
        await Future<void>.delayed(retryDelay);
      }
    }
    return !dir.existsSync();
  }

  static String _baseName(String path) {
    final cut = path.lastIndexOf(RegExp(r'[\\/]'));
    return cut < 0 ? path : path.substring(cut + 1);
  }
}

/// Removes stale profile folders left by a crashed or killed earlier run. Called
/// once from `main()` at launch, so a leftover is cleared whether or not the
/// search panel is ever used.
///
/// Windows only: the Linux browser keeps nothing under the temp directory.
///
/// The work is done in a background isolate. A leftover is hundreds of files
/// (a measured one was ~600 files / 68 MB), and deleting that on the UI isolate
/// would hold up the first frame. The guards are exactly those of
/// [SearchProfileStore.sweepStale] and [decideSweep]; nothing is relaxed here.
/// Never throws; returns how many folders were removed.
///
/// A folder with no lock file (a run that died before creating it) is left
/// until it is [kSearchProfileMinAge] old, so such a leftover goes at a later
/// launch, not necessarily the next one.
Future<int> sweepStaleProfilesAtLaunch({
  Directory? tempDir,
  int? ownPid,
  bool? enabled,
}) async {
  if (!(enabled ?? Platform.isWindows)) return 0;
  // Only plain values cross into the isolate.
  final tempPath = (tempDir ?? Directory.systemTemp).path;
  final pidValue = ownPid ?? pid;
  try {
    return await Isolate.run(
      () => SearchProfileStore(
        tempDir: Directory(tempPath),
        ownPid: pidValue,
      ).sweepStale(),
    );
  } catch (e) {
    debugPrint('[search] launch-time profile sweep failed: $e');
    return 0;
  }
}
