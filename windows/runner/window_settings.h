#ifndef RUNNER_WINDOW_SETTINGS_H_
#define RUNNER_WINDOW_SETTINGS_H_

// The remembered window size, kept by the runner so no window-management
// package is needed. Sizes are logical pixels (physical / (dpi / 96)) so a
// saved size means the same thing on a monitor with a different scale.
//
// Mirrors linux/runner/my_application.cc: the same defaults and the same limits.

struct WindowSize {
  int width;
  int height;
};

constexpr int kDefaultWindowWidth = 1100;
constexpr int kDefaultWindowHeight = 760;
constexpr int kMinWindowWidth = 480;
constexpr int kMinWindowHeight = 360;
constexpr int kMaxWindowDimension = 10000;

// True when |width| x |height| is a size worth remembering or restoring.
bool IsValidWindowSize(int width, int height);

// The saved size, or the 1100x760 default if there is none or it is invalid.
WindowSize LoadWindowSize();

// Saves |width| x |height| to %APPDATA%\dndreader\window-size. A size that
// fails IsValidWindowSize is ignored. Best effort: failures are silent.
void SaveWindowSize(int width, int height);

#endif  // RUNNER_WINDOW_SETTINGS_H_
