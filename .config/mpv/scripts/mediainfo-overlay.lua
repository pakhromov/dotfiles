-- mediainfo-overlay.lua — display mediainfo for the currently playing file

local assdraw = require("mp.assdraw")
local overlay = mp.create_osd_overlay("ass-events")

-- ── Configuration ─────────────────────────────────────────────────────────────

local MAX_LINES = 26
local PAN_STEP  = 50

-- ── Colors ────────────────────────────────────────────────────────────────────

local C = {
    header  = "&H88E7FC&",   -- gold
    sep     = "&HFFFFFF&",   -- white
    section = "&H88E7FC&",   -- gold  (section headers: General, Video, Audio…)
    key     = "&Hffccff&",   -- pink
    value   = "&HFFFFFF&",   -- white
}

-- ── State ─────────────────────────────────────────────────────────────────────

local lines  = {}
local scroll = 1
local posX   = 0
local active = false

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

    local total    = #lines
    local filename = mp.get_property("filename", "unknown")
    ass:append("{\\fs30\\c" .. C.header .. "\\b1}Mediainfo: " .. esc(filename) .. "\\N")
    ass:append("{\\fs20\\c" .. C.sep .. "}--------------------------------------------------------------------------------------------------------------------------------\\N")

    if total == 0 then
        ass:append("{\\fs20\\c" .. C.sep .. "}Loading\xe2\x80\xa6\\N")
    else
        local stop = math.min(total, scroll + MAX_LINES - 1)
        for i = scroll, stop do
            local line = lines[i]
            if line == "" then
                -- blank line between sections
                ass:append("{\\fs20}\\N")
            else
                local sep_pos = line:find(" : ", 1, true)
                if sep_pos then
                    -- key : value pair
                    local key = line:sub(1, sep_pos - 1)
                    local val = line:sub(sep_pos + 3)
                    ass:append(
                        "{\\fnMonospace\\fs20\\c" .. C.key   .. "}" .. esc(key) ..
                        "{\\c"                   .. C.value .. "} : " .. esc(val) .. "\\N")
                else
                    -- section header (General, Video, Audio #1, …)
                    ass:append("{\\fs20\\c" .. C.section .. "\\b1}" .. esc(line) .. "\\N")
                end
            end
        end
    end

    overlay.data = ass.text
    overlay:update()
end

-- ── Actions ───────────────────────────────────────────────────────────────────

local function bname(n) return "dynamic/" .. overlay.id .. "/" .. n end

local function scroll_up()
    if scroll > 1 then scroll = scroll - 1; render() end
end

local function scroll_down()
    if scroll + MAX_LINES - 1 < #lines then scroll = scroll + 1; render() end
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

local function close()
    active = false
    overlay:remove()
    for _, n in ipairs({ "up", "down", "wup", "wdown", "close", "pleft", "pright" }) do
        mp.remove_key_binding(bname(n))
    end
end

local function open()
    active = true
    scroll = 1
    posX   = 0
    lines  = {}

    mp.add_forced_key_binding("UP",         bname("up"),    scroll_up,   { repeatable = true })
    mp.add_forced_key_binding("DOWN",       bname("down"),  scroll_down, { repeatable = true })
    mp.add_forced_key_binding("wheel_up",   bname("wup"),   scroll_up,   { repeatable = true })
    mp.add_forced_key_binding("wheel_down", bname("wdown"), scroll_down, { repeatable = true })
    mp.add_forced_key_binding("ESC",        bname("close"), close,       {})
    mp.add_forced_key_binding("LEFT",       bname("pleft"), pan_left,    { repeatable = true })
    mp.add_forced_key_binding("RIGHT",      bname("pright"),pan_right,   { repeatable = true })

    render()  -- show "Loading…" immediately

    mp.add_timeout(0.1, function()
        if active then render() end
    end)

    local path = mp.get_property("path", "")
    mp.command_native_async({
        name           = "subprocess",
        args           = { "mediainfo", path },
        capture_stdout = true,
        playback_only  = false,
    }, function(success, result)
        if not active then return end
        if success and result and result.stdout and result.stdout ~= "" then
            lines = {}
            for line in (result.stdout .. "\n"):gmatch("([^\n]*)\n") do
                lines[#lines + 1] = line
            end
            while #lines > 0 and lines[#lines] == "" do
                table.remove(lines)
            end
        else
            lines = { "Error: mediainfo failed or is not installed" }
        end
        render()
    end)
end

-- ── Entry point ───────────────────────────────────────────────────────────────

mp.add_key_binding("ctrl+i", "mediainfo-overlay", function()
    if active then close() else open() end
end)

mp.register_script_message("open-mediainfo", function()
    if not active then open() end
end)
