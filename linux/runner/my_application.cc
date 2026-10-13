#include "my_application.h"

#include <stdio.h>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include <webview_cef/webview_cef_plugin.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ---- Window size persistence -------------------------------------------------
// The size is remembered in $XDG_CONFIG_HOME/dndreader/window-size ("W H").
// Kept in the runner so no window-management package is needed.
static const int kDefaultWidth = 1100;
static const int kDefaultHeight = 760;
static guint window_size_save_timer = 0;

static gchar* window_size_path() {
  return g_build_filename(g_get_user_config_dir(), "dndreader", "window-size",
                          nullptr);
}

static void load_window_size(int* width, int* height) {
  *width = kDefaultWidth;
  *height = kDefaultHeight;
  g_autofree gchar* path = window_size_path();
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(path, &contents, nullptr, nullptr)) return;
  int w = 0, h = 0;
  // Reject anything that is not two sane integers.
  if (sscanf(contents, "%d %d", &w, &h) == 2 && w >= 480 && w <= 10000 &&
      h >= 360 && h <= 10000) {
    *width = w;
    *height = h;
  }
}

static gboolean save_window_size_cb(gpointer data) {
  GtkWindow* window = GTK_WINDOW(data);
  window_size_save_timer = 0;
  if (gtk_window_is_maximized(window)) return G_SOURCE_REMOVE;
  int w = 0, h = 0;
  gtk_window_get_size(window, &w, &h);
  if (w < 480 || h < 360) return G_SOURCE_REMOVE;
  g_autofree gchar* path = window_size_path();
  g_autofree gchar* dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0700);
  g_autofree gchar* text = g_strdup_printf("%d %d\n", w, h);
  g_file_set_contents(path, text, -1, nullptr);
  return G_SOURCE_REMOVE;
}

static gboolean window_configure_cb(GtkWidget* widget, GdkEventConfigure*,
                                    gpointer) {
  // Debounce: a drag-resize fires many events.
  if (window_size_save_timer != 0) g_source_remove(window_size_save_timer);
  window_size_save_timer = g_timeout_add(500, save_window_size_cb, widget);
  return FALSE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "DNDReader");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "DNDReader");
  }

  int width = kDefaultWidth, height = kDefaultHeight;
  load_window_size(&width, &height);
  gtk_window_set_default_size(window, width, height);
  g_signal_connect(window, "configure-event",
                   G_CALLBACK(window_configure_cb), nullptr);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  g_signal_connect(view, "key_press_event", G_CALLBACK(processKeyEventForCEF), nullptr);
  g_signal_connect(view, "key_release_event", G_CALLBACK(processKeyEventForCEF), nullptr);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
