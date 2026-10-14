// Standalone test for window_geometry.h; no framework, no Windows headers.
//   cl /EHsc /std:c++17 /I windows\runner windows\runner\test\window_geometry_test.cpp
// Exits non-zero on the first failure and prints what failed.

#include <cstdio>
#include <cstdlib>

#include "../window_geometry.h"

namespace {

int g_checks = 0;

void Check(bool ok, const char* what, int a = 0, int b = 0) {
  ++g_checks;
  if (!ok) {
    std::printf("FAIL: %s (%d, %d)\n", what, a, b);
    std::exit(1);
  }
}

constexpr int kMargin = 10;  // logical; the caller passes margin * scale

PhysicalRect Work(int w, int h, int left = 0, int top = 0) {
  return PhysicalRect{left, top, left + w, top + h};
}

bool Inside(const WindowPlacement& p, const PhysicalRect& w) {
  return p.x >= w.left && p.y >= w.top && p.x + p.width <= w.right &&
         p.y + p.height <= w.bottom && p.width > 0 && p.height > 0;
}

}  // namespace

int main() {
  // 100 %: the default fits and keeps its logical position.
  {
    const auto p = FitToWorkArea(10, 10, 1100, 760, 1.0, Work(1920, 1040), 10);
    Check(p.width == 1100 && p.height == 760, "100% size unchanged");
    Check(p.x == 10 && p.y == 10, "100% position unchanged");
  }
  // 150 % on 1080p (work area 1034 tall): the reported bug. 1140 -> fits.
  {
    const auto w = Work(1920, 1034);
    const auto p = FitToWorkArea(10, 10, 1100, 760, 1.5, w, 15);
    Check(p.width == 1650, "150% width kept", p.width);
    Check(p.height == 1034 - 30, "150% height clamped to work area", p.height);
    Check(Inside(p, w), "150% inside work area");
    Check(p.y == 15, "150% keeps its position when it then fits", p.y);
  }
  // 200 % on a small 1366x768 laptop: both dimensions clamp.
  {
    const auto w = Work(1366, 728);
    const auto p = FitToWorkArea(10, 10, 1100, 760, 2.0, w, 20);
    Check(p.width == 1366 - 40 && p.height == 728 - 40, "200% both clamped");
    Check(Inside(p, w), "200% inside");
  }
  // Taskbar on top: the work area does not start at 0.
  {
    const auto w = Work(1920, 1040, 0, 40);
    const auto p = FitToWorkArea(10, 10, 1100, 760, 1.0, w, 10);
    Check(p.y >= 40, "respects work-area top", p.y);
    Check(Inside(p, w), "top taskbar inside");
  }
  // A second monitor to the left (negative coordinates).
  {
    const auto w = Work(1920, 1040, -1920, 0);
    const auto p = FitToWorkArea(10, 10, 1100, 760, 1.0, w, 10);
    Check(Inside(p, w), "left monitor inside");
    Check(p.x >= -1920, "left monitor x", p.x);
  }
  // A saved size larger than the screen (moved from a bigger monitor).
  {
    const auto w = Work(1366, 728);
    const auto p = FitToWorkArea(10, 10, 3000, 2000, 1.0, w, 10);
    Check(p.width == 1346 && p.height == 708, "oversized saved size clamped");
  }
  // Never enlarged: a small window stays small.
  {
    const auto p = FitToWorkArea(10, 10, 500, 400, 1.0, Work(3840, 2120), 10);
    Check(p.width == 500 && p.height == 400, "small window not enlarged");
  }
  // A position that would put the window off the bottom/right is pulled in.
  {
    const auto w = Work(1000, 800);
    const auto p = FitToWorkArea(900, 700, 400, 300, 1.0, w, 0);
    Check(p.x == 600 && p.y == 500, "far position pulled inside", p.x, p.y);
  }
  // A work area too small for the margins: use the whole area, never negative.
  {
    const auto w = Work(15, 15);
    const auto p = FitToWorkArea(10, 10, 1100, 760, 1.0, w, 10);
    Check(p.width == 15 && p.height == 15 && p.x == 0 && p.y == 0,
          "tiny work area", p.width, p.height);
  }
  // Property sweep: every scale x screen x size lands inside the work area.
  {
    const double scales[] = {1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0};
    const int screens[][2] = {{1280, 720},  {1366, 728},  {1536, 824},
                              {1920, 1040}, {2560, 1400}, {3840, 2120}};
    const int sizes[][2] = {{1100, 760}, {480, 360}, {3000, 2000}, {10000, 10000}};
    for (double s : scales) {
      for (const auto& sc : screens) {
        for (const auto& sz : sizes) {
          const auto w = Work(sc[0], sc[1]);
          const int margin = static_cast<int>(10 * s);
          const auto p = FitToWorkArea(10, 10, sz[0], sz[1], s, w, margin);
          Check(Inside(p, w), "sweep inside work area", sc[0], sz[0]);
        }
      }
    }
  }
  std::printf("window_geometry_test: %d checks passed\n", g_checks);
  return 0;
}
