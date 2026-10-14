import 'dart:io' show Platform;

/// The last segment of [path], for showing a document's name.
///
/// On Windows both `\` and `/` separate segments: a path can arrive with
/// either (a command-line argument, a recent entry written by another tool), and
/// splitting on one would show the whole path as the "name". Elsewhere only `/`
/// does, because a backslash is a legal filename character there.
String baseName(String path, {bool? windows}) {
  final isWindows = windows ?? Platform.isWindows;
  var end = path.length;
  bool isSeparator(String c) => c == '/' || (isWindows && c == r'\');
  // Ignore trailing separators ("C:\docs\" → "docs").
  while (end > 0 && isSeparator(path[end - 1])) {
    end--;
  }
  var start = end;
  while (start > 0 && !isSeparator(path[start - 1])) {
    start--;
  }
  final name = path.substring(start, end);
  return name.isEmpty ? path : name;
}
