--TODO:		encoding filter

mp.msg.info("MPV-CUT LOADED")

utils = require "mp.utils"

-- Global variable to track continuous cache dumping
local continuous_cache_timer = nil
local continuous_cache_start_time = nil
local original_chapters = {}

local function create_chapter(time_pos)
    -- Check if there's an original chapter very close to this position
    for _, orig_chapter in ipairs(original_chapters) do
        if math.abs(orig_chapter.time - time_pos) < 0.1 then
            return -- Don't create a new chapter
        end
    end
    
    local curr_chapter = mp.get_property_number("chapter")
    local chapter_count = mp.get_property_number("chapter-list/count")
    local all_chapters = mp.get_property_native("chapter-list")
    
    if chapter_count == 0 then
        all_chapters[1] = {
            title = "temp_chapter",
            time = time_pos
        }
        curr_chapter = 0
    else
        for i = chapter_count, curr_chapter + 2, -1 do
            all_chapters[i + 1] = all_chapters[i]
        end
        all_chapters[curr_chapter+2] = {
            title = "temp_chapter",
            time = time_pos
        }
    end
    
    mp.set_property_native("chapter-list", all_chapters)
end

local function update_chapter_names()
    local chapter_count = mp.get_property_number("chapter-list/count")
    local all_chapters = mp.get_property_native("chapter-list")
    
    if chapter_count == 0 then
        return
    end
    
    -- Create a map of cut times to their position in cut_data._timestamps
    local time_to_index = {}
    for i, time in ipairs(cut_data._timestamps) do
        time_to_index[time] = i
    end
    
    -- Update chapter names based on cut times
    for i = 1, chapter_count do
        local chapter = all_chapters[i]
        local chapter_time = chapter.time
        
        -- Check if this chapter corresponds to a cut time
        local cut_index = nil
        for time, index in pairs(time_to_index) do
            if math.abs(time - chapter_time) < 0.1 then
                cut_index = index
                break
            end
        end
        
        if cut_index then
            local fragment_num = math.ceil(cut_index / 2)
            local is_start = (cut_index % 2 == 1)
            local point_type = is_start and "start" or "end"
            local new_title = string.format("cut_%d_%s(%s)", fragment_num, point_type, ACTION)
            chapter.title = new_title
        end
    end
    
    mp.set_property_native("chapter-list", all_chapters)
end

local function remove_chapter(time_pos)
    local chapter_count = mp.get_property_number("chapter-list/count")
    local all_chapters = mp.get_property_native("chapter-list")
    
    local chapter_to_modify = nil
    for i = 1, chapter_count do
        if all_chapters[i] and math.abs(all_chapters[i].time - time_pos) < 0.1 then
            chapter_to_modify = i
            break
        end
    end
    
    if chapter_to_modify then
        -- Check if this position matches an original chapter
        local is_original_chapter = false
        local original_title = nil
        
        for _, orig_chapter in ipairs(original_chapters) do
            if math.abs(orig_chapter.time - time_pos) < 0.1 then
                is_original_chapter = true
                original_title = orig_chapter.title
                break
            end
        end
        
        if is_original_chapter then
            -- Create a fresh chapter object:
            all_chapters[chapter_to_modify] = {
                title = original_title,
                time = time_pos
            }
            mp.set_property_native("chapter-list", all_chapters)
        else
            -- Remove the chapter entirely (it was created by this script)
            for i = chapter_to_modify, chapter_count - 1 do
                all_chapters[i] = all_chapters[i + 1]
            end
            all_chapters[chapter_count] = nil
            mp.set_property_native("chapter-list", all_chapters)
        end
    end
end

local result = mp.command_native({ name = "subprocess", args = {"ffmpeg"}, playback_only = false, capture_stdout = true, capture_stderr = true })
if result.status ~= 1 then
    mp.osd_message("FFmpeg failed to run, please check installation", 5)
end

local function to_hms(seconds)
    local ms = math.floor((seconds - math.floor(seconds)) * 1000)
    local secs = math.floor(seconds)
    local mins = math.floor(secs / 60)
    secs = secs % 60
    local hours = math.floor(mins / 60)
    mins = mins % 60
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

local function next_table_key(t, current)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for i = 1, #keys do
        if keys[i] == current then
            return keys[(i % #keys) + 1]
        end
    end
    return keys[1]
end

local function is_url(path)
    return path:match("^https?://") or path:match("^acestream://")
end

local function get_unique_filename(base_path)
    local counter = 0
    local test_path = base_path
    
    while utils.file_info(test_path) do
        counter = counter + 1
        local dir, name_with_ext = utils.split_path(test_path)
        local name, ext = name_with_ext:match("^(.+)(%..+)$")
        if not name then
            name = name_with_ext
            ext = ""
        end
        test_path = utils.join_path(dir, string.format("%s(%d)%s", name, counter, ext))
    end
    
    return test_path
end

local function generate_output_filename(d, fragments, action_suffix)
    local base_name = mp.get_property("filename/no-ext")
    
    local time_parts = {}
    for _, frag in ipairs(fragments) do
        table.insert(time_parts, to_hms(frag.start) .. "-" .. to_hms(frag.end_time))
    end
    
    local time_string = table.concat(time_parts, "_")
    local filename = string.format("%s_%s_%s%s", base_name, time_string, action_suffix, d.ext)
    
    return get_unique_filename(utils.join_path(d.indir, filename))
end

local function stop_continuous_cache()
    if continuous_cache_timer then
        continuous_cache_timer:kill()
        continuous_cache_timer = nil
        continuous_cache_start_time = nil
        mp.osd_message("Continuous cache recording stopped")
        return true
    end
    return false
end

-- Forward declaration for get_data function
local get_data

local function start_continuous_cache(start_time)
    if not is_url(mp.get_property("path")) then
        mp.osd_message("ERROR: Continuous cache only works with online videos")
        return
    end
    
    -- Stop any existing continuous cache
    stop_continuous_cache()
    
    local d = get_data()
    local base_name = mp.get_property("filename/no-ext")
    local cache_filename = string.format("%s_STREAM_CACHE.mkv", base_name)
    local full_path = get_unique_filename(utils.join_path(d.indir, cache_filename))
    continuous_cache_start_time = start_time
    
    mp.osd_message(string.format("Starting continuous cache from %.2f seconds", start_time))
    
    -- Function to perform continuous cache dump
    local function dump_cache_segment()
        local current_time = mp.get_property_number("time-pos")
        if not current_time then
            return
        end
        
        -- Only dump if we have new cache data beyond our start time
        if current_time > continuous_cache_start_time then
            local command = {
                name = "dump-cache",
                start = tostring(continuous_cache_start_time),
                ["end"] = tostring(current_time),
                filename = full_path
            }
            
            mp.command_native_async(command, function(success, result)
                if not success then
                    mp.msg.warn("Cache dump segment failed")
                end
            end)
        end
    end
    
    -- Set up timer to continuously dump cache (every 5 seconds)
    continuous_cache_timer = mp.add_periodic_timer(5.0, dump_cache_segment)
    
    -- Initial dump
    dump_cache_segment()
end

ACTIONS = {}

ACTIONS.COPY = function(d)
    local args = {
        "ffmpeg",
        "-nostdin", "-y",
        "-loglevel", "error",
        "-ss", d.start_time,
        "-t", d.duration,
        "-i", d.inpath,
        "-c", "copy",
        "-map", "0",
        "-dn",
        "-avoid_negative_ts", "make_zero",
        d.output_path
    }
    mp.command_native_async({
        name = "subprocess",
        args = args,
        playback_only = false,
    }, function() mp.osd_message("Done") end)
end

ACTIONS.ENCODE = function(d)
    local args = {
        "ffmpeg",
        "-nostdin", "-y",
        "-loglevel", "error",
        "-ss", d.start_time,
        "-t", d.duration,
        "-i", d.inpath,
        "-c:v", "libx264",
        "-b:v", "1200k",
        "-maxrate", "1500k",
        "-bufsize", "2400k",
        "-pix_fmt", "yuv420p",
        "-preset", "fast",
        "-c:a", "aac",
        "-b:a", "128k",
        d.output_path
    }
    mp.command_native_async({
        name = "subprocess",
        args = args,
        playback_only = false,
    }, function() mp.osd_message("Done") end)
end

ACTIONS.CACHE = function(d)
    if not is_url(d.inpath) then
        mp.osd_message("ERROR: CACHE action only works with online videos")
        return
    end
    
    local command = {
        name = "dump-cache",
        start = d.start_time,
        ["end"] = d.end_time,
        filename = d.output_path
    }
    
    mp.command_native_async(command, function(success, result)
        if success then
            mp.osd_message("Done")
        else
            mp.osd_message("Cache dump failed")
        end
    end)
end

ACTION = "COPY"
CHANNEL = 1
CHANNEL_NAMES = {}

KEY_CUT = "c"
KEY_CANCEL_CUT = "C"
KEY_CYCLE_ACTION = "ctrl+a"
KEY_EXECUTE_CUT = "ctrl+c"
KEY_CLEAR_ALL = "ctrl+C"

home_config = mp.command_native({"expand-path", "~/.config/mpv-cut/config.lua"})
if pcall(require, "config") then
    mp.msg.info("Loaded config file from script dir")
elseif pcall(dofile, home_config) then
    mp.msg.info("Loaded config file from " .. home_config)
else
    mp.msg.info("No config loaded")
end

for i, v in ipairs(CHANNEL_NAMES) do
    CHANNEL_NAMES[i] = string.gsub(v, ":", "-")
end

if not ACTIONS[ACTION] then 
    ACTION = next_table_key(ACTIONS, nil) 
end

-- Fragment management using similar approach to mpv-splice
cut_data = {
    _timestamps = {},
    
    _pieces = function(self)
        return #self._timestamps
    end,
    
    pieces = function(self)
        return self:_pieces()
    end,
    
    _pairs = function(self)
        return math.floor(self:_pieces() / 2)
    end,
    
    _has_incomplete_fragment = function(self)
        return not (self:_pieces() % 2 == 0)
    end,
    
    _put_time = function(self, value)
        table.insert(self._timestamps, value)
    end,
    
    add_time = function(self)
        local time = mp.get_property_number("time-pos")
        
        if self:_has_incomplete_fragment() then
            -- Setting end time
            local start_time = self._timestamps[#self._timestamps]
            if time < start_time then
                -- Auto-sort: remove start, add new time as start, then add old start as end
                table.remove(self._timestamps)
                self:_put_time(time)
                self:_put_time(start_time)
                create_chapter(time)
                update_chapter_names()
                mp.osd_message("Fragment " .. self:_pairs() .. " end set (auto-sorted): Start=" .. string.format("%.2f", time) .. " End=" .. string.format("%.2f", start_time))
            else
                self:_put_time(time)
                create_chapter(time)
                update_chapter_names()
                mp.osd_message("Fragment " .. self:_pairs() .. " end set: " .. string.format("%.2f", time))
            end
        else
            -- Setting start time
            self:_put_time(time)
            create_chapter(time)
            update_chapter_names()
            mp.osd_message("Fragment " .. (self:_pairs() + 1) .. " start set: " .. string.format("%.2f", time))
        end
    end,
    
    as_pairs = function(self)
        local pairs = {}
        for i = 1, self:_pieces(), 2 do
            if self._timestamps[i + 1] then
                table.insert(pairs, {
                    start = self._timestamps[i],
                    end_time = self._timestamps[i + 1]
                })
            end
        end
        return pairs
    end,
    
    remove_at_time = function(self, time_pos)
        for i = 1, #self._timestamps do
            if math.abs(self._timestamps[i] - time_pos) < 0.1 then
                -- Remove from timestamps FIRST
                table.remove(self._timestamps, i)

                -- Then remove/restore the chapter
                remove_chapter(time_pos)

                -- Update chapter names (now that timestamp is gone)
                update_chapter_names()

                local fragment_num = math.ceil(i / 2)
                local point_type = (i % 2 == 1) and "start" or "end"
                mp.osd_message("Fragment " .. fragment_num .. " " .. point_type .. " removed")
                return true
            end
        end
        return false
    end,
    
    clear = function(self)
        for _, time in ipairs(self._timestamps) do
            remove_chapter(time)
        end
        self._timestamps = {}
    end
}

mp.register_event("file-loaded", function()
    original_chapters = mp.get_property_native("chapter-list") or {}
end)

local function get_current_channel_name()
    return CHANNEL_NAMES[CHANNEL] or tostring(CHANNEL)
end

get_data = function()
    local d = {}
    d.inpath = mp.get_property("path")
    if is_url(d.inpath) then
        d.indir = mp.command_native({"expand-path", "~/Videos"})
        d.ext = ".mkv"
    else
        d.indir = utils.split_path(d.inpath)
        d.ext = mp.get_property("filename"):match("^.+(%..+)$") or ".mkv"
    end
    d.channel = get_current_channel_name()
    return d
end

local function get_times(start_time, end_time)
    local d = {}
    d.start_time = tostring(start_time)
    d.end_time = tostring(end_time)
    d.duration = tostring(end_time - start_time)
    return d
end

local function cycle_action()
    ACTION = next_table_key(ACTIONS, ACTION)
    -- Update chapter names when action changes
    update_chapter_names()
    mp.osd_message("ACTION: " .. ACTION)
end

local function cut_single_fragment(start_time, end_time)
    local d = get_data()
    local t = get_times(start_time, end_time)
    for k, v in pairs(t) do 
        d[k] = v 
    end
    
    -- Generate output filename
    local fragments = {{start = start_time, end_time = end_time}}
    d.output_path = generate_output_filename(d, fragments, ACTION)
    
    ACTIONS[ACTION](d)
end

local function make_temp_dir()
    local tmp_dir = os.tmpname()
    os.remove(tmp_dir) -- Remove the file created by tmpname
    
    -- Create directory using mkdir command
    local mkdir_cmd = string.format('mkdir "%s"', tmp_dir)
    os.execute(mkdir_cmd)
    
    return tmp_dir
end

local function create_concat_file(tmp_dir, fragment_files)
    local concat_file_path = utils.join_path(tmp_dir, "concat.txt")
    local file = io.open(concat_file_path, "w")
    
    for _, fragment_file in ipairs(fragment_files) do
        file:write(string.format("file '%s'\n", fragment_file))
    end
    
    file:close()
    return concat_file_path
end

local function cut_multiple_fragments_cache(fragments)
    if not is_url(mp.get_property("path")) then
        mp.osd_message("ERROR: Multiple fragment cache cutting only works with online videos")
        return
    end
    
    local d = get_data()
    local output_path = generate_output_filename(d, fragments, ACTION)
    
    local tmp_dir = make_temp_dir()
    local fragment_files = {}
    local completed_count = 0
    local total_fragments = #fragments
    
    mp.osd_message(string.format("Creating %d cache fragments...", total_fragments))
    
    -- Function to handle completion of all fragments
    local function try_concatenate()
        if completed_count == total_fragments then
            mp.osd_message("All cache fragments completed. Starting concatenation...")
            
            -- Create concat file
            local concat_file_path = create_concat_file(tmp_dir, fragment_files)
            
            local concat_args = {
                "ffmpeg",
                "-nostdin", "-y",
                "-loglevel", "error",
                "-f", "concat",
                "-safe", "0",
                "-i", concat_file_path,
                "-c", "copy",
                output_path
            }
            
            mp.command_native_async({
                name = "subprocess",
                args = concat_args,
                playback_only = false,
            }, function(success, result)
                if success and result.status == 0 then
                    mp.osd_message("Cache concatenation completed successfully")
                    
                    -- Clean up temporary files
                    for _, temp_file in ipairs(fragment_files) do
                        os.remove(temp_file)
                    end
                    os.execute(string.format('rm -rf "%s"', tmp_dir))
                else
                    mp.osd_message("Error during cache concatenation - temporary files preserved")
                end
            end)
        end
    end
    
    -- Start all cache dumps
    for i, frag in ipairs(fragments) do
        local t = get_times(frag.start, frag.end_time)
        
        -- Create temporary fragment filename
        local fragment_filename = string.format("cache_fragment_%02d.mkv", i)
        local fragment_path = utils.join_path(tmp_dir, fragment_filename)
        table.insert(fragment_files, fragment_path)
        
        local command = {
            name = "dump-cache",
            start = t.start_time,
            ["end"] = t.end_time,
            filename = fragment_path
        }
        
        mp.command_native_async(command, function(success, result)
            if success then
                completed_count = completed_count + 1
                mp.osd_message(string.format("Fragment %d/%d cached successfully", completed_count, total_fragments))
                try_concatenate()
            else
                mp.osd_message(string.format("Fragment %d cache failed", i))
                -- Still increment to avoid hanging, but mark as failed
                completed_count = completed_count + 1
                try_concatenate()
            end
        end)
    end
end

local function cut_multiple_fragments(fragments)
    -- Check if we're using cache action
    if ACTION == "CACHE" then
        cut_multiple_fragments_cache(fragments)
        return
    end
    
    local d = get_data()
    local output_path = generate_output_filename(d, fragments, ACTION)
    local tmp_dir = make_temp_dir()
    local fragment_files = {}
    
    mp.osd_message("Creating temporary fragments...")
    
    -- Step 1: Create individual fragment files
    for i, frag in ipairs(fragments) do
        local fragment_filename = string.format("fragment_%d%s", i, d.ext)
        local fragment_path = utils.join_path(tmp_dir, fragment_filename)
        
        local cut_args = {
            "ffmpeg",
            "-nostdin", "-y",
            "-loglevel", "error",
            "-ss", tostring(frag.start),
            "-t", tostring(frag.end_time - frag.start),
            "-i", d.inpath,
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            fragment_path
        }
        
        -- Execute fragment cut synchronously
        local result = mp.command_native({
            name = "subprocess",
            args = cut_args,
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true
        })
        
        if result.status == 0 then
            table.insert(fragment_files, fragment_path)
        else
            mp.osd_message("Error creating fragment " .. i)
            -- Cleanup and return
            os.execute(string.format('rm -rf "%s"', tmp_dir))
            return
        end
    end
    
    -- Step 2: Create concat file
    local concat_file_path = create_concat_file(tmp_dir, fragment_files)
    
    -- Step 3: Concatenate all fragments
    local concat_args = {
        "ffmpeg",
        "-nostdin", "-y",
        "-loglevel", "error",
        "-f", "concat",
        "-safe", "0",
        "-i", concat_file_path,
        "-c", "copy",
        output_path
    }
    
    mp.osd_message("Concatenating fragments...")
    
    mp.command_native_async({
        name = "subprocess",
        args = concat_args,
        playback_only = false,
    }, function(success, result)
        -- Cleanup temporary directory
        os.execute(string.format('rm -rf "%s"', tmp_dir))
        
        if success and result.status == 0 then
            mp.osd_message("Done")
        else
            mp.osd_message("Error during concatenation")
        end
    end)
end

local function dump_full_cache()
    if not is_url(mp.get_property("path")) then
        mp.osd_message("ERROR: Cache dump only works with online videos")
        return
    end
    
    local cache_time = mp.get_property_number("demuxer-cache-time")
    local cache_duration = mp.get_property_number("demuxer-cache-duration")
    local cache_state = mp.get_property_native("demuxer-cache-state")
    local time_pos = mp.get_property_number("time-pos")
    
    local cache_start = nil
    local cache_end = nil
    
    -- Method 1: Try seekable-ranges
    if cache_state and cache_state["seekable-ranges"] and #cache_state["seekable-ranges"] > 0 then
        for i, range in ipairs(cache_state["seekable-ranges"]) do
            if not cache_start or range.start < cache_start then
                cache_start = range.start
            end
            if not cache_end or range["end"] > cache_end then
                cache_end = range["end"]
            end
        end
    end
    
    -- Method 2: Fallback to cache time + duration
    if not cache_start or not cache_end then
        if cache_time and cache_duration then
            cache_start = cache_time
            cache_end = cache_time + cache_duration
        end
    end
    
    -- Method 3: Last resort - use current time and estimate
    if not cache_start or not cache_end then
        if time_pos then
            cache_start = math.max(0, time_pos - 30) -- Assume 30s before current
            cache_end = time_pos + 30 -- Assume 30s after current
        end
    end
    
    if not cache_start or not cache_end or cache_start >= cache_end then
        mp.osd_message("ERROR: Could not determine any valid cache range")
        return
    end
    
    local d = get_data()
    local base_name = mp.get_property("filename/no-ext")
    local cache_filename = string.format("%s_FULL_CACHE.mkv", base_name)
    local full_path = get_unique_filename(utils.join_path(d.indir, cache_filename))
    
    mp.osd_message(string.format("Using cache range: %.2f to %.2f seconds (%.2f minutes)", 
          cache_start, cache_end, (cache_end - cache_start) / 60))
    
    local command = {
        name = "dump-cache",
        start = tostring(cache_start),
        ["end"] = tostring(cache_end),
        filename = full_path
    }
    
    mp.osd_message("Dumping full cache...")
    mp.command_native_async(command, function(success, result)
        if success then
            mp.osd_message("Full cache dumped successfully")
        else
            mp.osd_message("Full cache dump failed")
        end
    end)
end

local function put_time()
    cut_data:add_time()
end

local function cancel_cut()
    local time_pos = mp.get_property_number("time-pos")
    
    if cut_data:remove_at_time(time_pos) then
        -- Successfully removed
    else
        mp.osd_message("Not at cutting position - no changes made")
    end
end

local function clear_all()
    -- Stop continuous cache if running
    stop_continuous_cache()
    
    -- Clear our cut data
    cut_data:clear()
    
    -- Restore original chapters instead of just clearing
    mp.set_property_native("chapter-list", original_chapters)
    
    mp.osd_message("All fragments, chapters, and continuous recording cleared")
end

local function execute_cut()
    -- Special case: if CACHE action and no fragments, dump full cache
    if ACTION == "CACHE" and cut_data:pieces() == 0 then
        dump_full_cache()
        return
    end
    
    -- Special case: if CACHE action and only one incomplete fragment (start only), start continuous cache
    if ACTION == "CACHE" and cut_data:_has_incomplete_fragment() and cut_data:pieces() == 1 then
        -- Check if continuous cache is already running
        if continuous_cache_timer then
            -- Stop continuous cache
            stop_continuous_cache()
        else
            -- Start continuous cache from the start time
            start_continuous_cache(cut_data._timestamps[1])
        end
        return
    end
    
    -- For non-CACHE actions, check for incomplete fragments
    if cut_data:_has_incomplete_fragment() then
        mp.osd_message("ERROR: Incomplete fragment - missing end time")
        return
    end
    
    local fragments = cut_data:as_pairs()
    if #fragments == 0 then
        mp.osd_message("ERROR: No fragments to cut")
        return
    end
    
    -- Sort fragments by start time
    table.sort(fragments, function(a, b) return a.start < b.start end)
    
    if #fragments == 1 then
        cut_single_fragment(fragments[1].start, fragments[1].end_time)
    else
        cut_multiple_fragments(fragments)
    end
    
    cut_data:clear()
    -- Restore original chapters after clearing cut data
    mp.set_property_native("chapter-list", original_chapters)
    
    mp.osd_message("Cut executed successfully")
end

mp.add_key_binding(KEY_CUT, "cut", put_time)
mp.add_key_binding(KEY_CANCEL_CUT, "cancel_cut", cancel_cut)
mp.add_key_binding(KEY_CYCLE_ACTION, "cycle_action", cycle_action)
mp.add_key_binding(KEY_EXECUTE_CUT, "execute_cut", execute_cut)
mp.add_key_binding(KEY_CLEAR_ALL, "clear_all", clear_all)