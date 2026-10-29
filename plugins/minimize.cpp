#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>

inline HANDLE PHANDLE = nullptr;

static CFunctionHook* g_stateHook = nullptr;

using UpdateStateFn = void (*)(Desktop::View::CWindow*);

static bool takeMinimizeRequest(Desktop::View::CWindow* self, bool& xwayland) {
    xwayland = false;
    if (!self)
        return false;

    if (self->m_xdgSurface && self->m_xdgSurface->m_toplevel) {
        auto& request = self->m_xdgSurface->m_toplevel->m_state.requestsMinimize;
        if (request.has_value() && *request) {
            request.reset();
            return true;
        }
    }

    if (self->m_xwaylandSurface) {
        auto& request = self->m_xwaylandSurface->m_state.requestsMinimize;
        if (request.has_value() && *request) {
            request.reset();
            xwayland = true;
            return true;
        }
    }

    return false;
}

static void queueMinimize(Desktop::View::CWindow* self) {
    if (!self || (self->m_workspace && self->m_workspace->m_name == "special:minimized"))
        return;

    const char* home = std::getenv("HOME");
    if (!home || home[0] == '\0')
        return;

    const std::string script = std::string{home} + "/.config/hypr/scripts/window-min";
    char address[32];
    std::snprintf(address, sizeof(address), "0x%lx", static_cast<unsigned long>(reinterpret_cast<uintptr_t>(self)));

    const pid_t pid = fork();
    if (pid != 0)
        return;

    setsid();
    execl(script.c_str(), "window-min", "minimize", address, static_cast<char*>(nullptr));
    _exit(127);
}

static void onUpdateState(Desktop::View::CWindow* self) {
    bool xwayland = false;
    const bool minimize = takeMinimizeRequest(self, xwayland);
    reinterpret_cast<UpdateStateFn>(g_stateHook->m_original)(self);
    if (!minimize)
        return;
    if (xwayland && self->m_xwaylandSurface)
        self->m_xwaylandSurface->setMinimized(true);
    queueMinimize(self);
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    if (std::string{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash())
        return {"minimize", "ignored: header mismatch", "shell", "1"};

    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "onUpdateState")) {
        if (match.demangled.find("CWindow::onUpdateState") == std::string::npos)
            continue;
        g_stateHook = HyprlandAPI::createFunctionHook(handle, match.address, reinterpret_cast<void*>(onUpdateState));
        if (g_stateHook && g_stateHook->hook())
            break;
        g_stateHook = nullptr;
    }

    return {"minimize", "Hide a window when its minimize button is pressed", "shell", "1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_stateHook = nullptr;
}
