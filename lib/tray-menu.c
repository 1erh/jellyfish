/* Place Waybar's tray menu under the icon, 8px below the bar. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <gtk/gtk.h>

static void (*real_popup_at_pointer)(GtkMenu *, const GdkEvent *);

void gtk_menu_popup_at_pointer(GtkMenu *menu, const GdkEvent *trigger_event) {
    static int guard = 0;
    GtkWidget *widget = gtk_menu_get_attach_widget(menu);

    if (!guard && widget != NULL && !GTK_IS_MENU_ITEM(widget)) {
        GtkWidget *top = gtk_widget_get_toplevel(widget);
        GdkWindow *window = top != NULL ? gtk_widget_get_window(top) : NULL;
        if (window != NULL) {
            gint x = 0, y = 0;
            GtkAllocation alloc;
            gtk_widget_get_allocation(widget, &alloc);
            if (!gtk_widget_translate_coordinates(widget, top, 0, 0, &x, &y)) {
                x = alloc.x;
                y = alloc.y;
            }
            /* South edge sits 8px under the bar, matching the other panels. */
            GdkRectangle rect = {
                x,
                y,
                alloc.width > 0 ? alloc.width : 1,
                alloc.height + 8,
            };
            guard = 1;
            gtk_menu_popup_at_rect(menu, window, &rect, GDK_GRAVITY_SOUTH_WEST,
                                   GDK_GRAVITY_NORTH_WEST, trigger_event);
            guard = 0;
            return;
        }
    }

    if (real_popup_at_pointer == NULL)
        real_popup_at_pointer = dlsym(RTLD_NEXT, "gtk_menu_popup_at_pointer");
    if (real_popup_at_pointer != NULL)
        real_popup_at_pointer(menu, trigger_event);
}
