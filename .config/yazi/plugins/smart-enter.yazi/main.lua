--- @sync entry

local function entry(self)
	local h = cx.active.current.hovered

	if not h then
		return
	end

	-- If hovering over a directory, always enter it (even if files are selected)
	if h.cha.is_dir then
		ya.emit("enter", { hovered = true })
		return
	end

	-- Check if there are any selected files and if hovered file is one of them
	local selected_count = 0
	local hovered_is_selected = false

	for _, url in pairs(cx.active.selected) do
		selected_count = selected_count + 1
		if tostring(h.url) == tostring(url) then
			hovered_is_selected = true
		end
	end

	-- If hovering over a selected file and there are selected files, open all selected
	if selected_count > 0 and hovered_is_selected then
		-- Open all selected files with their default openers
		ya.emit("open", {})
	else
		-- Otherwise, open only the hovered file
		ya.emit("open", { hovered = true })
	end
end

return { entry = entry }
