import 'dart:io' show Platform;

/// How the search panel is presented over the document.
enum SearchPresentation {
  /// A 420–480 px panel docked to the right edge (desktop, and tablets/foldables).
  sidePanel,

  /// A draggable bottom sheet on a phone-width window, the side panel above [sheetBreakpoint].
  adaptive;

  /// Below this width (dp) a side panel cannot fit beside a readable page, so the sheet is used.
  static const double sheetBreakpoint = 600;

  /// The presentation for this platform: adaptive on Android, the side panel everywhere else.
  static SearchPresentation forPlatform() =>
      Platform.isAndroid ? adaptive : sidePanel;

  /// Whether a window [width] dp wide shows the bottom sheet.
  bool usesSheet(double width) => this == adaptive && width < sheetBreakpoint;
}
