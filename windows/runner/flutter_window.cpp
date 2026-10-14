#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <cmath>
#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "window_settings.h"

namespace {
constexpr UINT_PTR kSaveSizeTimerId = 1;
constexpr UINT kSaveSizeDelayMs = 500;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "dndreader/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setFullscreen") {
          const flutter::EncodableValue* args = call.arguments();
          const bool* enable = args ? std::get_if<bool>(args) : nullptr;
          if (enable == nullptr) {
            result->Error("bad-args", "setFullscreen expects a bool");
            return;
          }
          SetFullscreen(*enable);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (HWND hwnd = GetHandle()) {
    ::KillTimer(hwnd, kSaveSizeTimerId);
  }
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Size persistence observes these messages; it never consumes them.
  switch (message) {
    case WM_SIZE:
      if (wparam != SIZE_MINIMIZED) {
        ScheduleSaveSize();
      }
      break;
    case WM_EXITSIZEMOVE:
      ScheduleSaveSize();
      break;
    case WM_TIMER:
      if (wparam == kSaveSizeTimerId) {
        ::KillTimer(hwnd, kSaveSizeTimerId);
        SaveSizeNow();
        return 0;
      }
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetFullscreen(bool enable) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || enable == fullscreen_) {
    return;
  }
  if (enable) {
    MONITORINFO monitor = {sizeof(monitor)};
    if (!::GetMonitorInfo(
            ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &monitor)) {
      return;
    }
    saved_style_ = ::GetWindowLongPtr(hwnd, GWL_STYLE);
    saved_placement_.length = sizeof(saved_placement_);
    ::GetWindowPlacement(hwnd, &saved_placement_);
    // Set first: the WM_SIZE this causes must not be saved as the window size.
    fullscreen_ = true;
    ::SetWindowLongPtr(hwnd, GWL_STYLE, saved_style_ & ~WS_OVERLAPPEDWINDOW);
    ::SetWindowPos(hwnd, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
                   monitor.rcMonitor.right - monitor.rcMonitor.left,
                   monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    fullscreen_ = false;
    ::SetWindowLongPtr(hwnd, GWL_STYLE, saved_style_);
    ::SetWindowPlacement(hwnd, &saved_placement_);
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }
  // No window-manager event will arrive, so report the change ourselves. Dart
  // only learns the state from this push.
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "fullscreenChanged",
        std::make_unique<flutter::EncodableValue>(fullscreen_));
  }
}

void FlutterWindow::ScheduleSaveSize() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  // Debounce: a drag-resize fires many messages. Setting a timer with the same
  // id restarts it.
  ::SetTimer(hwnd, kSaveSizeTimerId, kSaveSizeDelayMs, nullptr);
}

void FlutterWindow::SaveSizeNow() {
  HWND hwnd = GetHandle();
  // A maximized, minimized or full-screen window is not the size to restore to.
  if (hwnd == nullptr || fullscreen_ || ::IsZoomed(hwnd) || ::IsIconic(hwnd)) {
    return;
  }
  RECT rect;
  if (!::GetWindowRect(hwnd, &rect)) {
    return;
  }
  const double scale = ::GetDpiForWindow(hwnd) / 96.0;
  if (scale <= 0) {
    return;
  }
  SaveWindowSize(static_cast<int>(std::lround((rect.right - rect.left) / scale)),
                 static_cast<int>(std::lround((rect.bottom - rect.top) / scale)));
}
