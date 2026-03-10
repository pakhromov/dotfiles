local write = ya.sync(function()
    ya.emit("shell", { 'echo -n "$YAZI_ID" > /tmp/yazi_instance_id', block = true })
end)

local find_tab = ya.sync(function(_, dir)
    for i, tab in ipairs(cx.tabs) do
        if tostring(tab.current.cwd) == dir then
            return i - 1  -- 0-based index for tab_switch
        end
    end
    return -1
end)

return {
    setup = function() write() end,

    entry = function(_, job)
        local dir = tostring(job.args[1] or "")
        local idx = find_tab(dir)
        if idx >= 0 then
            ya.emit("tab_switch", { idx })
        else
            ya.emit("tab_create", { dir })
        end
    end,
}
