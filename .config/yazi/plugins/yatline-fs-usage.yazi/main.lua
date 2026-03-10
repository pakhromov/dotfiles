-- Yatline wrapper for fs-usage plugin
-- Stores disk usage state that can be accessed by yatline component

local state = ya.sync(function(st)
    return st
end)

local set_state = ya.sync(function(st, cwd, source, usage, text_left, text_right)
    st.cwd = cwd
    st.source = source
    st.usage = usage
    st.text_left = text_left
    st.text_right = text_right
    ui.render()
end)

local function setup(st)

    -- Subscribe to events to update disk usage
    local get_cwd = ya.sync(function()
        return tostring(cx.active.current.cwd)
    end)

    local function callback()
        local cwd = get_cwd()
        ya.emit("plugin", { st._id, ya.quote(cwd, true) })
    end

    ps.sub("cd", callback)
    ps.sub("tab", callback)
    ps.sub("delete", callback)
    ps.sub("trash", callback)
    ps.sub("move", callback)
    ps.sub("@yank", callback)


    -- Register yatline component
    if Yatline ~= nil then
        Yatline.coloreds.get["fs-usage"] = function()
            local result = {}
            local current_cwd = tostring(cx.active.current.cwd)
            local current_state = state()

            -- If cached cwd doesn't match current cwd, trigger update
            if current_state.cwd ~= current_cwd then
                ya.emit("plugin", { st._id, ya.quote(current_cwd, true) })
            end

            if not current_state.usage then
                return result
            end

            local usage_num = current_state.usage
            local source = current_state.source or ""
            -- Strip /dev/ prefix if present
            source = source:gsub("^/dev/", "")
            local text = string.format("󰋊 %s %s%% ", source, usage_num)

            -- Color based on usage
            local color
            if usage_num > 85 then
                color = "red"
            elseif usage_num >= 65 then
                color = "yellow"
            else
                color = "green"
            end

            table.insert(result, { text, color })
            return result
        end
    end
end

-- Called from ya.emit in the callback
local function entry(st, job)
    local cwd = job.args[1]

    -- Use timeout to prevent hanging on disconnected sshfs mounts (1 second timeout)
    local output = Command("timeout"):arg("1"):arg("df"):arg("--output=source,pcent"):arg(cwd):output()

    if not output or not output.status.success then
        set_state(cwd, "", nil, "", "")
        return
    end

    local source, usage = output.stdout:match(".*%s(%S+)%s+(%d+)%%")
    usage = tonumber(usage)

    if source == st.source and usage == st.usage and cwd == st.cwd then
        return
    end

    set_state(cwd, source, usage, "", "")
end

return { setup = setup, entry = entry }
