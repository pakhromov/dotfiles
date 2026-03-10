--- Quick navigation plugin
--- Paste a path to navigate/create files and directories

local function expand_path(path, cwd)
	-- Expand ~/ to home directory
	path = path:gsub("^~/", os.getenv("HOME") .. "/")

	-- Expand $HOME
	path = path:gsub("%$HOME", os.getenv("HOME"))

	-- Make relative paths absolute
	if not path:match("^/") then
		path = cwd .. "/" .. path
	end

	return path
end

local function is_file_path(path)
	-- Get the basename (last component)
	local basename = path:match("([^/]+)$") or path

	-- If basename contains a dot (but not just . or ..), it's likely a file
	if basename:match("^%.%.?$") then
		return false -- . or .. are directories
	end

	return basename:match("%.") ~= nil
end

local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local function entry()
	-- Get user input
	local value, event = ya.input({
		title = "Navigate to:",
		pos = { "top-center", w = 60 },
	})

	-- User cancelled
	if event ~= 1 or not value or value == "" then
		return
	end

	-- Get current working directory using sync
	local cwd = get_cwd()

	-- Expand path and strip trailing slashes
	local path = expand_path(value, cwd):gsub("/+$", "")

	-- Check filesystem first, fall back to heuristic for non-existent paths
	local cha = fs.cha(Url(path))
	local is_file = cha and not cha.is_dir or not cha and is_file_path(path)

	if is_file then
		-- Extract directory and filename
		local dir = path:match("^(.+)/[^/]+$")
		local filename = path:match("([^/]+)$")

		-- Create parent directories
		local child = Command("mkdir"):arg({ "-p", dir }):spawn()
		if child then
			child:wait()
		end

		-- Check if file exists
		local file_exists = fs.cha(Url(path))

		-- Create file if it doesn't exist
		if not file_exists then
			local child = Command("touch"):arg({ path }):spawn()
			if child then
				child:wait()
			end
		end

		-- Navigate to directory
		ya.emit("cd", { Url(dir) })

		-- Reveal the file
		ya.emit("reveal", { path })

	else
		-- It's a directory - same as before
		local dir_url = Url(path)
		local dir_exists = fs.cha(dir_url)

		if not dir_exists then
			local child = Command("mkdir"):arg({ "-p", path }):spawn()
			if child then
				child:wait()
			end
		end

		ya.emit("cd", { dir_url })
	end
end

return { entry = entry }
