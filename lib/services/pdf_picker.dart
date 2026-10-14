import 'package:file_picker/file_picker.dart';

/// Asks the user for a PDF and returns its path, or null if they cancelled.
typedef PdfPicker = Future<String?> Function();

/// Default picker: the native file chooser (the XDG desktop portal on Linux, the Windows common dialog on Windows).
Future<String?> pickPdfPath() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Open PDF',
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  return file?.path;
}
