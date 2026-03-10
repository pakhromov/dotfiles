-- Creation and modification dates component for yatline

local function setup(_, options)
    options = options or {}

    if Yatline ~= nil then
        -- Combined dates component (creation and modification without separator)
        Yatline.coloreds.get["crtime"] = function()
            local result = {}
            local h = cx.active.current.hovered

            if h and h.cha then

                -- Creation date (btime)
                if h.cha.btime then
                    local text = os.date("  %d.%m.%y %H:%M ", h.cha.btime // 1)
                    table.insert(result, { text, "green" })
                end

            end

            return result
        end
    end
end

return { setup = setup }
