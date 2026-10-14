#include "window_settings.h"

#include <knownfolders.h>
#include <shlobj.h>
#include <windows.h>

#include <filesystem>
#include <fstream>
#include <string>

namespace {

// %APPDATA%\dndreader\window-size, or an empty path if APPDATA is unavailable.
std::filesystem::path SettingsPath() {
  PWSTR roaming = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr,
                                    &roaming))) {
    return std::filesystem::path();
  }
  std::filesystem::path path(roaming);
  ::CoTaskMemFree(roaming);
  return path / L"dndreader" / L"window-size";
}

}  // namespace

bool IsValidWindowSize(int width, int height) {
  return width >= kMinWindowWidth && width <= kMaxWindowDimension &&
         height >= kMinWindowHeight && height <= kMaxWindowDimension;
}

WindowSize LoadWindowSize() {
  const WindowSize fallback{kDefaultWindowWidth, kDefaultWindowHeight};
  const std::filesystem::path path = SettingsPath();
  if (path.empty()) {
    return fallback;
  }
  std::ifstream file(path);
  int width = 0;
  int height = 0;
  // Reject anything that is not two sane integers.
  if (!(file >> width >> height) || !IsValidWindowSize(width, height)) {
    return fallback;
  }
  return WindowSize{width, height};
}

void SaveWindowSize(int width, int height) {
  if (!IsValidWindowSize(width, height)) {
    return;
  }
  const std::filesystem::path path = SettingsPath();
  if (path.empty()) {
    return;
  }
  std::error_code error;
  std::filesystem::create_directories(path.parent_path(), error);
  if (error) {
    return;
  }
  std::ofstream file(path, std::ios::trunc);
  file << width << ' ' << height << '\n';
}
