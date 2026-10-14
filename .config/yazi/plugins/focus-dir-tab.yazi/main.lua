local find_tab = ya.sync(function(_, dir)
    for i, tab in ipairs(cx.tabs) do
        if tostring(tab.current.cwd) == dir then
            return i - 1
        end
    end
    return -1
end)

return {
    entry = function(_, job)
        local dir = tostring(job.args[1] or "")
        local idx = find_tab(dir)
        if idx >= 0 then
            ya.emit("tab_switch", { idx })
        else
            ya.emit("tab_create", { dir })
        end
        if job.args[2] then
            ya.emit("reveal", { tostring(job.args[2]) })
        end
    end,
}
