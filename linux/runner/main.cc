#include <gio/gio.h>
#include <stdlib.h>

#include <webview_cef/webview_cef_plugin.h>
#include "my_application.h"

// Whether GDK's Wayland xsettings fallback (gdk/wayland/gdkscreen-wayland.c,
// update_xft_settings()) would abort on this system: the
// org.gnome.settings-daemon.plugins.xsettings schema exists — its only guard
// — but no longer has the "antialiasing" key GLib's g_settings_get_enum()
// reads unconditionally. GNOME 50's gnome-settings-daemon moved that key
// (with "hinting" and "rgba-order") to a separate
// org.gnome.settings-daemon.plugins.xsettings.deprecated schema id GDK never
// looks at. Filed 2021, still open upstream:
// https://gitlab.gnome.org/GNOME/gtk/-/issues/3680.
//
// Deliberately narrow: this checks only what the GLib schema on this system
// actually has, not whether GDK will end up on its Wayland backend at all
// (the only backend with this bug — X11's gdkscreen-x11.c reads real
// XSETTINGS and never hits this). A system whose gnome-settings-daemon
// package has already dropped the key but that happens to run under X11 will
// still get GTK_USE_PORTAL set below, unnecessarily (see main()) — narrowing
// that further would mean independently replicating GDK's own backend
// selection, which could not be verified against GTK's actual source here.
static gboolean xsettings_schema_is_missing_antialiasing_key(void) {
  GSettingsSchemaSource* source = g_settings_schema_source_get_default();
  if (source == nullptr) return FALSE;
  g_autoptr(GSettingsSchema) schema = g_settings_schema_source_lookup(
      source, "org.gnome.settings-daemon.plugins.xsettings", TRUE);
  if (schema == nullptr) return FALSE;
  return !g_settings_schema_has_key(schema, "antialiasing");
}

int main(int argc, char** argv) {
  // GTK_USE_PORTAL also changes which dialogs (file chooser, print, app
  // chooser) are routed through the desktop portal, so it is only set when
  // the broken condition above is actually present — never unconditionally.
  // Setting it where nothing is broken has two real costs: on X11 (see the
  // comment above) it is pure unnecessary scope; and on a system with no
  // portal implementation reachable at all, forcing GDK to try one for
  // *anything* can make launch itself slow to the point of looking hung —
  // https://github.com/flutter/flutter/issues/180143 is exactly that,
  // independently reported against a Flutter app on a portal-less compositor.
  // Must run before any GTK/GDK call: gdk_should_use_portal() caches
  // GTK_USE_PORTAL the first time anything reads it. The "0" means an
  // operator's own GTK_USE_PORTAL is never overridden.
  if (xsettings_schema_is_missing_antialiasing_key()) {
    setenv("GTK_USE_PORTAL", "1", 0);
  }

  int exit_code = initCEFProcesses(argc, argv);
  if (exit_code >= 0) {
    return exit_code;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
