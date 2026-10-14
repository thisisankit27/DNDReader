#ifndef RUNNER_WINDOW_GEOMETRY_H_
#define RUNNER_WINDOW_GEOMETRY_H_

// Pure window-placement arithmetic, free of Windows headers so that it can be
// unit-tested on its own (windows/runner/test/window_geometry_test.cpp).
//
// The remembered and default sizes are *logical* pixels. They are scaled by the
// monitor's DPI to physical pixels, and that scaled size can exceed the monitor
// (the 1100x760 default is 1650x1140 physical at 150 %, taller than a 1080p
// work area). The scaled rectangle is therefore fitted to the monitor's work
// area *after* scaling.

#include <algorithm>
#include <cmath>

struct PhysicalRect {
  int left;
  int top;
  int right;
  int bottom;
};

struct WindowPlacement {
  int x;
  int y;
  int width;
  int height;
};

// Places a window of |logical_width| x |logical_height| at |logical_x|,
// |logical_y| (relative to the work area's top-left), scaled by |scale|, so
// that it lies inside |work| with at least |margin| physical pixels to spare
// on every side that it would otherwise touch or cross.
//
// The window is only ever made smaller or moved; it is never enlarged. If
// |work| is smaller than the margins allow, the result is the whole work area.
inline WindowPlacement FitToWorkArea(int logical_x, int logical_y,
                                     int logical_width, int logical_height,
                                     double scale, const PhysicalRect& work,
                                     int margin = 0) {
  const int work_width = (std::max)(1, work.right - work.left);
  const int work_height = (std::max)(1, work.bottom - work.top);
  // Leave the margins only when the work area is big enough to have them.
  const int m = (work_width > 2 * margin && work_height > 2 * margin) ? margin
                                                                      : 0;
  const int max_width = work_width - 2 * m;
  const int max_height = work_height - 2 * m;

  const int wanted_width =
      (std::max)(1, static_cast<int>(std::lround(logical_width * scale)));
  const int wanted_height =
      (std::max)(1, static_cast<int>(std::lround(logical_height * scale)));
  const int width = (std::min)(wanted_width, max_width);
  const int height = (std::min)(wanted_height, max_height);

  int x = work.left + static_cast<int>(std::lround(logical_x * scale));
  int y = work.top + static_cast<int>(std::lround(logical_y * scale));
  x = (std::min)(x, work.right - m - width);
  y = (std::min)(y, work.bottom - m - height);
  x = (std::max)(x, work.left + m);
  y = (std::max)(y, work.top + m);
  return WindowPlacement{x, y, width, height};
}

#endif  // RUNNER_WINDOW_GEOMETRY_H_
