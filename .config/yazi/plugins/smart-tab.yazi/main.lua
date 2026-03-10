--- @sync entry

local function entry(self)
    local tabs = cx.tabs

    -- Check if we're on the last tab
    if tabs.idx >= #tabs then
        -- Create new tab after current
        ya.emit("tab_create", { current = true })
    else
        -- Switch to next tab (relative +1)
        ya.emit("tab_switch", { 1, relative = true })
    end
end

return { entry = entry }
