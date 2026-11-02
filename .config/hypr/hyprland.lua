--------------
---- DBUS ----
--------------

local function update_dbus_environment()
    os.execute("dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE DISPLAY XDG_RUNTIME_DIR XDG_SESSION_DESKTOP")
end

-- A bus belongs to its login session. Reusing one from a previous login races
-- that login's cleanup, which will kill it even after a new compositor adopts it.
do
    local function shell_quote(value)
        return "'" .. value:gsub("'", "'\\''") .. "'"
    end

    local function bus_alive(address)
        if not address or address == "" then return false end
        -- Hyprland uses SA_NOCLDWAIT: os.execute()/pclose() cannot reliably
        -- report child exit status. Have the shell report success over stdout.
        local probe = assert(io.popen(
            "dbus-send --bus=" .. shell_quote(address)
            .. " --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus"
            .. " org.freedesktop.DBus.GetId >/dev/null 2>&1 && printf 'ready\\n'", "r"
        ))
        local ready = probe:read("*l")
        probe:close()
        return ready == "ready"
    end

    local runtime_dir = assert(os.getenv("XDG_RUNTIME_DIR"), "XDG_RUNTIME_DIR is not set")
    local session_id = assert(os.getenv("XDG_SESSION_ID"), "XDG_SESSION_ID is not set")
    local env_path = runtime_dir .. "/hyprland-dbus-" .. session_id .. ".env"
    local address
    local saved = io.open(env_path, "r")
    if saved then
        address = saved:read("*l")
        saved:close()
    end

    local started = false
    if not bus_alive(address) then
        -- Restore normal signal handling and unblock inherited compositor
        -- signals before daemonizing. This affects only the child process.
        local daemon = assert(io.popen(
            "env --default-signal dbus-daemon --session --fork --syslog-only --print-address=1 --print-pid=1", "r"
        ))
        local output = daemon:read("*a")
        daemon:close()
        address = output:match("^([^\r\n]+)\n%d+")
        assert(address, "Failed to start the D-Bus session bus")
        local file = assert(io.open(env_path, "w"))
        assert(file:write(output))
        assert(file:close())
        started = true
    end

    hl.env("DBUS_SESSION_BUS_ADDRESS", address)
    -- A config reload can replace a dead bus while the compositor is already
    -- running. Publish its existing display environment to that new bus too.
    if started and os.getenv("WAYLAND_DISPLAY") then
        update_dbus_environment()
    end
end


------------------
---- MONITORS ----
------------------

hl.monitor({ output = "DP-2",  mode = "1920x1080@144", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-1", disabled = true })
--hl.monitor({ output = "eDP-1",  mode = "1920x1080@144", position = "0x1080", scale = 1})


--------------------
---- WORKSPACES ----
--------------------

-- wayfire.ini had vwidth/vheight = 3, i.e. a fixed 3x3 grid addressed as "RC"
-- (row, column, 1-based). Hyprland workspaces are plain integers, and
-- hyprtasking's grid assigns slots dynamically (grid.cpp refresh_workspace_cache:
-- workspace rules sorted by id first, then live workspaces sorted by id, each
-- taking the next free slot in y-major order). Declaring all 9 as persistent
-- pins that mapping so it cannot drift as workspaces come and go:
--
--     workspace N  ->  x = (N-1) % 3, y = (N-1) / 3
--     wayfire RC   ->  N = (R-1)*3 + C
--
--     11=1  12=2  13=3
--     21=4  22=5  23=6
--     31=7  32=8  33=9
for i = 1, 9 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true, monitor = "DP-2" })
end


--------------------------
---- DETACHED SPAWNS ----
--------------------------

-- Every process hyprland starts is normally a direct child of the compositor,
-- while anything whose parent exits (sublime forks itself; rofi exits after
-- launching) gets reparented to PID 1. Detach everything so the tree is
-- uniform: all spawned apps land under init.
--
-- The whole command goes to `sh -c` INSIDE setsid. Prefixing `setsid -f` alone
-- would not work: hyprland already runs the string via /bin/sh -c, so in
-- "setsid -f a && b" the && binds at the outer shell and only `a` gets detached.
--
-- Window rules are unaffected. Exec rules match the inherited HL_EXEC_RULE_TOKEN
-- environment variable (WindowRule.cpp:461), not the pid, and env survives the
-- fork - verified: a setsid-detached window still honoured its exec workspace.
local function detach(cmd)
    return "setsid -f sh -c '" .. cmd:gsub("'", "'\\''") .. "'"
end

local _dsp_exec_cmd = hl.dsp.exec_cmd
hl.dsp.exec_cmd = function(cmd, rules)
    return _dsp_exec_cmd(detach(cmd), rules)
end

local _exec_cmd = hl.exec_cmd
hl.exec_cmd = function(cmd)
    return _exec_cmd(detach(cmd))
end


-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    -- Publish the display environment before other startup commands can ask
    -- D-Bus to activate applications. This updates D-Bus directly.
    update_dbus_environment()

    -- Plugins load AFTER the config has been parsed, so the plugin.* keys in
    -- hl.config() below are unknown at parse time and Hyprland raises the error
    -- overlay ("unknown config key 'plugin.hyprtasking.*'"). The plugin works
    -- regardless - it registers its keys on load - but the overlay keeps showing
    -- the stale parse errors. Chain the loads and a reload in one shell command:
    -- `hyprctl plugin load` is synchronous, so && guarantees the reload happens
    -- once both plugins have registered their config keys, which re-parses
    -- cleanly and clears the overlay. hyprland.start does not re-fire on reload,
    -- so this cannot loop.
    -- hyprland already execs via /bin/sh -c, so && works directly.
    -- The eDP-1 dance runs after the reload so nothing re-parses over it.

    --hl.exec_cmd("hyprctl plugin load /home/pavel/Projects/hyprland-plugins/overview-bench/hdiag-tail/build/liboverview.so")
    hl.exec_cmd("hyprctl plugin load /home/pavel/Projects/hyprland-plugins/overview/build/liboverview.so")
    hl.exec_cmd("hyprctl plugin load /home/pavel/.config/hypr/scrollbar_fix/libscrollbar_fix.so")
    hl.exec_cmd("hyprctl plugin load /home/pavel/.config/hypr/edp-disable-fix/libedp-disable-fix.so")
    hl.exec_cmd("hyprctl plugin load /home/pavel/.config/hypr/clipboard_bridge/libclipboard_bridge.so")
    hl.exec_cmd("audio-default.sh")
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE",    "24")
hl.env("XCURSOR_THEME",   "LiOSV")
--hl.env("HYPRCURSOR_THEME", "Hackneyed Cursors")
--hl.env("HYPRCURSOR_SIZE", "24")

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
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",

        col = {
            active_border   = "0xff242424",
            inactive_border = "0xff242424",
        },
    },

    render = {
        direct_scanout = 1,
        --async_commit = true,
        cm_auto_hdr = 0,
        cm_enabled = false,
        --commit_timing_enabled
        expand_undersized_textures = true,
        icc_vcgt_enabled = false,
        keep_unmodified_copy = 0,
        --new_render_scheduling = true,
        send_content_type = false,
        --use_fp16 = 0,
        --xp_mode = false
    },

    opengl = {
        nvidia_anti_flicker = false
    },

    xwayland = {
        enabled = false,
    },

    decoration = {
        rounding       = 0,
        border_part_of_window = true,

        active_opacity = 1.0,
        inactive_opacity = 1.0,
        fullscreen_opacity = 1.0,

        --rounding_power = 4.0,
        --dim_inactive = false,
        --dim_modal = true,
        --dim_special = 0.2,
        --dim_strength = 0.2,
        --dim_around = 0.3,

        shadow = {
            enabled = false,
        },
        blur = {
            enabled = false,
        },
        motion_blur = {
            enabled = false,
        },
        wobble = {
            enabled = false,
        },
        glow = {
            enabled = false,
        }
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    cursor = {
        no_hardware_cursors = 0,
        enable_hyprcursor = false,
        hotspot_padding = 1,
        zoom_disable_aa = true,
        --warp_on_change_workspace = 1,
        --no_break_fs_vrr = 0,
        --zoom_detached_camera = false,
        --zoom_rigid = true
    },

    misc = {
        --animate_manual_resizes = true,
        --animate_mouse_windowdragging = true,
        --disable_autoreload = true,
        --enable_swallow = true,
        --render_unfocused_fps = 1,
        force_default_wallpaper = 1,
        disable_hyprland_logo = true,
        background_color = 0xff171717,
        bell_sound = "none",
        initial_workspace_tracking = 0,
        disable_watchdog_warning = true,
        disable_splash_rendering = true,
        focus_on_activate        = true,
        middle_click_paste       = false,
    },

    ecosystem = {
        no_donation_nag = true,
        no_update_news = true,
    },

    group = {
        auto_group = true,
        insert_after_current = false,
        col = {
            border_active = "0xff242424",
            border_inactive = "0xff242424",
        },
        groupbar = {
            enabled = true,
            render_titles = true,
            height = 32,
            --font_family =
            font_size = 11,
            --font_weight_active =
            --font_weight_inactive =

            indicator_height = 0,
            indicator_gap = 0,
            gaps_in = 8,
            gaps_out = 2,
            keep_upper_gap = false,
            text_color = "0xffffffff",
            text_color_inactive = "0xff9a9a9a",
            col = {
                active = "0xff3c3c3c",
                inactive = "0xff242424",
            },
        },
    },

    input = {
        kb_layout = "us,se,ru",
        repeat_delay = 300,
        repeat_rate = 30,
        follow_mouse = 1,
        focus_on_close = 1,
        sensitivity = 0,
        accel_profile = "flat",
        --force_no_accel = true,
        --emulate_discrete_scroll = 0,
        --off_window_axis_events = 3,
        --resolve_binds_by_sym = false,

        --touchpad = {}
        touchdevice = {
            enabled = false,
        },
        --tablet = {
        --    enabled = false,
        --},
    },

    binds = {
        movefocus_cycles_groupfirst = true,
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { { 0.23, 1    }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear",         { type = "bezier", points = { { 0,    0    }, { 1,    1 } } })
hl.curve("almostLinear",   { type = "bezier", points = { { 0.5,  0.5  }, { 0.75, 1 } } })
hl.curve("quick",          { type = "bezier", points = { { 0.15, 0    }, { 0.1,  1 } } })
hl.curve("circle",         { type = "bezier", points = { { 0,    0.55 }, { 0.45, 1 } } })  -- wayfire "circle": sqrt(2x-x^2)
hl.curve("circle2",        { type = "bezier", points = { { 0,    0.3 }, { 0.35, 1 } } })

hl.animation({ leaf = "global",        enabled = true, speed = 2, bezier = "circle" })
hl.animation({ leaf = "border",        enabled = true, speed = 2, bezier = "circle" })
hl.animation({ leaf = "windows",       enabled = true, speed = 2, bezier = "circle" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 2, bezier = "circle", style = "popin 50%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 2, bezier = "circle", style = "popin 50%" })
hl.animation({ leaf = "windowsMove",   enabled = true, speed = 2, bezier = "circle" })  -- hyprexpo overview zoom: 200ms
hl.animation({ leaf = "fadeIn",        enabled = false })   -- no fade on open, zoom only
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 2, bezier = "circle" })   -- required: a closing window lives only while this runs
hl.animation({ leaf = "fade",          enabled = true, speed = 2, bezier = "circle" })
hl.animation({ leaf = "layers",        enabled = true, speed = 2, bezier = "circle" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 2, bezier = "circle", style = "popin 50%" })   -- zoom, not fade
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 2, bezier = "circle", style = "popin 50%" })   -- zoom, not fade
hl.animation({ leaf = "fadeLayersIn",  enabled = false })   -- no alpha fade when a layer opens
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 2, bezier = "circle" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 3, bezier = "circle" })  -- hyprtasking grid pan/zoom: 200ms
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 3.5, bezier = "circle" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 3.5, bezier = "circle" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 2, bezier = "circle" })


---------------
---- INPUT ----
---------------

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })



---------------------
---- KEYBINDINGS ----
---------------------

local M = "SUPER"

-- Terminal / core
hl.bind(M .. " + Q",           hl.dsp.window.close())

-- Move/resize windows with mouse
hl.bind(M .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(M .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- TEMPORARY (blur test): the focused window's opacity on SUPER + mouse wheel
local window_opacity = {}
local function step_opacity(delta)
    local w = hl.get_active_window()
    if not w then return end
    local a = math.min(1.0, math.max(0.1, (window_opacity[w.address] or 1.0) + delta))
    window_opacity[w.address] = a
    -- Focused and unfocused alike: in the overview no window is focused.
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = tostring(a) }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_inactive", value = tostring(a) }))
end
hl.bind(M .. " + mouse_up",   function() step_opacity(0.05) end)
hl.bind(M .. " + mouse_down", function() step_opacity(-0.05) end)





----------------------------
---- MODIFIER-ONLY TAPS ----
----------------------------

-- The keybind engine in 0.56.0-194-gd50ca8950 does not reliably match
-- modmask-based modifier binds. Measured here: "SUPER + CTRL + Control_L" fired
-- 0/6 presses, while an ignore_mods bind whose callback reads hl.is_key_down
-- fired 6/6. Bind.cpp matchesContext() compares
--   (modifiersAtPress | trigger's own modifier) == modmask
-- on release, and that comparison is what fails; ignore_mods short-circuits it.
--
-- Shadowing still applies, so Ctrl+C does NOT trigger these (verified: 0 fires
-- for Ctrl+C, 3/3 for a bare Ctrl tap). non_consuming keeps the key events
-- flowing to applications.
--
-- One release bind per modifier key; the callback works out which combination
-- was held. combo_fired stops the remaining keys of a chord from also running
-- their single-key action as they are released.

local MOD_KEYS   = { "Super_L", "Control_L", "Control_R", "Shift_L", "Alt_L" }
-- Suppression for chord tails, keyed per modifier and time-bounded so it cannot
-- leak. A global boolean latch did leak: if a chord's last key went up while
-- another modifier still read as held, the release never saw n == 1, the latch
-- stayed set, and it swallowed the NEXT bare tap (single Ctrl needing two
-- presses). Per-key entries are consumed on use and expire on their own.
local suppress_bare = {}

local function uptime()
    local f = io.open("/proc/uptime")
    if not f then return 0 end
    local t = f:read("*n") or 0
    f:close()
    return t
end

local function mod_tap(self_key)
    local down = { [self_key] = true }
    for _, k in ipairs(MOD_KEYS) do
        if k ~= self_key and hl.is_key_down(k) then down[k] = true end
    end

    local super = down["Super_L"] and 1 or 0
    local ctrl  = (down["Control_L"] or down["Control_R"]) and 1 or 0
    local shift = down["Shift_L"] and 1 or 0
    local alt   = down["Alt_L"] and 1 or 0
    local n     = super + ctrl + shift + alt

    if n > 1 then
        -- Fire every time a combo completes: while Super is held, each Shift tap
        -- is a fresh n=2 release and should act. Mark every key held right now,
        -- so none of them runs its bare action as the chord is released.
        local t = uptime()
        for k in pairs(down) do suppress_bare[k] = t end
        if super == 1 and shift == 1 and alt == 1 and ctrl == 0 then
            hl.exec_cmd("monstar")                                                 -- binding_37
        elseif super == 1 and ctrl == 1 and shift == 0 and alt == 0 then
            hl.exec_cmd("launch-or-focus.sh -w 4 --single-class sublime_text subl")     -- binding_2
        elseif super == 1 and shift == 1 and ctrl == 0 and alt == 0 then
            hl.exec_cmd("launch-or-focus.sh -w 1 --single-class shell kitty --single-instance --listen-on=unix:@mykitty --class shell zsh")    -- binding_8
        elseif super == 1 and alt == 1 and ctrl == 0 and shift == 0 then
            hl.exec_cmd("dashboard.sh --class float --session ~/.config/kitty/session.conf")     -- binding_49
        end
        return
    end

    -- n == 1: either a genuine bare tap, or the last key of a chord being let go.
    -- Consume any mark for this key; only honour it if it is fresh, so a stale
    -- entry can never eat a real tap.
    local marked = suppress_bare[self_key]
    suppress_bare[self_key] = nil
    if marked and (uptime() - marked) < 1.0 then
        return
    end

    if ctrl == 1 then
        hl.exec_cmd("makoctl invoke && makoctl dismiss")                           -- binding_51
    elseif super == 1 then
        hl.plugin.hyprtasking.toggle("cursor")                                 -- expo toggle = <super>
    end
end

for _, k in ipairs(MOD_KEYS) do
    hl.bind(k, function() mod_tap(k) end, { release = true, ignore_mods = true, non_consuming = true })
end


-- Multimedia keys
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("volume.sh up"),                                  { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("volume.sh down"),                                { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("volume.sh mute"),                                { locked = true, repeating = true })
hl.bind(M .. " + Prior",         hl.dsp.exec_cmd("brightness.sh up"),   { repeating = true })
hl.bind(M .. " + Next",          hl.dsp.exec_cmd("brightness.sh down"), { repeating = true })


-- System
hl.bind("CTRL + ALT + BACKSPACE", hl.dsp.exit())
-- ESC: dismiss the top notification if one is showing, otherwise pass ESC
-- through to the focused program. Returning { pass_event = true } from a Lua
-- bind callback tells Hyprland not to consume the key (KeybindManager.cpp:842).
-- mako-daemonless only runs while a notification is up, so empty `makoctl list`
-- == nothing showing, and makoctl never activates the daemon.
hl.bind("ESCAPE", function()
    local f = io.popen("makoctl list 2>/dev/null")
    local out = ""
    if f then
        out = f:read("*a") or ""
        f:close()
    end

    if out:match("%S") then
        hl.exec_cmd("makoctl dismiss")
        return { pass_event = false }
    end

    return { pass_event = true }
end)

-- Tap bare Ctrl to invoke + dismiss the notification; Ctrl held as a modifier
-- still works (Hyprland shadows this release bind if another bind fired).
-- The modifier must be KEPT here: bare "Control_L" never fires on 0.56.2,
-- same stale-modmask issue as SUPER_L. Verified by testing both forms.
-- exec runs via /bin/sh -c (Executor.cpp:203), so && needs no wrapper.


--------------------------------
---- PORTED FROM WAYFIRE.INI ----
--------------------------------
-- The `open -w NN --single-app-id X` wrapper is dropped: `open` is a Wayfire
-- IPC binary (my-rules/prepare-open) and cannot work here. Only the wrapper is
-- gone - the underlying command and its keybind are preserved.

-- Launchers
hl.bind(M .. " + Z",           hl.dsp.exec_cmd("launch-or-focus.sh -w 2 --single-class vivaldi --exclude-tag incognito vivaldi"))                                              -- binding_16
hl.bind(M .. " + SHIFT + Z",   hl.dsp.exec_cmd("launch-or-focus.sh -w 3 --single-tag incognito --adopt-class vivaldi --tag incognito vivaldi --incognito"))                                  -- binding_17
hl.bind(M .. " + M",           hl.dsp.exec_cmd("launch-or-focus.sh -w 5 --single-class mpv mpv --player-operation-mode=pseudo-gui"))               -- binding_39
hl.bind(M .. " + D",           hl.dsp.exec_cmd("launch-or-focus.sh -w 6 --single-class wcm wcm"))                                                  -- binding_23
hl.bind(M .. " + A",           hl.dsp.exec_cmd("launch-or-focus.sh -w 7 --single-class yazi kitty --single-instance --listen-on=unix:@mykitty --class yazi yazi"))  -- binding_19
hl.bind(M .. " + GRAVE",       hl.dsp.exec_cmd("launch-or-focus.sh -w 9 --single-class btm kitty --single-instance --listen-on=unix:@mykitty --class btm btm"))    -- binding_21
hl.bind(M .. " + SHIFT + GRAVE", hl.dsp.exec_cmd("launch-or-focus.sh -w 8 --single-class btop kitty --single-instance --listen-on=unix:@mykitty --class btop btop")) -- binding_43

-- launch-or-focus helpers (compositor-agnostic script)
hl.bind(M .. " + U",           hl.dsp.exec_cmd("kitty-launch-or-focus.sh yzf -u"))                       -- binding_24
hl.bind(M .. " + I",           hl.dsp.exec_cmd("kitty-launch-or-focus.sh cliphist-images.sh"))            -- binding_25
hl.bind(M .. " + K",           hl.dsp.exec_cmd("kitty-launch-or-focus.sh nasc"))                         -- binding_26
hl.bind(M .. " + SHIFT + W",   hl.dsp.exec_cmd("kitty-launch-or-focus.sh impala"))                       -- binding_53
hl.bind(M .. " + N",           hl.dsp.exec_cmd([[kitty-launch-or-focus.sh vpn-shell nyaazf.sh 'naruto|-"kun.hu"|(varyg dual)']])) -- binding_40

-- Menus / pickers
hl.bind(M .. " + V",           hl.dsp.exec_cmd("cliphist-menu.sh"))                                       -- binding_1
hl.bind(M .. " + E",           hl.dsp.exec_cmd("emoji-picker.sh"))                                       -- binding_4
hl.bind(M .. " + SHIFT + E",   hl.dsp.exec_cmd("nerdfont-picker.sh"))                                    -- binding_18
hl.bind(M .. " + ALT + E",     hl.dsp.exec_cmd("unicode-picker.sh"))                                     -- binding_41
hl.bind(M .. " + TAB",         hl.dsp.exec_cmd("rofi -show drun -show-icons"))                           -- binding_14
hl.bind(M .. " + W",           hl.dsp.exec_cmd("iwmenu --launcher rofi"))                                -- binding_13
hl.bind(M .. " + S",           hl.dsp.exec_cmd("alsa-switch"))                                           -- binding_6
hl.bind(M .. " + SPACE",       hl.dsp.exec_cmd("keyboard-layout-switcher.py"))                           -- binding_12

-- Screenshot / capture
hl.bind(M .. " + SHIFT + S",   hl.dsp.exec_cmd("dulcepan | wl-copy --type image/png"))                   -- binding_0
hl.bind(M .. " + ALT + S",     hl.dsp.exec_cmd("grabit -e -c"))                                          -- binding_9
hl.bind(M .. " + SHIFT + D",   hl.dsp.exec_cmd("hyprpicker -a"))                                         -- binding_7
hl.bind(M .. " + SHIFT + X",   hl.dsp.exec_cmd("shmooz --invert-scroll"))                                -- binding_28
hl.bind(M .. " + SHIFT + A",   hl.dsp.exec_cmd([[dulcepan -f png | tesseract - stdout -l swe 2>/dev/null | wl-copy && notify-send -a osd -t 2000 "$(wl-paste)"]])) -- binding_3

-- Mic volume (repeatable, like wayfire's repeatable_binding_*)
hl.bind(M .. " + ALT + Prior", hl.dsp.exec_cmd("mic-volume.sh up"),   { repeating = true })              -- binding_54
hl.bind(M .. " + ALT + Next",  hl.dsp.exec_cmd("mic-volume.sh down"), { repeating = true })              -- binding_55
hl.bind(M .. " + ALT + M",     hl.dsp.exec_cmd("mic-volume.sh mute"))                                    -- binding_56

-- Monitor rotation
-- Rotation, natively rather than via wlr-randr. An output change made while the
-- desktop is idle is queued but not committed until something wakes the
-- renderer - which is why nothing happened until the cursor moved.
-- force_renderer_reload does that wake-up explicitly.
-- transform: 0 = normal, 1 = 90, 2 = 180, 3 = 270 (wl_output_transform)
local function rotate_dp2(transform)
    hl.dispatch(hl.dsp.force_renderer_reload())
    hl.monitor({ output = "DP-2", mode = "1920x1080@144", position = "0x0", scale = 1, transform = transform })
end

hl.bind(M .. " + ALT + CTRL + up",    function() rotate_dp2(2) end)   -- binding_45: 180
hl.bind(M .. " + ALT + CTRL + down",  function() rotate_dp2(0) end)   -- binding_46: normal
hl.bind(M .. " + ALT + CTRL + left",  function() rotate_dp2(3) end)   -- binding_47: 270
hl.bind(M .. " + ALT + CTRL + right", function() rotate_dp2(1) end)   -- binding_48: 90

-- simple-tile key_focus_* (wayfire used CTRL+SUPER; SUPER+ALT above is a hyprland-only extra)
--hl.bind(M .. " + CTRL + up",    hl.dsp.focus({ direction = "up" }))
--hl.bind(M .. " + CTRL + down",  hl.dsp.focus({ direction = "down" }))
--hl.bind(M .. " + CTRL + left",  hl.dsp.focus({ direction = "left" }))
--hl.bind(M .. " + CTRL + right", hl.dsp.focus({ direction = "right" }))

-- Bare modifier-combo taps (wayfire modifier_binding_timeout = 400).
-- Same rule as SUPER_L / Control_L: keep the full modmask in the bind string.
-- Both release orders are bound so either key may be let go first; only the
-- first one matches, since the second release no longer has the full modmask.
-- UNVERIFIED - these multi-mod combos still need a real keypress to confirm.




hl.bind(M .. " + L",              hl.dsp.exec_cmd("hyprlock"))
hl.bind(M .. " + SHIFT + Q",      hl.dsp.exec_cmd("power-menu-hyprland.sh"))
hl.bind(M .. " + RETURN",         hl.dsp.exec_cmd("autostart.sh -w"))


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- Ported from wayfire.ini [my-rules] "assign-focus RC".
-- workspace = "N" (no "silent") moves the window there AND follows it, which is
-- what assign-focus did. Exec rules from hl.dsp.exec_cmd are applied after
-- static rules (WindowRuleApplicator.cpp:517), so a launcher can override these
-- per-launch - that is how incognito vivaldi reaches ws 3 despite sharing a
-- class with regular vivaldi. No suppression token needed.
-- kitty --single-instance hands the request to the ALREADY RUNNING kitty, which
-- creates the window under its own pid. Hyprland's exec rules bind to the pid of
-- the process it spawned, so they never match these windows. Static class rules
-- do, because they match the window itself. Each of these passes a distinct
-- --class, so the class is correct at map time.
hl.window_rule({ name = "assign-shell", match = { class = "^shell$" }, workspace = "1" })   -- open -w 11
hl.window_rule({ name = "assign-yazi-k", match = { class = "^yazi$" },  workspace = "7" })  -- open -w 31
hl.window_rule({ name = "assign-btm",   match = { class = "^btm$" },   workspace = "9" })   -- open -w 33
hl.window_rule({ name = "assign-btop",  match = { class = "^btop$" },  workspace = "8" })   -- open -w 33

hl.window_rule({                                          -- rule_10: subl -> 21
    name  = "assign-subl",
    match = { class = ".*subl.*" },
    workspace = "4",
})

hl.window_rule({                                          -- rule_11: browser -> 12
    name  = "assign-browser",
    match = { class = ".*vivaldi.*" },
    workspace = "2",
})

hl.window_rule({                                          -- rule_12: yazi -> 31
    name  = "assign-yazi",
    match = { class = ".*yazi.*" },
    workspace = "7",
})

hl.window_rule({                                          -- rule_15: mpv -> 22
    name  = "assign-mpv",
    match = { class = ".*mpv.*" },
    workspace = "5",
})

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

-- wayfire.ini [simple-tile] tile_by_default = !(app_id contains "float" | app_id
-- contains "mousam") - i.e. anything whose class contains those never tiles.
hl.window_rule({
    name  = "float-by-class",
    match = { class = ".*(float|mousam).*" },
    float = true,
})
-- The dashboard is launched as `dashboard.sh --class float`, so its class is
-- exactly "float" - float-half / float-full are separate classes and keep their
-- own rules below. Global rounding and border_size are both 0, so they have to
-- be set here for this window to get either.
hl.window_rule({
    name        = "dashboard",
    match       = { class = "^float$" },
    float       = true,
    rounding    = 10,
    border_size = 2,
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
hl.config({ debug = { disable_logs = false } })

hl.bind("SUPER + O", function() hl.plugin.overview.toggle() end)
hl.bind("SUPER + SHIFT + O", function() hl.plugin.overview.toggle_all() end)
hl.config({ plugin = { overview = {
    rows = 3,
    columns = 3,
    border_size = 2,
    border_color = "#242424FF",
    duration = "200ms circle",
    skip_empty_workspaces = true,
    fullsize_rendering = false,
    grabbed_scale = 50,
    preview_border_color = 0xcc404080,
    preview_border_size = 3,
    preview_border_radius = 8,
    snapshot_switch = 0.6,
    scaled_target = true,
    overview_wait_timeout = 15,
    overview_focus_timeout = 50,
    switch_duration = "300ms circle",
    switch_wait_timeout = 1000,
    pool_buffers = 0,
    flush_after_draw = false,
} } })

hl.bind("SUPER + LEFT", function() hl.plugin.overview.move("left") end)
hl.bind("SUPER + RIGHT", function() hl.plugin.overview.move("right") end)
hl.bind("SUPER + UP", function() hl.plugin.overview.move("up") end)
hl.bind("SUPER + DOWN", function() hl.plugin.overview.move("down") end)

hl.bind("SUPER + SHIFT + LEFT", function() hl.plugin.overview.move_window("left") end)
hl.bind("SUPER + SHIFT + RIGHT", function() hl.plugin.overview.move_window("right") end)
hl.bind("SUPER + SHIFT + UP", function() hl.plugin.overview.move_window("up") end)
hl.bind("SUPER + SHIFT + DOWN", function() hl.plugin.overview.move_window("down") end)



hl.config({ plugin = { clipboard_bridge = {
    command = "cliphist -max-store-size 0 store",

    clipboard = "regular",
    xwayland = false,
    persistence = true,
    forward_sensitive = false,

    mime_types = "image/jpeg,image/*,image/png,text/plain;charset=utf-8,UTF8_STRING,text/plain,*",
    forward_all = false,

    min_size = 0,
    max_size = 0,
    timeout_ms = 0,

    excluded_apps = "",
    excluded_patterns = "",
} } })


if hl.plugin.scrollbar_fix then
    hl.plugin.scrollbar_fix.rule({
        app = "vivaldi-stable",
        scrollbar_width = 17,
        gap_top = 80,
        gap_bottom = 15,
        gaps_fullscreen = 15,
    })
end



-- Turn the focused window into a group, or dissolve the group it is in
hl.bind(M .. " + G",           hl.dsp.group.toggle())
-- Show the next / previous window of the group
hl.bind(M .. " + CTRL + TAB",  hl.dsp.group.next())
hl.bind(M .. " + CTRL + SHIFT + TAB", hl.dsp.group.prev())
-- Move the focused window into the group next to it
hl.bind(M .. " + CTRL + LEFT",  hl.dsp.window.move({ into_group = "left" }))
hl.bind(M .. " + CTRL + RIGHT", hl.dsp.window.move({ into_group = "right" }))
hl.bind(M .. " + CTRL + UP",    hl.dsp.window.move({ into_group = "up" }))
hl.bind(M .. " + CTRL + DOWN",  hl.dsp.window.move({ into_group = "down" }))
-- Take the focused window out of its group
hl.bind(M .. " + CTRL + G",     hl.dsp.window.move({ out_of_group = true }))
