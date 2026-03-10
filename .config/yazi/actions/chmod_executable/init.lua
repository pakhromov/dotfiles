local M = {}

function M:init(opts)
	-- Run chmod +x on all selected files
	local cmd = Command("chmod"):arg("+x")
	for _, file in ipairs(opts.selected) do
		cmd = cmd:arg(file)
	end

	cmd:output()
end

return M
