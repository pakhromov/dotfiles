local mpopt  = require("mp.options")
local assdraw = require("mp.assdraw")
local overlay = mp.create_osd_overlay("ass-events")

local opt = {
    max_rows         = 24,
    col_width        = 40,
    font_size        = 20,
    header_font_size = 30,
    keybind          = "a",
    color_header     = "#FCE788",
    color_sep        = "#FFFFFF",
    color_selected   = "#FCE788",
    color_active     = "#00FFFF",
    color_normal     = "#FFFFFF",
    color_inactive   = "#888888",
}

mpopt.read_options(opt, "track-picker")
for _, k in ipairs({"color_header","color_sep","color_selected","color_active","color_normal","color_inactive"}) do
    local hex = opt[k]:gsub("^#", "")
    opt[k] = "&H" .. hex:sub(5,6) .. hex:sub(3,4) .. hex:sub(1,2) .. "&"
end

local audio_tracks = {}
local sub_tracks   = {}
local col          = "audio"
local audio_cur    = 1
local sub_cur      = 1
local active       = false

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

local function pad(s, n)
    if #s >= n then return s:sub(1, n) end
    return s .. string.rep(" ", n - #s)
end

local function load_tracks()
    audio_tracks = {}
    sub_tracks   = { { id = false, title = "Off" } }
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "audio" then
            audio_tracks[#audio_tracks + 1] = t
        elseif t.type == "sub" then
            sub_tracks[#sub_tracks + 1] = t
        end
    end
end

local function fmt_audio(t)
    local label = ""
    if t.lang  then label = t.lang:upper() end
    if t.title and t.title ~= "" and t.title ~= t.lang then
        label = label ~= "" and (label .. " - " .. t.title) or t.title
    end
    if label == "" then label = "Track " .. t.id end
    local detail = {}
    if t.codec                   then detail[#detail + 1] = t.codec:upper() end
    if t["demux-channel-count"]  then detail[#detail + 1] = t["demux-channel-count"] .. "ch" end
    return label .. (#detail > 0 and " (" .. table.concat(detail, ", ") .. ")" or "")
end

local function fmt_sub(t)
    if not t.id then return "Off" end
    local label = ""
    if t.lang  then label = t.lang:upper() end
    if t.title and t.title ~= "" and t.title ~= t.lang then
        label = label ~= "" and (label .. " - " .. t.title) or t.title
    end
    if label == "" then label = "Track " .. t.id end
    local tags = {}
    if t.forced   then tags[#tags + 1] = "forced"  end
    if t.default  then tags[#tags + 1] = "default" end
    if t.external then tags[#tags + 1] = "ext"     end
    return label .. (#tags > 0 and " [" .. table.concat(tags, ", ") .. "]" or "")
end

local function render()
    local ass = assdraw.ass_new()
    ass:new_event()
    ass:append("{\\an7\\q2}")
    ass:append("\\N\\N")

    local filename = mp.get_property("filename", "unknown")
    ass:append("{\\fs" .. opt.header_font_size .. "\\c" .. opt.color_header .. "\\b1}Tracks: " .. esc(filename) .. "\\N")
    ass:append("{\\fs" .. opt.font_size .. "\\c" .. opt.color_sep .. "}" .. string.rep("-", opt.col_width + 107) .. "\\N")

    local a_clr  = col == "audio" and opt.color_selected or opt.color_inactive
    local s_clr  = col == "sub"   and opt.color_selected or opt.color_inactive
    local a_bold = col == "audio" and "\\b1" or "\\b0"
    local s_bold = col == "sub"   and "\\b1" or "\\b0"
    ass:append(
        "{\\fnMonospace\\fs" .. opt.font_size .. "\\c" .. a_clr .. a_bold .. "}" .. pad("  AUDIO", opt.col_width + 2) ..
        "{\\c" .. s_clr .. s_bold .. "}    SUBTITLES\\N")
    ass:append(
        "{\\fnMonospace\\fs" .. opt.font_size .. "\\c" .. opt.color_sep .. a_bold .. "}" ..
        string.rep("-", opt.col_width + 2) .. "{\\b0}  " .. string.rep("-", 40) .. "\\N")

    local cur_aid = mp.get_property("aid", "no")
    local cur_sid = mp.get_property("sid", "no")

    local half        = math.floor(opt.max_rows / 2) - 1
    local audio_start = math.max(1, audio_cur - half)
    local sub_start   = math.max(1, sub_cur   - half)

    for row = 0, opt.max_rows - 1 do
        local ai = audio_start + row
        local si = sub_start   + row
        local a  = audio_tracks[ai]
        local s  = sub_tracks[si]
        if not a and not s then break end

        local left
        if a then
            local text   = pad(fmt_audio(a), opt.col_width)
            local is_sel = col == "audio" and ai == audio_cur
            local is_live = tostring(a.id) == cur_aid
            if is_sel then
                left = "{\\c" .. opt.color_selected .. "}{\\alpha&H00&}⮞\\h" .. esc(text)
            else
                local clr = is_live and opt.color_active or opt.color_normal
                left = "{\\alpha&HFF&}⮞\\h{\\alpha&H00&}{\\c" .. clr .. "}" .. esc(text)
            end
        else
            left = "{\\alpha&HFF&}⮞\\h{\\alpha&H00&}" .. string.rep(" ", opt.col_width)
        end

        local right = ""
        if s then
            local text    = fmt_sub(s)
            local is_sel  = col == "sub" and si == sub_cur
            local is_live = (s.id == false and cur_sid == "no") or
                            (s.id and tostring(s.id) == cur_sid)
            if is_sel then
                right = "{\\c" .. opt.color_selected .. "}{\\alpha&H00&}⮞\\h" .. esc(text)
            else
                local clr = is_live and opt.color_active or opt.color_normal
                right = "{\\alpha&HFF&}⮞\\h{\\alpha&H00&}{\\c" .. clr .. "}" .. esc(text)
            end
        end

        ass:append("{\\b0\\fnMonospace\\fs" .. opt.font_size .. "}" .. left .. "{\\c" .. opt.color_sep .. "}  " .. right .. "\\N")
    end

    overlay.data = ass.text
    overlay:update()
end

local function bname(n) return "dynamic/" .. overlay.id .. "/" .. n end

local function nav_up()
    if col == "audio" then
        if audio_cur > 1 then audio_cur = audio_cur - 1; render() end
    else
        if sub_cur > 1 then sub_cur = sub_cur - 1; render() end
    end
end

local function nav_down()
    if col == "audio" then
        if audio_cur < #audio_tracks then audio_cur = audio_cur + 1; render() end
    else
        if sub_cur < #sub_tracks then sub_cur = sub_cur + 1; render() end
    end
end

local function switch_left()
    if col == "sub" then col = "audio"; render() end
end

local function switch_right()
    if col == "audio" then col = "sub"; render() end
end

local function apply()
    if col == "audio" then
        local t = audio_tracks[audio_cur]
        if t then mp.set_property("aid", t.id) end
    else
        local t = sub_tracks[sub_cur]
        if t then
            if t.id then
                mp.set_property("sid", t.id)
            else
                mp.set_property("sid", "no")
            end
        end
    end
    render()
end

local function close()
    active = false
    overlay:remove()
    for _, n in ipairs({ "up", "down", "left", "right", "enter", "close", "wup", "wdown", "rclick" }) do
        mp.remove_key_binding(bname(n))
    end
end

local function open()
    active    = true
    col       = "audio"
    audio_cur = 1
    sub_cur   = 1
    load_tracks()

    local cur_aid = mp.get_property("aid", "no")
    local cur_sid = mp.get_property("sid", "no")
    for i, t in ipairs(audio_tracks) do
        if tostring(t.id) == cur_aid then audio_cur = i; break end
    end
    for i, t in ipairs(sub_tracks) do
        if (t.id == false and cur_sid == "no") or
           (t.id and tostring(t.id) == cur_sid) then
            sub_cur = i; break
        end
    end

    if #audio_tracks == 0 then col = "sub" end

    mp.add_forced_key_binding("UP",         bname("up"),     nav_up,       { repeatable = true })
    mp.add_forced_key_binding("DOWN",       bname("down"),   nav_down,     { repeatable = true })
    mp.add_forced_key_binding("LEFT",       bname("left"),   switch_left)
    mp.add_forced_key_binding("RIGHT",      bname("right"),  switch_right)
    mp.add_forced_key_binding("ENTER",      bname("enter"),  apply)
    mp.add_forced_key_binding("ESC",        bname("close"),  close)
    mp.add_forced_key_binding("wheel_up",   bname("wup"),    nav_up,       { repeatable = true })
    mp.add_forced_key_binding("wheel_down", bname("wdown"),  nav_down,     { repeatable = true })
    mp.add_forced_key_binding("MBTN_RIGHT", bname("rclick"), apply)

    render()
    mp.add_timeout(0.1, function()
        if active then render() end
    end)
end

mp.add_key_binding(opt.keybind, "track-picker", function()
    if active then close() else open() end
end)

mp.register_script_message("open-track-picker", function()
    if not active then open() end
end)
