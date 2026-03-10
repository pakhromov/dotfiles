--- @sync entry

return {
	entry = function()
		local selected_count = 0
		local status, err = pcall(function()
			for _ in pairs(cx.active.selected) do
				selected_count = selected_count + 1
			end
		end)

		if not status then
			ya.notify({
				title = "Error",
				content = "Failed to count: " .. tostring(err),
				timeout = 5,
				level = "error"
			})
			return
		end

		-- Single file or no selection: use normal rename
		if selected_count <= 1 then
			ya.emit("rename", { cursor = "before_ext" })
			return
		end

		-- Multiple files: use custom batch rename with subl -w
		ya.emit("shell", {
			os.getenv("HOME") .. "/.config/yazi/scripts/batch-rename-subl.sh %s",
			block = true,
			confirm = false,
		})
	end,
}
