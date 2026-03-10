local utils = require("mp.utils")
local mpopts = require("mp.options")
local assdraw = require("mp.assdraw")
local overlay = mp.create_osd_overlay("ass-events")

SEPARATOR = "/"

local settings = {
    dynamic_binds = true,
    navigator_mainkey = "TAB",
    key_navclose = "ESC",
    defaultpath = "/home/pavel/Videos/",
    forcedefault = false,
    favorites = {
        '/home/pavel/Downloads/',
        '/home/pavel/Videos/',
    },
    visible_item_count = 25,
    style_ass_tags = "{\\fs20\\c&HFFFFFF&}",
    name_prefix = "",
    selection_prefix = "",
}

mpopts.read_options(settings)

-- Define playable video and audio formats that mpv supports
local playable_formats = {
    -- Video formats
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'ogv', 'm4v', 'mpg', 'mpeg',
    'ts', 'mts', 'm2ts', 'vob', 'asf', 'rm', 'rmvb', '3gp', 'f4v', 'divx', 'xvid',
    -- Audio formats
    'mp3', 'flac', 'wav', 'aac', 'ogg', 'opus', 'wma', 'm4a', 'ac3', 'dts', 'ape',
    'wv', 'tta', 'aiff', 'au', 'ra', 'mka', 'mpc', 'amr', 'awb',
    -- Container formats that can contain video/audio
    'matroska', 'webm', 'ogg', 'nut', 'nsv'
}

-- Create lookup table for playable formats
local playable_lookup = {}
for _, ext in ipairs(playable_formats) do
    playable_lookup[ext:lower()] = true
end

local audio_exts = {
    'mp3', 'flac', 'wav', 'aac', 'ogg', 'opus', 'wma', 'm4a', 'ac3', 'dts', 'ape',
    'wv', 'tta', 'aiff', 'au', 'ra', 'mka', 'mpc', 'amr', 'awb'
}
local audio_lookup = {}
for _, ext in ipairs(audio_exts) do
    audio_lookup[ext] = true
end

local function is_audio_file(name)
    local ext = name:match("^.+%.(.+)$")
    return ext and audio_lookup[ext:lower()]
end

-- Search functionality variables
local current_pattern = ""
local grepped_arr = {}
local grepped_pattern = ""

function escapepath(dir, escapechar)
    return string.gsub(dir, escapechar, '\\' .. escapechar)
end

function stripdoubleslash(dir)
    if (string.sub(dir, -2) == "//") then
        return string.sub(dir, 1, -2)
    else
        return dir
    end
end

function os.capture(cmd, raw)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    return string.sub(s, 0, -2)
end

-- Function to check if a file is playable by mpv
function is_playable_file(filename)
    local ext = filename:match("^.+%.(.+)$")
    if not ext then return false end
    ext = ext:lower()

    -- Check if it's a torrent file (keep these)
    if ext == "torrent" then return true end

    -- Check if it's a playable media file
    return playable_lookup[ext] or false
end

dir = nil
path = nil
cursor = 1
length = 0

-- Function to underline matching search patterns
local function underline_matches(text, pattern)
    if pattern == "" then return text end
    local lower_text = text:lower()
    local lower_pattern = pattern:lower()
    local result = ""
    local pos = 1
    while true do
        local start_pos, end_pos = lower_text:find(lower_pattern, pos, true)
        if not start_pos then break end
        result = result .. text:sub(pos, start_pos - 1) .. "{\\u1}" .. text:sub(start_pos, end_pos) .. "{\\u0}"
        pos = end_pos + 1
    end
    result = result .. text:sub(pos)
    return result
end

function handler()
    add_keybinds()
    local ass = assdraw.ass_new()
    ass:new_event()
    ass:append("{\\an7}")
    ass:append("\\N\\N")

    if not path then
        local current_path = mp.get_property("path", "")
        local is_web_link = current_path:match("^https?://") or current_path:match("^acestream://")
        if is_web_link or settings.forcedefault then
            if is_web_link then
                local source_torrent = mp.get_property_native("user-data/webtorrent-source", "")
                local source_dir = source_torrent ~= "" and source_torrent:match("^(.*)/[^/]+$")
                path = source_dir and (source_dir .. "/") or settings.defaultpath
            else
                path = settings.defaultpath
            end
        else
            if current_path ~= "" and not settings.forcedefault then
                local workingdir = mp.get_property("working-directory")
                local playfilename = mp.get_property("filename")
                local playpath = mp.get_property("path")
                local firstchar = string.sub(playpath, 1, 1)
                path = string.sub(playpath, 1, string.len(playpath) - string.len(playfilename))
                if firstchar ~= "/" then
                    path = workingdir .. "/" .. path
                end
                path = resolvedir(path)
                if (not isfolder(path)) then
                    path = workingdir
                end
            else
                path = settings.defaultpath
            end
        end
        dir, length = scandirectory(path)
        cursor = 1
    end

    -- Filter directory based on search pattern
    if current_pattern == "" then
        grepped_arr = {}
        for i = 1, #dir do
            grepped_arr[#grepped_arr + 1] = { index = i, item = dir[i] }
        end
        grepped_pattern = current_pattern
    elseif grepped_pattern ~= current_pattern then
        grepped_arr = {}
        grepped_pattern = current_pattern
        cursor = 1
        for i = 1, #dir do
            local item = dir[i]
            local name = item.name
            local e, match = pcall(string.match, name:lower(), current_pattern:lower())
            if match and e then
                grepped_arr[#grepped_arr + 1] = { index = i, item = item }
            elseif not e then
                break
            end
        end
    end

    local display_path = path
    if current_pattern ~= "" then
        display_path = path .. current_pattern
    end
    ass:append("{\\fs30\\c&HFFCC00&\\b1}" .. display_path .. "\\N")
    ass:append(
        "{\\fs20\\c&HFFFFFF&}-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------\\N")

    if #grepped_arr == 0 then
        ass:append("{\\fs20\\c&HFFFFFF&}No matching items\\N")
    else
        local playing_path = mp.get_property("path")

        local max_lines = settings.visible_item_count
        local start = math.max(1, cursor - math.floor((max_lines - 1) / 2))
        local end_idx = math.min(#grepped_arr, start + max_lines - 1)
        if end_idx - start < max_lines - 1 then
            start = math.max(1, end_idx - max_lines + 1)
        end

        for i = start, end_idx do
            local entry = grepped_arr[i]
            local item = entry.item
            local is_selected = (i == cursor)

            if not item then break end

            local display_name = item.name
            -- Apply search highlighting
            if current_pattern ~= "" then
                display_name = underline_matches(item.name, current_pattern)
            end

            if #display_name > 100 then
                display_name = display_name:sub(1, 97) .. "..."
            end

            local item_path = utils.join_path(path, item.name)
            local abs_playing = playing_path
            if abs_playing and not abs_playing:match("^/") and not abs_playing:match("://") then
                abs_playing = mp.get_property("working-directory", "") .. "/" .. abs_playing
            end
            local is_playing = abs_playing and item_path == abs_playing
            if not is_playing and abs_playing and abs_playing:match("^https?://") then
                local source_torrent = mp.get_property_native("user-data/webtorrent-source", "")
                if source_torrent ~= "" then
                    is_playing = (source_torrent == item_path)
                end
            end

            -- Set the color for the entire line
            if is_selected then
                ass:append("{\\c&H88E7FC&}")
            elseif is_playing then
                ass:append("{\\c&HFFCC00&}")
            else
                ass:append("{\\c&HFFFFFF&}")
            end

            -- Append the selection arrow: visible if selected, transparent otherwise
            if is_selected then
                ass:append("{\\alpha&H00&}󰋇  ")
            else
                ass:append("{\\alpha&HFF&}󰋇  ")
            end

            -- Add type icon
            if item.is_dir then
                ass:append("{\\alpha&H00&}  ") -- Visible folder arrow
            elseif item.name:lower():match("%.torrent$") then
                ass:append("{\\alpha&H00&}  ") -- torrent
            elseif is_audio_file(item.name) then
                ass:append("{\\alpha&H00&}  ") -- audio
            else
                ass:append("{\\alpha&H00&}󱜆  ") -- video
            end
            local status_indicator = is_playing and "  󰊼" or ""
            ass:append("{\\alpha&H00&} " .. display_name .. status_indicator .. "\\N")
        end
    end

    overlay.data = ass.text
    overlay:update()
end

function navdown()
    if #grepped_arr == 0 then return end
    if cursor < #grepped_arr then
        cursor = cursor + 1
        handler()
    end
end

function navup()
    if #grepped_arr == 0 then return end
    if cursor > 1 then
        cursor = cursor - 1
        handler()
    end
end

function navigate(direction, modifier)
    if #grepped_arr == 0 then return end

    if modifier == "shift" then
        -- Jump to first or last
        if direction < 0 then
            cursor = 1
        else
            cursor = #grepped_arr
        end
    elseif modifier == "ctrl" then
        -- Move in steps of 10
        cursor = cursor + (direction * 10)
        cursor = math.max(1, math.min(cursor, #grepped_arr))
    else
        -- Normal movement
        cursor = cursor + direction
        cursor = math.max(1, math.min(cursor, #grepped_arr))
    end

    handler()
end

function movepageup()
    navigate(-1)
end

function movepagedown()
    navigate(1)
end

-- Search input functions
local function backspace()
    current_pattern = current_pattern:sub(1, -2)
    handler()
end

local function clear_search()
    current_pattern = ""
    handler()
end

-- Handle search input
local function handle_input(input)
    if input.event == "press" or input.event == "down" or input.event == "repeat" then
        local key = input.key_text
        if key == "[" then cyclefavorite(-1); return end
        if key == "]" then cyclefavorite(1);  return end
        current_pattern = current_pattern .. key
        handler()
    end
end

function delete_current_file()
    if #grepped_arr == 0 then return end
    local entry = grepped_arr[cursor]
    local item = entry.item
    if not item or not path then
        mp.osd_message("No item selected")
        return
    end
    local full_path = utils.join_path(path, item.name)
    local file_info = utils.file_info(full_path)
    if not file_info then
        mp.osd_message("Path not found: " .. full_path)
        return
    end
    local cmd_args = {}
    if file_info.is_dir then
        cmd_args = { "rm", "-rf", "--", full_path }
    else
        cmd_args = { "rm", "-f", "--", full_path }
    end
    local result = utils.subprocess({
        args = cmd_args,
        cancellable = false
    })
    if result.status == 0 then
        dir, length = scandirectory(path)
        -- Reset search state to refresh filtered array
        current_pattern = ""
        grepped_arr = {}
        grepped_pattern = ""
        if cursor > length and length > 0 then
            cursor = length
        elseif length == 0 then
            cursor = 1
        end
        handler()
    else
        mp.msg.error("Deletion failed: " .. (result.stderr or result.error))
        mp.osd_message(("Failed to delete %s (error %d)"):format(item.name, result.status))
    end
end

function opendir()
    if #grepped_arr == 0 then return end
    local entry = grepped_arr[cursor]
    local item = entry.item
    if item then
        local filepath = utils.join_path(path, item.name)

        -- If it's a directory, navigate into it instead of trying to play
        if item.is_dir then
            local newdir = stripdoubleslash(filepath .. "/")
            changepath(newdir)
            return
        end

        -- If it's the currently-playing multi-file torrent, open playlist view
        if item.name:lower():match("%.torrent$") then
            local source_torrent = mp.get_property_native("user-data/webtorrent-source", "")
            if source_torrent == filepath then
                local pl = mp.get_property_native("playlist", {})
                if #pl > 1 then
                    suspend_navigator()
                    open_playlist()
                    return
                end
            end
        end

        -- If it's a file, play it
        remove_keybinds()
        mp.commandv("loadfile", filepath, "replace")
        mp.set_property("pause", "no")
    end
end

function changepath(args)
    path = args
    dir, length = scandirectory(path)
    cursor = 1
    -- Reset search state when changing path
    current_pattern = ""
    grepped_arr = {}
    grepped_pattern = ""
    handler()
end

function parentdir()
    local child_name = path:gsub('/*$', ''):match('[^/]+$')
    local parent = stripdoubleslash(os.capture('cd "' ..
        escapepath(path, '"') .. '" 2>/dev/null && cd .. 2>/dev/null && pwd') .. "/")
    changepath(parent)
    if child_name then
        for i, entry in ipairs(grepped_arr) do
            if entry.item.name == child_name then
                cursor = i
                handler()
                break
            end
        end
    end
end

function resolvedir(dir)
    local safedir = escapepath(dir, '"')
    local resolved = stripdoubleslash(os.capture('cd "' .. safedir .. '" 2>/dev/null && pwd') .. "/")
    return resolved
end

function isfolder(dir)
    local lua51returncode, _, lua52returncode = os.execute('test -d "' .. escapepath(dir, '"') .. '"')
    return lua51returncode == 0 or lua52returncode == 0
end

function scandirectory(searchdir)
    local items = {}
    local popen, err = io.popen('ls -1vp "' .. escapepath(searchdir, '"') .. '" 2>/dev/null')
    if popen then
        for direntry in popen:lines() do
            local is_dir = direntry:sub(-1) == '/'
            local name = is_dir and direntry:sub(1, -2) or direntry

            -- Include all directories
            if is_dir then
                table.insert(items, { name = name, is_dir = true })
            -- Include only playable files (video, audio, torrents, subtitles)
            elseif is_playable_file(name) then
                table.insert(items, { name = name, is_dir = false })
            end
        end
        popen:close()
    else
        mp.msg.error("Could not scan for files: " .. (err or ""))
    end

    -- Custom sorting: folders first, then torrents, then everything else
    table.sort(items, function(a, b)
        local a_type = a.is_dir and 1 or (a.name:lower():match("%.torrent$") and 2 or 3)
        local b_type = b.is_dir and 1 or (b.name:lower():match("%.torrent$") and 2 or 3)

        if a_type ~= b_type then
            return a_type < b_type
        end

        return string.lower(a.name) < string.lower(b.name)
    end)

    return items, #items
end

local function find_playing_cursor()
    if #grepped_arr == 0 or not path then return nil end
    local playing_path = mp.get_property("path")
    if not playing_path then return nil end

    local abs_playing = playing_path
    if not abs_playing:match("^/") and not abs_playing:match("://") then
        abs_playing = mp.get_property("working-directory", "") .. "/" .. abs_playing
    end

    local match_path = abs_playing
    if abs_playing:match("^https?://") then
        local source_torrent = mp.get_property_native("user-data/webtorrent-source", "")
        if source_torrent ~= "" then match_path = source_torrent end
    end

    for i, entry in ipairs(grepped_arr) do
        if utils.join_path(path, entry.item.name) == match_path then
            return i
        end
    end
    return nil
end

-- ─── Playlist (torrent multi-file view) ──────────────────────────────────────
local playlist_visible = false
local pl_selected = 1
local pl_pattern = ""
local pl_grepped_arr = {}
local pl_grepped_pattern = ""

local function render_playlist()
    local pl = mp.get_property_native("playlist", {})
    local playing_pos = mp.get_property_number("playlist-pos", -1) + 1
    local ass = assdraw.ass_new()
    ass:new_event()
    ass:append("{\\an7}")
    ass:append("\\N\\N")

    local source_torrent = mp.get_property_native("user-data/webtorrent-source", "")
    local header_text = source_torrent ~= "" and source_torrent or "Playlist"
    if pl_pattern ~= "" then header_text = header_text .. pl_pattern end
    ass:append("{\\fs30\\c&HFFCC00&\\b1}" .. header_text .. "\\N")
    ass:append("{\\fs20\\c&HFFFFFF&}-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------\\N")

    if pl_pattern == "" then
        pl_grepped_arr = {}
        for i = 1, #pl do
            pl_grepped_arr[#pl_grepped_arr + 1] = { index = i, item = pl[i] }
        end
        pl_grepped_pattern = pl_pattern
    elseif pl_grepped_pattern ~= pl_pattern then
        pl_grepped_arr = {}
        pl_grepped_pattern = pl_pattern
        pl_selected = 1
        for i = 1, #pl do
            local item = pl[i]
            local title = item.title or item.filename:gsub("^.+[\\/]", "")
            local e, match = pcall(string.match, title:lower(), pl_pattern:lower())
            if match and e then
                pl_grepped_arr[#pl_grepped_arr + 1] = { index = i, item = item }
            elseif not e then break end
        end
    end

    if #pl_grepped_arr == 0 then
        ass:append("{\\fs20\\c&HFFFFFF&}No matching items\\N")
    else
        local max_lines = settings.visible_item_count
        local start = math.max(1, pl_selected - math.floor((max_lines - 1) / 2))
        local end_idx = math.min(#pl_grepped_arr, start + max_lines - 1)
        if end_idx - start < max_lines - 1 then
            start = math.max(1, end_idx - max_lines + 1)
        end
        for i = start, end_idx do
            local entry = pl_grepped_arr[i]
            local item = entry.item
            local is_selected = (i == pl_selected)
            local is_playing = (entry.index == playing_pos)
            local title = item.title or item.filename:gsub("^.+[\\/]", "")
            local display_title = underline_matches(title, pl_pattern)
            if #display_title > 100 then display_title = display_title:sub(1, 97) .. "..." end

            if is_selected then ass:append("{\\c&H88E7FC&}")
            elseif is_playing then ass:append("{\\c&HFFCC00&}")
            else ass:append("{\\c&HFFFFFF&}") end

            if is_selected then ass:append("{\\alpha&H00&}󰋇  ")
            else ass:append("{\\alpha&HFF&}󰋇  ") end

            ass:append("{\\alpha&H00&}󱜆  ")
            local status = is_playing and "  󰊼" or ""
            ass:append("{\\alpha&H00&} " .. display_title .. status .. "\\N")
        end
    end

    overlay.data = ass.text
    overlay:update()
end

function remove_playlist_keybinds()
    overlay:remove()
    playlist_visible = false
    pl_pattern = ""
    pl_grepped_arr = {}
    pl_grepped_pattern = ""
    local binds = {
        "pl_up", "pl_down", "pl_up_shift", "pl_down_shift",
        "pl_up_ctrl", "pl_down_ctrl", "pl_select", "pl_select_right",
        "pl_to_navigator", "pl_close", "pl_backspace", "pl_clear", "pl_handle_input",
        "pl_wheel_up", "pl_wheel_down", "pl_rclick"
    }
    for _, b in pairs(binds) do mp.remove_key_binding(b) end
end

function open_playlist()
    playlist_visible = true
    pl_pattern = ""
    pl_grepped_arr = {}
    pl_grepped_pattern = ""
    local playing_pos = mp.get_property_number("playlist-pos", -1) + 1
    pl_selected = playing_pos > 0 and playing_pos or 1
    render_playlist()
    -- Adjust selection to match playing item in filtered array
    for i, entry in ipairs(pl_grepped_arr) do
        if entry.index == playing_pos then pl_selected = i; break end
    end
    render_playlist()

    local function pl_navigate(dir, mod)
        if #pl_grepped_arr == 0 then return end
        if mod == "shift" then
            pl_selected = dir < 0 and 1 or #pl_grepped_arr
        elseif mod == "ctrl" then
            pl_selected = math.max(1, math.min(pl_selected + dir * 10, #pl_grepped_arr))
        else
            pl_selected = math.max(1, math.min(pl_selected + dir, #pl_grepped_arr))
        end
        render_playlist()
    end

    local function pl_select()
        if #pl_grepped_arr == 0 then return end
        mp.commandv("playlist-play-index", pl_grepped_arr[pl_selected].index - 1)
        mp.set_property("pause", "no")
        remove_playlist_keybinds()
    end

    local function pl_go_to_navigator()
        remove_playlist_keybinds()
        open_navigator()
    end

    local function pl_handle_input(input)
        if input.event == "press" or input.event == "down" or input.event == "repeat" then
            local key = input.key_text
            if key == "[" or key == "]" then
                remove_playlist_keybinds()
                active = true
                cyclefavorite(key == "[" and -1 or 1)
                return
            end
            pl_pattern = pl_pattern .. key
            render_playlist()
        end
    end

    mp.add_forced_key_binding("UP",          "pl_up",           function() pl_navigate(-1) end,       { repeatable = true })
    mp.add_forced_key_binding("DOWN",        "pl_down",         function() pl_navigate(1) end,        { repeatable = true })
    mp.add_forced_key_binding("Shift+UP",    "pl_up_shift",     function() pl_navigate(-1, "shift") end)
    mp.add_forced_key_binding("Shift+DOWN",  "pl_down_shift",   function() pl_navigate(1,  "shift") end)
    mp.add_forced_key_binding("Ctrl+UP",     "pl_up_ctrl",      function() pl_navigate(-1, "ctrl") end, { repeatable = true })
    mp.add_forced_key_binding("Ctrl+DOWN",   "pl_down_ctrl",    function() pl_navigate(1,  "ctrl") end, { repeatable = true })
    mp.add_forced_key_binding("ENTER",       "pl_select",       pl_select)
    mp.add_forced_key_binding("RIGHT",       "pl_select_right", pl_select)
    mp.add_forced_key_binding("LEFT",        "pl_to_navigator", pl_go_to_navigator)
    mp.add_forced_key_binding("ESC",         "pl_close",        remove_playlist_keybinds)
    mp.add_forced_key_binding("BS",          "pl_backspace",    function()
        pl_pattern = pl_pattern:sub(1, -2); render_playlist()
    end, { repeatable = true })
    mp.add_forced_key_binding("Ctrl+u",      "pl_clear",        function()
        pl_pattern = ""; render_playlist()
    end)
    mp.add_forced_key_binding("any_unicode", "pl_handle_input", pl_handle_input, { repeatable = true, complex = true })
    mp.add_forced_key_binding("wheel_up",    "pl_wheel_up",     function() pl_navigate(-1) end, { repeatable = true })
    mp.add_forced_key_binding("wheel_down",  "pl_wheel_down",   function() pl_navigate(1) end,  { repeatable = true })
    mp.add_forced_key_binding("MBTN_RIGHT",  "pl_rclick",       pl_select)
end

favcursor = 0
function cyclefavorite(dir)
    local n = #settings.favorites
    if n == 0 then return end
    if favcursor == 0 then
        local cur = (path or ''):gsub('/*$', '/')
        for i, fav in ipairs(settings.favorites) do
            if fav:gsub('/*$', '/') == cur then
                favcursor = i
                break
            end
        end
    end
    favcursor = favcursor + dir
    if favcursor < 1 then favcursor = n end
    if favcursor > n then favcursor = 1 end
    changepath(settings.favorites[favcursor])
end

function add_keybinds()
    -- Arrow key navigation
    mp.add_forced_key_binding("UP",    "navup",   navup,      { repeatable = true })
    mp.add_forced_key_binding("DOWN",  "navdown", navdown,    { repeatable = true })
    mp.add_forced_key_binding("RIGHT", "navopen", opendir)
    mp.add_forced_key_binding("LEFT",  "navback", parentdir)

    -- Shift+arrow: jump to first/last
    mp.add_forced_key_binding("Shift+UP",   "nav_up_shift",   function() navigate(-1, "shift") end)
    mp.add_forced_key_binding("Shift+DOWN", "nav_down_shift", function() navigate(1,  "shift") end)

    -- Ctrl+arrow: ±10
    mp.add_forced_key_binding("Ctrl+UP",   "nav_up_ctrl",   function() navigate(-1, "ctrl") end, { repeatable = true })
    mp.add_forced_key_binding("Ctrl+DOWN", "nav_down_ctrl", function() navigate(1,  "ctrl") end, { repeatable = true })

    -- Other controls
    mp.add_forced_key_binding("ENTER", "navopen_enter", opendir)
    mp.add_forced_key_binding("DEL",    "navdelete",    delete_current_file)
    mp.add_forced_key_binding("KP_DEL","navdelete_kp", delete_current_file)
    mp.add_forced_key_binding(settings.key_navclose, "navclose", remove_keybinds)

    -- Search controls
    mp.add_forced_key_binding("BS",          "nav_backspace",    backspace,    { repeatable = true })
    mp.add_forced_key_binding("Ctrl+u",      "nav_clear",        clear_search)
    mp.add_forced_key_binding("any_unicode", "nav_handle_input", handle_input, { repeatable = true, complex = true })
    mp.add_forced_key_binding("wheel_up",    "nav_wheel_up",     navup,        { repeatable = true })
    mp.add_forced_key_binding("wheel_down",  "nav_wheel_down",   navdown,      { repeatable = true })
    mp.add_forced_key_binding("MBTN_RIGHT",  "nav_rclick",       opendir)
end

function suspend_navigator()
    overlay:remove()
    active = false
    current_pattern = ""
    grepped_arr = {}
    grepped_pattern = ""
    if settings.dynamic_binds then
        local binds = {
            'navup', 'navdown', 'navopen', 'navopen_enter', 'navback', 'navclose', 'navdelete', 'navdelete_kp',
            'nav_up_shift', 'nav_down_shift',
            'nav_up_ctrl', 'nav_down_ctrl',
            'nav_backspace', 'nav_clear', 'nav_handle_input',
            'nav_wheel_up', 'nav_wheel_down', 'nav_rclick'
        }
        for _, bind in pairs(binds) do mp.remove_key_binding(bind) end
    end
end

function remove_keybinds()
    suspend_navigator()
    path = nil
end

if not settings.dynamic_binds then
    add_keybinds()
end

function open_navigator()
    active = true
    handler()
    local new_cursor = find_playing_cursor()
    if new_cursor then
        cursor = new_cursor
        handler()
    end
end

active = false
function activate()
    if playlist_visible then
        remove_playlist_keybinds()
        return
    end
    if active then
        remove_keybinds()
        return
    end
    if mp.get_property("pause") == "no" then
        mp.set_property("pause", "yes")
    end
    local playing_path = mp.get_property("path", "")
    local pl = mp.get_property_native("playlist", {})
    if playing_path:match("^https?://") and #pl > 1 then
        open_playlist()
    else
        open_navigator()
    end
end

mp.add_key_binding(settings.navigator_mainkey, "navigator", activate)

mp.register_event("file-loaded", function()
    if active then remove_keybinds() end
    if playlist_visible then remove_playlist_keybinds() end
end)

mp.observe_property("playlist-pos", "number", function()
    if playlist_visible then render_playlist() end
end)

if mp.get_property_native("idle-active") then
    activate()
end
