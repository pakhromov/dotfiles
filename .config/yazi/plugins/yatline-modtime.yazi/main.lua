local function setup(_, options)
    options = options or {}

    if Yatline ~= nil then
        -- Combined dates component (creation and modification without separator)
        Yatline.coloreds.get["modtime"] = function()
            local result = {}
            local h = cx.active.current.hovered

            if h and h.cha then

                -- Modification date (mtime)
                if h.cha.mtime then
                    local text = os.date("  %d.%m.%y %H:%M ", h.cha.mtime // 1)
                    table.insert(result, { text, "blue" })
                end

            end

            return result
        end
    end
end

return { setup = setup }
