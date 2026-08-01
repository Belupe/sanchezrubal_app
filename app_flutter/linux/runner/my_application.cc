#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // INSTANCIA ÚNICA. Si ya hay una ventana (nos han vuelto a lanzar, por
  // ejemplo al pulsar un enlace portalfamilia:// del correo), la traemos al
  // frente y salimos en vez de abrir una segunda ventana. Tiene que ir ANTES
  // de gtk_application_window_new: al revés se crearía y se fugaría una
  // ventana en cada enlace.
  GList* ventanas = gtk_application_get_windows(GTK_APPLICATION(application));
  if (ventanas != nullptr) {
    gtk_window_present(GTK_WINDOW(ventanas->data));
    return;
  }

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
    gtk_header_bar_set_title(header_bar, "Portal Familia");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Portal Familia");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
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

// Implements GApplication::command_line.
//
// Con G_APPLICATION_HANDLES_COMMAND_LINE, GApplication emite "command-line"
// en la instancia PRIMARIA, tanto al arrancar como cada vez que una instancia
// secundaria le reenvía sus argumentos (el escritorio lanza el binario otra vez
// al abrir un enlace portalfamilia://). El plugin `gtk` está enganchado a esa
// misma señal y es por donde app_links entrega el enlace a Dart.
static int my_application_command_line(GApplication* application,
                                       GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);

  // Los argumentos llegan a Dart como los de main(List<String> args): es la
  // vía del arranque EN FRÍO, porque en ese momento el plugin `gtk` todavía no
  // existe (se registra al crear la vista, más abajo en activate) y por tanto
  // no puede haber escuchado esta primera emisión.
  gchar** argumentos =
      g_application_command_line_get_arguments(command_line, nullptr);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  // Se descarta el primero, que es el nombre del binario.
  self->dart_entrypoint_arguments = g_strdupv(argumentos + 1);
  g_strfreev(argumentos);

  g_application_activate(application);
  return 0;
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // Ya hay otra instancia corriendo: le pedimos que se ponga delante ANTES de
  // reenviarle los argumentos, porque el reenvío por sí solo no levanta la
  // ventana (la señal "command-line" la consume el plugin `gtk`).
  if (g_application_get_is_remote(application)) {
    g_application_activate(application);
  }

  // FALSE = que GApplication haga su trabajo normal: en la instancia primaria
  // emite "command-line", y en una secundaria reenvía los argumentos a la
  // primaria por D-Bus y sale.
  return FALSE;
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
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
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

  // NO se usa G_APPLICATION_NON_UNIQUE a propósito: la app es de INSTANCIA
  // ÚNICA para que los enlaces portalfamilia:// del correo lleguen a la
  // ventana que ya está abierta (GApplication reenvía los argumentos por
  // D-Bus y emite "command-line" en la primaria, que es lo que escucha
  // app_links). HANDLES_OPEN cubre además a los escritorios que en vez de
  // pasar el URI como argumento lo entregan por la señal "open".
  //
  // Efecto secundario al desarrollar: `flutter run -d linux` con otra
  // instancia ya abierta cederá el control a esa y saldrá enseguida. Es lo
  // esperado; cierra la instancia anterior antes de relanzar.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE |
                                         G_APPLICATION_HANDLES_OPEN,
                                     nullptr));
}
