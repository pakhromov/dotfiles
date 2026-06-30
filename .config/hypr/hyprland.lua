-- ~/.config/hypr/hyprland.lua


------------------
---- MONITORS ----
------------------

--hl.monitor({ output = "DP-2",  mode = "1920x1080@144", position = "0x0", scale = 1 })
--hl.monitor({ output = "eDP-1", disabled = true })


---------------------
---- MY PROGRAMS ----
---------------------

local terminal = "kitty"
local menu     = "fuzzel"


-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("hyprpm reload -n")
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE",    "24")
hl.env("XCURSOR_THEME",   "mycursor_LiOSV")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "mycursor_LiOSV")

-- NVIDIA Wayland
hl.env("LIBVA_DRIVER_NAME",        "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("__GL_GSYNC_ALLOWED",       "0")
hl.env("__GL_VRR_ALLOWED",         "0")


-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 0,
        gaps_out = 0,

        border_size = 0,

        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    master = {
        new_status = "master",
    },

    cursor = {
        no_hardware_cursors = true,
    },

    misc = {
        force_default_wallpaper  = 1,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        focus_on_activate        = true,
        middle_click_paste       = false,
    },

    xwayland = {
        enabled = false,
    },

    input = {
        kb_layout     = "us",
        follow_mouse  = 1,
        sensitivity   = 0,
        accel_profile = "flat",

        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { { 0.23, 1    }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear",         { type = "bezier", points = { { 0,    0    }, { 1,    1 } } })
hl.curve("almostLinear",   { type = "bezier", points = { { 0.5,  0.5  }, { 0.75, 1 } } })
hl.curve("quick",          { type = "bezier", points = { { 0.15, 0    }, { 0.1,  1 } } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })


---------------
---- INPUT ----
---------------

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })


---------------------
---- KEYBINDINGS ----
---------------------

local M = "SUPER"

-- Terminal / core
hl.bind(M .. " + T",           hl.dsp.exec_cmd(terminal))
hl.bind(M .. " + ALT + SPACE", hl.dsp.exec_cmd(terminal))
hl.bind(M .. " + X",           hl.dsp.exec_cmd("subl"))
hl.bind(M .. " + Q",           hl.dsp.window.close())
hl.bind(M .. " + D",           hl.dsp.exec_cmd(menu))
hl.bind(M .. " + P",           hl.dsp.window.pseudo())

-- Move focus
hl.bind(M .. " + ALT + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(M .. " + ALT + right", hl.dsp.focus({ direction = "right" }))
hl.bind(M .. " + ALT + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(M .. " + ALT + down",  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces / move windows to workspace
for i = 1, 10 do
    local key = i % 10
    hl.bind(M .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(M .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scroll through workspaces
hl.bind(M .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(M .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mouse
hl.bind(M .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(M .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Hyprtasking overview
hl.bind("mouse:276", function()
    hl.plugin.hyprtasking.toggle("cursor")
end)

-- Hyprtasking directional navigation
hl.bind(M .. " + left",  function() hl.plugin.hyprtasking.move("left") end)
hl.bind(M .. " + right", function() hl.plugin.hyprtasking.move("right") end)
hl.bind(M .. " + up",    function() hl.plugin.hyprtasking.move("up") end)
hl.bind(M .. " + down",  function() hl.plugin.hyprtasking.move("down") end)

-- Hyprtasking move window to adjacent workspace
hl.bind(M .. " + SHIFT + left",  function() hl.plugin.hyprtasking.movewindow("left") end)
hl.bind(M .. " + SHIFT + right", function() hl.plugin.hyprtasking.movewindow("right") end)
hl.bind(M .. " + SHIFT + up",    function() hl.plugin.hyprtasking.movewindow("up") end)
hl.bind(M .. " + SHIFT + down",  function() hl.plugin.hyprtasking.movewindow("down") end)



--hl.bind("mouse:276", function()
--    hl.plugin.hyprexpo.expo("toggle")
--end)


-- Multimedia keys
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("volume.sh up"),                                  { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("volume.sh down"),                                { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("volume.sh mute"),                                { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                 { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                 { locked = true, repeating = true })
hl.bind(M .. " + Prior",         hl.dsp.exec_cmd("brightness.sh up"))
hl.bind(M .. " + Next",          hl.dsp.exec_cmd("brightness.sh down"))

hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),        { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"),  { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"),  { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),    { locked = true })

-- System
hl.bind("CTRL + ALT + BACKSPACE", hl.dsp.exit())
hl.bind(M .. " + L",              hl.dsp.exec_cmd("hyprlock"))
hl.bind(M .. " + SHIFT + Q",      hl.dsp.exec_cmd("kitty --single-instance --class float-full power-menu.sh"))
hl.bind(M .. " + RETURN",         hl.dsp.exec_cmd("autostart -w"))
hl.bind(M .. " + SPACE",          hl.dsp.exec_cmd("keyboard-layout-switcher.sh"))

-- Browsers / apps
hl.bind(M .. " + Z",         hl.dsp.exec_cmd("firefox"))
hl.bind(M .. " + SHIFT + Z", hl.dsp.exec_cmd("firefox --private-window"))
hl.bind(M .. " + M",         hl.dsp.exec_cmd("mpv --player-operation-mode=pseudo-gui"))
hl.bind(M .. " + N",         hl.dsp.exec_cmd("kitty --single-instance --class float-full vpn-command nyaazf 'naruto|-\"kun.hu\"|(varyg dual)'"))
hl.bind(M .. " + SHIFT + W", hl.dsp.exec_cmd("iwmenu --launcher rofi"))
hl.bind(M .. " + SHIFT + D", hl.dsp.exec_cmd("hyprpicker -a"))

-- Kitty-based tools
hl.bind(M .. " + A",         hl.dsp.exec_cmd('kitty --single-instance --listen-on="unix:@mykitty" yazi'))
hl.bind(M .. " + GRAVE",     hl.dsp.exec_cmd('kitty --single-instance --listen-on="unix:@mykitty" btm'))
hl.bind(M .. " + S",         hl.dsp.exec_cmd("kitty --single-instance --class float-half audio-switch"))
hl.bind(M .. " + TAB",       hl.dsp.exec_cmd("kitty --single-instance --class float-half fsel --detach"))
hl.bind(M .. " + W",         hl.dsp.exec_cmd("kitty-launch-or-focus.sh impala"))
hl.bind(M .. " + C",         hl.dsp.exec_cmd("kitty-launch-or-focus.sh pacsea"))
hl.bind(M .. " + SHIFT + C", hl.dsp.exec_cmd("kitty-launch-or-focus.sh pacseek"))
hl.bind(M .. " + K",         hl.dsp.exec_cmd("kitty-launch-or-focus.sh nasc"))

-- Pickers / menus
hl.bind(M .. " + E",         hl.dsp.exec_cmd("emoji-picker.sh -t 'kitty --single-instance --wait-for-single-instance-window-close --class float-half'"))
hl.bind(M .. " + SHIFT + E", hl.dsp.exec_cmd("nerdfont-picker.sh -t 'kitty --single-instance --wait-for-single-instance-window-close --class float-half'"))
hl.bind(M .. " + ALT + E",   hl.dsp.exec_cmd("unicode-picker.sh -t 'kitty --single-instance --wait-for-single-instance-window-close --class float-half'"))
hl.bind(M .. " + V",         hl.dsp.exec_cmd("cclip-menu.sh -t 'kitty --single-instance --wait-for-single-instance-window-close --class float-half'"))
hl.bind(M .. " + I",         hl.dsp.exec_cmd("cclip-images.sh -t 'kitty --single-instance --wait-for-single-instance-window-close --class float-full'"))
hl.bind(M .. " + U",         hl.dsp.exec_cmd("kitty --single-instance --class float-full yzf -u"))

-- Screenshots / capture
hl.bind(M .. " + SHIFT + S",       function() hl.plugin.hyprcapture.open() end)
hl.bind(M .. " + SHIFT + A",       hl.dsp.exec_cmd("dulcepan -f png | tesseract - stdout -l swe 2>/dev/null | wl-copy"))
hl.bind(M .. " + SHIFT + ALT + A", hl.dsp.exec_cmd("ocrs.sh"))
hl.bind(M .. " + SHIFT + X",       hl.dsp.exec_cmd("wayscriber -a --no-resume-session"))

-- NOTE: these wayfire binds had no key (modifier-only) and could not be migrated:
--   SUPER + CTRL         → subl
--   SUPER + SHIFT        → kitty --single-instance --listen-on="unix:@mykitty"
--   SUPER + SHIFT + ALT  → foot
--   SUPER + ALT + CTRL   → kitty flow --restore-session


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move  = "20 monitor_h-120",
    float = true,
})

hl.window_rule({
    name  = "float-half",
    match = { class = ".*float-half.*" },
    float = true,
    move  = "25% 0%",
    size  = "50% 100%",
})

hl.window_rule({
    name  = "float-full",
    match = { class = ".*float-full.*" },
    float = true,
    move  = "0% 0%",
    size  = "100% 100%",
})


--------------------
---- PLUGINS ----
--------------------

hl.config({
    plugin = {
        hyprtasking = {
            drag_button            = 0x111,
            select_button          = 0x110,
            bg_color               = 0xff111111,
            layout                 = "grid",
            gap_size               = 4,
            border_size            = 1,
            exit_on_hovered        = false,
            warp_on_move_window    = 1,
            close_overview_on_reload = true,

            gestures = {
                enabled       = true,
                move_fingers  = 3,
                move_distance = 300,
                open_fingers  = 4,
                open_distance = 300,
                open_positive = true,
            },

            grid = {
                rows                  = 3,
                cols                  = 3,
                loop                  = false,
                layers                = 1,
                loop_layers           = true,
                gaps_use_aspect_ratio = false,
            },

            linear = {
                top          = false,
                height       = 400,
                scroll_speed = 1.0,
                blur         = false,
            },
        },
    },
})

--hl.config({
--    plugin = {
--        hyprexpo = {
--            columns = 3,
--            gaps_in = 5,
--            gaps_out = 0,
--            bg_col = "rgb(111111)",
--            workspace_method = "first 1",
--            gesture_distance = 200,
--            cancel_key = "escape",
--            show_cursor = 1,
--            keynav_enable = 0,
--        },
--    },
--})