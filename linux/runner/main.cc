#include <stdlib.h>

#include <webview_cef/webview_cef_plugin.h>
#include "my_application.h"

int main(int argc, char** argv) {
  // GDK's Wayland backend falls back to reading org.gnome.settings-daemon.
  // plugins.xsettings directly via GSettings when it doesn't use the
  // org.freedesktop.portal.Settings portal, and that fallback (gdk/wayland/
  // gdkscreen-wayland.c, update_xft_settings()) reads the antialiasing,
  // hinting and rgba-order keys unconditionally. GNOME 50's
  // gnome-settings-daemon moved those keys to a differently-named sibling
  // schema (org.gnome.settings-daemon.plugins.xsettings.deprecated), so the
  // schema GDK looks up still exists but no longer has the keys, and GLib
  // treats that as a fatal error: the process aborts before any window opens.
  // This is an unfixed GTK3 bug (filed 2021, still open upstream:
  // https://gitlab.gnome.org/GNOME/gtk/-/issues/3680), not something in this
  // app's own code. Preferring the portal avoids the broken fallback
  // entirely, and is read once by GDK before anything else runs, so this must
  // be set before any GTK/GDK call. The "0" means an operator's own
  // GTK_USE_PORTAL is never overridden.
  setenv("GTK_USE_PORTAL", "1", 0);

  int exit_code = initCEFProcesses(argc, argv);
  if (exit_code >= 0) {
    return exit_code;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
