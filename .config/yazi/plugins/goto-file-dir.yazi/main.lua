--- Go to file's directory plugin - step 2: access hovered

local get_hovered_url = ya.sync(function()
	if cx and cx.active and cx.active.current and cx.active.current.hovered then
		return tostring(cx.active.current.hovered.url)
	end
	return nil
end)

local function entry()
	local hovered_url = get_hovered_url()

	if not hovered_url then
		return
	end

	-- Exit search mode first
	ya.emit("escape", {})

	-- Extract actual path from search URL if needed
	-- Search URL format: search://<query>:<line>:<col>//<actual_path>
	local actual_path = hovered_url
	if hovered_url:match("^search://") then
		local path_part = hovered_url:match("^search://[^/]+//(.+)$")
		if not path_part then
			ya.err("Failed to parse search URL: " .. hovered_url)
			return
		end
		-- Add leading slash if missing
		if not path_part:match("^/") then
			actual_path = "/" .. path_part
		else
			actual_path = path_part
		end
		ya.err("DEBUG: Extracted path: " .. actual_path)
	end

	-- Extract parent directory from the file path
	local parent_dir = actual_path:match("^(.+)/[^/]+$")

	if not parent_dir then
		return
	end

	-- Navigate to parent directory
	ya.emit("cd", { Url(parent_dir) })

	-- Reveal the file in its directory
	ya.emit("reveal", { actual_path })
end

return { entry = entry }
