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
        local parts = {}
        local i = 1
        while job.args[i] ~= nil do
            parts[#parts + 1] = tostring(job.args[i])
            i = i + 1
        end
        local dir = table.concat(parts, " ")
        local idx = find_tab(dir)
        if idx >= 0 then
            ya.emit("tab_switch", { idx })
        else
            ya.emit("tab_create", { dir })
        end
    end,
}
