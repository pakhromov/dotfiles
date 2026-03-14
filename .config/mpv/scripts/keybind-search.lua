-- keybind-search.lua — searchable keybind browser, navigator rendering style

local assdraw = require("mp.assdraw")
local overlay = mp.create_osd_overlay("ass-events")

-- ── Configuration ─────────────────────────────────────────────────────────────

local MAX_ITEMS = 26
local COL1_W    = 30    -- key+section column width (chars)
local COL2_W    = 100    -- key+section+padding+cmd width before comment (chars)
local PAN_STEP  = 50

-- ── Colors ────────────────────────────────────────────────────────────────────

local C = {
    header   = "&H88E7FC&",   -- light blue
    sep      = "&HFFFFFF&",   -- white
    key      = "&Hffccff&",   -- pink
    section  = "&H88E7FC&",   -- light blue
    cmd      = "&Hffff00&",   -- yellow
    comment  = "&H33ff66&",   -- green
    cursor   = "&Hfce788&",   -- light blue  (cursor icon when selected)
    selected = "&H88E7FC&",   -- gold        (full row when selected)
}

-- ── ASS helpers ───────────────────────────────────────────────────────────────

local ZWNBSP = "\239\187\191"

local function esc(s)
    if not s or s == "" then return "" end
    s = s:gsub('[\\{}\n]', {
        ['\\'] = '\\' .. ZWNBSP,
        ['{']  = '\\{',
        ['}']  = '\\}',
        ['\n'] = ZWNBSP .. '\\N',
    })
    s = s:gsub('^ ', '\\h')
    return s
end

local function gap(raw_len, col_width)
    local n = col_width - raw_len
    return string.rep(" ", n < 2 and 2 or n)
end

-- ── State ─────────────────────────────────────────────────────────────────────

local all_binds  = {}
local filtered   = {}
local pattern    = ""
local cursor_idx = 1
local active     = false
local posX       = 0

-- ── Data ──────────────────────────────────────────────────────────────────────

local function rebuild_filtered()
    local keys = mp.get_property_native('input-bindings') or {}

    -- find highest-priority cmd per key for override detection
    local best = {}
    for _, b in ipairs(keys) do
        if b.priority >= 0 and b.section ~= "input_forced_console" then
            local prev = best[b.key]
            if not prev or b.priority > prev.priority then
                best[b.key] = { priority = b.priority, cmd = b.cmd }
            end
        end
    end

    all_binds = {}
    filtered  = {}
    local kw  = pattern:lower()

    for _, b in ipairs(keys) do
        local bind = {
            key      = b.key     or "",
            cmd      = b.cmd     or "",
            comment  = b.comment or "",
            section  = (b.section and b.section ~= "default") and b.section or "",
            override = best[b.key] ~= nil and best[b.key].cmd ~= b.cmd,
        }
        all_binds[#all_binds + 1] = bind
        if kw == ""
            or bind.key    :lower():find(kw, 1, true)
            or bind.cmd    :lower():find(kw, 1, true)
            or (bind.comment ~= "" and bind.comment:lower():find(kw, 1, true))
        then
            filtered[#filtered + 1] = bind
        end
    end

    if cursor_idx > #filtered then
        cursor_idx = math.max(1, #filtered)
    end
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function render()
    local ass = assdraw.ass_new()
    ass:new_event()
    if posX == 0 then
        ass:append("{\\an7\\q2}")
        ass:append("\\N\\N")
    else
        ass:append("{\\pos(" .. posX .. ",0)\\an7\\q2}")
        ass:append("\\N\\N\\N")
    end

    local title = "Keybinds" .. (pattern ~= "" and ": " .. esc(pattern) or "")
    ass:append("{\\fs30\\c" .. C.header .. "\\b1}" .. title .. "\\N")
    ass:append("{\\fs20\\c" .. C.sep   .. "}" ..
        "--------------------------------------------------------------------------------------------------------------------------------\\N")

    if #filtered == 0 then
        ass:append("{\\c" .. C.sep .. "}no results\\N")
    else
        local half  = math.floor(MAX_ITEMS / 2) - 1
        local start = math.max(1, cursor_idx - half)
        local stop  = math.min(#filtered, start + MAX_ITEMS - 1)
        if stop - start < MAX_ITEMS - 1 then
            start = math.max(1, stop - MAX_ITEMS + 1)
        end

        for i = start, stop do
            local b      = filtered[i]
            local is_sel = (i == cursor_idx)

            -- raw (unescaped) text lengths for column alignment
            local sec_raw   = b.section ~= "" and ("  (" .. b.section .. ")") or ""
            local key_sec   = b.key .. sec_raw
            local g1        = gap(#key_sec, COL1_W)
            local col2_raw  = key_sec .. g1 .. b.cmd
            local g2        = b.comment ~= "" and gap(#col2_raw, COL2_W) or ""

            -- set row color first (navigator style), then alpha-trick the cursor icon
            if is_sel then
                ass:append("{\\c" .. C.selected .. "}")
            end
            if is_sel then
                ass:append("{\\alpha&H00&}⮞\\h")
            else
                ass:append("{\\alpha&HFF&}⮞\\h{\\alpha&H00&}")
            end

            -- switch to monospace for the three columns so space-padding aligns
            if is_sel then
                ass:append("{\\fnMonospace}" ..
                    esc(key_sec) .. g1 .. esc(b.cmd) ..
                    (b.comment ~= "" and (g2 .. esc(b.comment)) or "") ..
                    "\\N")
            else
                local fade   = b.override and "{\\alpha&H80&}" or ""
                local unfade = b.override and "{\\alpha&H00&}" or ""
                ass:append(
                    fade ..
                    "{\\fnMonospace\\c" .. C.key     .. "}" .. esc(b.key) ..
                    "{\\c"             .. C.section .. "}" .. esc(sec_raw) ..
                    "{\\c"             .. C.cmd     .. "}" .. g1 .. esc(b.cmd) ..
                    "{\\c"             .. C.comment .. "}" .. (b.comment ~= "" and (g2 .. esc(b.comment)) or "") ..
                    unfade .. "\\N")
            end
        end
    end

    overlay.data = ass.text
    overlay:update()
end

-- ── Actions ───────────────────────────────────────────────────────────────────

local function bname(n) return 'dynamic/' .. overlay.id .. '/' .. n end

local function close()
    active = false
    overlay:remove()
    for _, n in ipairs({ "up", "down", "enter", "bs", "clear", "close", "pleft", "pright", "input", "wup", "wdown", "rclick" }) do
        mp.remove_key_binding(bname(n))
    end
end

local function nav_up()
    if cursor_idx > 1 then cursor_idx = cursor_idx - 1; render() end
end

local function nav_down()
    if cursor_idx < #filtered then cursor_idx = cursor_idx + 1; render() end
end

local function do_enter()
    local b = filtered[cursor_idx]
    if b and b.cmd ~= "" then
        mp.command(b.cmd)
    end
end

local function do_backspace()
    if #pattern > 0 then
        pattern = pattern:sub(1, -2)
        cursor_idx = 1
        rebuild_filtered()
        render()
    end
end

local function do_clear()
    if pattern ~= "" then
        pattern = ""
        cursor_idx = 1
        rebuild_filtered()
        render()
    end
end

local function handle_input(event)
    if event.event == "press" or event.event == "down" or event.event == "repeat" then
        pattern = pattern .. event.key_text
        cursor_idx = 1
        rebuild_filtered()
        render()
    end
end

local function pan_left()
    posX = posX + PAN_STEP
    if posX > 0 then posX = 0 end
    render()
end

local function pan_right()
    posX = posX - PAN_STEP
    render()
end

local function open()
    active     = true
    posX       = 0
    pattern    = ""
    cursor_idx = 1
    mp.add_forced_key_binding("UP",          bname("up"),    nav_up,       { repeatable = true })
    mp.add_forced_key_binding("DOWN",        bname("down"),  nav_down,     { repeatable = true })
    mp.add_forced_key_binding("ENTER",       bname("enter"), do_enter,     {})
    mp.add_forced_key_binding("BS",          bname("bs"),    do_backspace, { repeatable = true })
    mp.add_forced_key_binding("Ctrl+u",      bname("clear"), do_clear,     {})
    mp.add_forced_key_binding("ESC",         bname("close"), close,        {})
    mp.add_forced_key_binding("LEFT",        bname("pleft"), pan_left,     { repeatable = true })
    mp.add_forced_key_binding("RIGHT",       bname("pright"),pan_right,    { repeatable = true })
    mp.add_forced_key_binding("any_unicode", bname("input"),  handle_input, { repeatable = true, complex = true })
    mp.add_forced_key_binding("wheel_up",    bname("wup"),    nav_up,       { repeatable = true })
    mp.add_forced_key_binding("wheel_down",  bname("wdown"),  nav_down,     { repeatable = true })
    mp.add_forced_key_binding("MBTN_RIGHT",  bname("rclick"), do_enter,     {})
    rebuild_filtered()
    render()
    mp.add_timeout(0.1, function()
        if active then rebuild_filtered(); render() end
    end)
end

-- ── Entry point ───────────────────────────────────────────────────────────────

mp.add_key_binding("f12", "keybind-search", function()
    if active then close() else open() end
end)

mp.register_script_message("open-keybind-search", function()
    if not active then open() end
end)
