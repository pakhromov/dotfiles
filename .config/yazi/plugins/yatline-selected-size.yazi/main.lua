-- Selected files component for yatline
-- Shows count and size of selected items with smart caching

local state = ya.sync(function(st)
    return st
end)

local add_file_data = ya.sync(function(st, file_path, size, count, is_dir)
    if not st.file_data then
        st.file_data = {}
    end
    st.file_data[file_path] = { size = size, count = count, is_dir = is_dir }
    ui.render()
end)

local remove_file_data = ya.sync(function(st, file_path)
    if st.file_data then
        st.file_data[file_path] = nil
    end
    ui.render()
end)

local function setup(st)
    -- Register yatline component
    if Yatline ~= nil then
        Yatline.coloreds.get["selected-files-size"] = function()
            local result = {}

            -- Initialize state if needed
            local current_state = state()
            if not current_state.file_data then
                current_state.file_data = {}
            end

            -- Get currently selected files
            local new_selection = {}
            for _, url in pairs(cx.active.selected) do
                local path = tostring(url)
                new_selection[path] = true
            end

            -- If no selection, clear cache and return nil
            if not next(new_selection) then
                if next(current_state.file_data) then
                    -- Clear all cached data
                    for path in pairs(current_state.file_data) do
                        remove_file_data(path)
                    end
                end
                return nil
            end

            -- Find files to remove from cache (deselected)
            for path, _ in pairs(current_state.file_data) do
                if not new_selection[path] then
                    -- File was deselected, remove from cache
                    remove_file_data(path)
                end
            end

            -- Find files to add (newly selected)
            local added_files = {}
            for path, _ in pairs(new_selection) do
                if not current_state.file_data[path] then
                    -- File not in cache, need to calculate
                    table.insert(added_files, path)
                end
            end

            -- Trigger calculation for new files
            for _, path in ipairs(added_files) do
                ya.emit("plugin", { st._id, ya.quote(path, true) })
            end

            -- Calculate totals from cached data
            local total_size = 0
            local total_count = 0
            local has_directory = false
            for _, data in pairs(current_state.file_data) do
                total_size = total_size + data.size
                total_count = total_count + data.count
                if data.is_dir then
                    has_directory = true
                end
            end

            -- Display current totals
            if total_size > 0 then
                local size_str = ya.readable_size(total_size)
                -- Show count only if at least one directory is selected
                if has_directory then
                    local text = string.format(" %d files, %s ", total_count, size_str)
                    table.insert(result, { text, "blue" })
                else
                    -- Only files selected, show just size
                    local text = string.format(" %s ", size_str)
                    table.insert(result, { text, "blue" })
                end
            end

            return result
        end
    end
end

-- Calculate size and count of a single file/directory
local function entry(st, job)
    local file_path = job.args[1]

    -- Calculate size using du
    local size_output = Command("du"):arg("-sb"):arg(file_path):output()

    if not size_output or not size_output.status.success then
        return
    end

    local size_str = size_output.stdout:match("^(%d+)")
    if not size_str then
        return
    end

    local size = tonumber(size_str)

    -- Calculate file count and determine if directory
    local count = 1  -- Default for regular files
    local is_dir = false

    -- Check if it's a directory
    local stat_output = Command("stat"):arg("-c"):arg("%F"):arg(file_path):output()
    if stat_output and stat_output.status.success then
        local file_type = stat_output.stdout:match("^%s*(.-)%s*$")
        if file_type == "directory" then
            is_dir = true
            -- Use find to count files recursively
            local count_output = Command("sh")
                :arg("-c")
                :arg(string.format("find %s -type f | wc -l", ya.quote(file_path, true)))
                :output()

            if count_output and count_output.status.success then
                count = tonumber(count_output.stdout:match("%d+")) or 0
            end
        end
    end

    -- Add to cache
    add_file_data(file_path, size, count, is_dir)
end

return { setup = setup, entry = entry }
