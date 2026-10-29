-- Minimal Hyprland shell.
-- Win opens the launcher. Super+/ lists keys.

local terminal = "ghostty"
local files = "dolphin"
local browser = "zen-browser"
local launcher_qs = "qs -p " .. os.getenv("HOME") .. "/.config/hypr/launcher"
local launcher = launcher_qs .. " ipc call launcher toggle"
local shell = os.getenv("HOME") .. "/.config/hypr/scripts/shell"

-- 配置は nwg-displays（Super+P）が monitors.lua / workspaces.lua に書く。
require("monitors")
require("workspaces")

hl.env("XCURSOR_THEME", "breeze_cursors")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "breeze_cursors")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GTK_IM_MODULE", "fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("LC_TIME", "ja_JP.UTF-8")
hl.env("FONTCONFIG_FILE", os.getenv("HOME") .. "/.config/fontconfig/udev.conf")

hl.config({
    general = {
        gaps_in = 6,
        gaps_out = 8,
        border_size = 1,
        col = {
            active_border = "rgba(e6e1d6ee)",
            inactive_border = "rgba(e6e1d622)",
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
        snap = { enabled = false },
    },
    decoration = {
        rounding = 0,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        shadow = { enabled = false },
        dim_strength = 0.42,
        blur = {
            enabled = true,
            size = 10,
            passes = 3,
            noise = 0.02,
            brightness = 0.82,
            contrast = 1.15,
            vibrancy = 0.18,
            new_optimizations = true,
            popups = false,
            input_methods = false,
        },
    },
    animations = { enabled = true },
    dwindle = {
        preserve_split = true,
        smart_split = false,
        smart_resizing = true,
        precise_mouse_move = true,
        -- 横長なら左右半分、縦長なら上下半分。半分にするたびに向きが入れ替わる。
        split_width_multiplier = 1.0,
        default_split_ratio = 1.0,
        special_scale_factor = 0.9,
    },
    input = {
        kb_layout = "jp",
        repeat_rate = 35,
        repeat_delay = 250,
        numlock_by_default = true,
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = { natural_scroll = false },
    },
    misc = {
        disable_hyprland_logo = true,
        allow_session_lock_restore = true,
        force_default_wallpaper = 0,
        background_color = "rgb(0c0b0a)",
        font_family = "UDEV Gothic",
        focus_on_activate = true,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        mouse_move_focuses_monitor = true,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = true,
        enable_swallow = true,
        swallow_regex = "^(com\\.mitchellh\\.ghostty)$",
        close_special_on_empty = true,
    },
    binds = {
        workspace_back_and_forth = true,
        window_direction_monitor_fallback = true,
    },
})

hl.curve("move", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.animation({ leaf = "global", enabled = false })
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "move" })
hl.animation({ leaf = "windowsIn", enabled = false })
hl.animation({ leaf = "windowsOut", enabled = false })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "move" })
hl.animation({ leaf = "fade", enabled = false })
hl.animation({ leaf = "layers", enabled = false })
hl.animation({ leaf = "border", enabled = false })
hl.animation({ leaf = "workspaces", enabled = false })
hl.animation({ leaf = "zoomFactor", enabled = false })

hl.layer_rule({
    name = "launcher",
    match = { namespace = "^(launcher|power-menu|user-switch|wallpaper-picker|auth|panel|workspaces)$" },
    blur = true,
    ignore_alpha = 0.12,
})

hl.layer_rule({
    name = "notifications",
    match = { namespace = "^(swaync-control-center|swaync-notification-window)$" },
    blur = true,
    ignore_alpha = 0.3,
})

hl.permission("/usr/bin/grim", "screencopy", "allow")
hl.permission("/usr/bin/slurp", "screencopy", "allow")
hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")

local minimize_plugin = os.getenv("HOME") .. "/.config/hypr/plugins/minimize.so"

local function ensure_minimize()
    local ok, loaded = pcall(hl.get_loaded_plugins)
    if ok and type(loaded) == "table" then
        for _, plugin in ipairs(loaded) do
            if plugin.name == "minimize" then
                return
            end
        end
    end
    --.plugin.load(minimize_plugin)
end

-- Reload does not re-run hyprland.start, and a missing plugin leaves Zen's
-- minimize button doing nothing.
ensure_minimize()

hl.on("hyprland.start", function()
    ensure_minimize()
    -- tty1 autologin has no display manager, so hyprlock is the login screen.
    hl.exec_cmd("hyprlock")
    hl.exec_cmd("fcitx5 -d --replace")
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/bar")
    hl.exec_cmd(launcher_qs .. " -n -d")
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/workspace-watch")
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/bt-agent")
    hl.exec_cmd("swaync")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE GTK_IM_MODULE QT_IM_MODULE XMODIFIERS SDL_IM_MODULE FONTCONFIG_FILE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE GTK_IM_MODULE QT_IM_MODULE XMODIFIERS FONTCONFIG_FILE")
end)

local main = "SUPER"

-- 画面ごとに 1..9。内蔵パネル（eDP- / LVDS- / DSI-）があるときはそれが先頭で、
-- ワークスペース 1 以降は内蔵側。内蔵がなければ外部出力が先頭。
local ws_span = 10
local ws_pinned = 5

local function internal_output(name)
    return name:find("^eDP%-") ~= nil or name:find("^LVDS%-") ~= nil or name:find("^DSI%-") ~= nil
end

local function monitor_slot(name)
    local names = {}
    for _, m in ipairs(hl.get_monitors()) do
        names[#names + 1] = m.name
    end
    table.sort(names, function(a, b)
        local ia = internal_output(a) and 0 or 1
        local ib = internal_output(b) and 0 or 1
        if ia ~= ib then
            return ia < ib
        end
        return a < b
    end)
    for i, n in ipairs(names) do
        if n == name then
            return i - 1
        end
    end
    return 0
end

local function pin_monitor(monitor)
    if monitor == nil or monitor.name == nil or monitor.name == "" then
        return
    end
    local slot = monitor_slot(monitor.name)
    for i = 1, 9 do
        hl.workspace_rule({
            workspace = tostring(slot * ws_span + i),
            monitor = monitor.name,
            persistent = i <= ws_pinned,
        })
    end
end

local function pin_monitors()
    local ok, monitors = pcall(hl.get_monitors)
    if not ok or type(monitors) ~= "table" then
        return
    end
    for _, monitor in ipairs(monitors) do
        pin_monitor(monitor)
    end
end

pin_monitors()

-- One bar per connected monitor; scripts/bar rewrites the Waybar config and restarts it.
local function refresh_bars()
    hl.timer(function()
        hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/bar")
    end, { timeout = 500, type = "oneshot" })
end

hl.on("monitor.added", function()
    pin_monitors()
    refresh_bars()
end)
hl.on("monitor.removed", refresh_bars)
hl.timer(pin_monitors, { timeout = 200, type = "oneshot" })

local function workspace_on_active(index)
    local monitor = hl.get_active_monitor()
    if not monitor then
        return
    end
    return tostring(monitor_slot(monitor.name) * ws_span + index)
end

hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd(launcher), { release = true })

hl.bind(main .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(main .. " + Q", hl.dsp.window.close())
hl.bind(main .. " + D", hl.dsp.exec_cmd(launcher))
hl.bind(main .. " + E", hl.dsp.exec_cmd(files))
hl.bind(main .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(main .. " + F", hl.dsp.window.fullscreen())
hl.bind(main .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(main .. " + V", hl.dsp.exec_cmd(shell .. " clip"))
hl.bind(main .. " + L", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/lock"))
hl.bind(main .. " + M", hl.dsp.exec_cmd(launcher_qs .. " ipc call power toggle"))
hl.bind(main .. " + W", hl.dsp.exec_cmd(launcher_qs .. " ipc call wallpaper pick"))
hl.bind(main .. " + N", hl.dsp.exec_cmd("swaync-client -t -sw"))
hl.bind(main .. " + SHIFT + N", hl.dsp.exec_cmd("swaync-client -d -sw"))
hl.bind(main .. " + P", hl.dsp.exec_cmd("nwg-displays"))
hl.bind(main .. " + slash", hl.dsp.exec_cmd(shell .. " keys"))
hl.bind(main .. " + S", hl.dsp.workspace.toggle_special("scratch"))
hl.bind(main .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:scratch" }))
hl.bind("Print", hl.dsp.exec_cmd(shell .. " shot"))
hl.bind(main .. " + SHIFT + Print", hl.dsp.exec_cmd(shell .. " shot region"))
hl.bind(main .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))
hl.bind(main .. " + Tab", hl.dsp.exec_cmd(launcher_qs .. " ipc call workspaces toggle"))

hl.bind(main .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(main .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(main .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(main .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(main .. " + J", hl.dsp.layout("togglesplit"))

local winmin = os.getenv("HOME") .. "/.config/hypr/scripts/window-min"
hl.bind(main .. " + Z", hl.dsp.exec_cmd(winmin .. " minimize"))
hl.bind(main .. " + SHIFT + Z", hl.dsp.exec_cmd(winmin .. " restore-last"))

hl.bind(main .. " + ALT + left", hl.dsp.focus({ monitor = "left" }))
hl.bind(main .. " + ALT + right", hl.dsp.focus({ monitor = "right" }))
hl.bind(main .. " + ALT + SHIFT + left", hl.dsp.window.move({ monitor = "left" }))
hl.bind(main .. " + ALT + SHIFT + right", hl.dsp.window.move({ monitor = "right" }))

-- Swap with the neighbour in that direction. On the screen edge that does nothing,
-- so continue onto the monitor in the same direction.
local function move_window(direction)
    return function()
        local win = hl.get_active_window()
        if not win then
            return
        end
        local address = win.address
        local before_ws = win.workspace and win.workspace.id
        local before_at = win.at
        hl.dispatch(hl.dsp.window.move({ direction = direction }))
        win = hl.get_active_window()
        if not win or win.address ~= address or (win.workspace and win.workspace.id) ~= before_ws then
            return
        end
        local after_at = win.at
        local function xy(at)
            if type(at) ~= "table" then
                return tostring(at), ""
            end
            return tostring(at.x or at[1]), tostring(at.y or at[2])
        end
        local bx, by = xy(before_at)
        local ax, ay = xy(after_at)
        if ax == bx and ay == by then
            hl.dispatch(hl.dsp.window.move({ monitor = direction }))
        end
    end
end

local move_keys = { dont_inhibit = true }
hl.bind(main .. " + SHIFT + left", move_window("left"), move_keys)
hl.bind(main .. " + SHIFT + right", move_window("right"), move_keys)
hl.bind(main .. " + SHIFT + up", move_window("up"), move_keys)
hl.bind(main .. " + SHIFT + down", move_window("down"), move_keys)

for i = 1, 9 do
    hl.bind(main .. " + " .. i, function()
        local id = workspace_on_active(i)
        if id then
            hl.dispatch(hl.dsp.focus({ workspace = id }))
        end
    end)
    hl.bind(main .. " + SHIFT + " .. i, function()
        local id = workspace_on_active(i)
        if id then
            hl.dispatch(hl.dsp.window.move({ workspace = id }))
        end
    end)
end

hl.bind(main .. " + mouse_down", hl.dsp.focus({ workspace = "r+1" }))
hl.bind(main .. " + mouse_up", hl.dsp.focus({ workspace = "r-1" }))
hl.bind(main .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(main .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(shell .. " volume up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(shell .. " volume down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(shell .. " volume mute"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "float-polkit",
    match = { class = "org.kde.polkit-kde-authentication-agent-1" },
    float = true,
    center = true,
})

hl.window_rule({
    name = "float-bar-tools",
    match = { class = "^bar-(network|bluetooth)$" },
    float = true,
    center = true,
    size = "760 520",
})

hl.window_rule({
    name = "float-picture-in-picture",
    match = { title = "^Picture-in-Picture$" },
    float = true,
    pin = true,
    size = "480 270",
    move = "monitor_w-500 36",
})
