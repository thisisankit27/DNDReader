#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // "dndreader/window": setFullscreen(bool) from Dart, fullscreenChanged(bool)
  // to Dart. Same contract as linux/runner/my_application.cc.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // "dndreader/lifecycle": prepareToClose() to Dart. The close is deferred
  // until Dart has finished its clean-up (the search profile), or a native
  // timeout elapses, so that the WebView2 environment is torn down while the
  // engine is still alive instead of during OnDestroy().
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      lifecycle_channel_;
  bool close_requested_ = false;  // prepareToClose is in flight
  bool close_allowed_ = false;    // clean-up finished; let WM_CLOSE through
  void BeginPrepareToClose(HWND hwnd);
  void FinishPrepareToClose();

  // Windows has no fullscreen window state to observe, so it is emulated: the
  // style and placement are saved, the frame is stripped and the window sized
  // to its monitor, and fullscreenChanged is sent from here.
  void SetFullscreen(bool enable);
  bool fullscreen_ = false;
  LONG_PTR saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_ = {};

  // Window-size persistence, debounced by 500 ms like the Linux runner.
  void ScheduleSaveSize();
  void SaveSizeNow();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
