--- @sync

local state_file = "/tmp/yazi_filter_state"

local function read_state()
	local file = io.open(state_file, "r")
	if file then
		local content = file:read("*all")
		file:close()
		return content or ""
	end
	return ""
end

local function write_state(text)
	local file = io.open(state_file, "w")
	if file then
		file:write(text)
		file:close()
	end
end

local function is_file(name)
	-- If starts with . but has another . after it, it's a file (.config.bak)
	if name:match("^%..*%.") then
		return true
	end
	-- If starts with . and no other ., it's a directory (.config, .local)
	if name:match("^%.[^%.]*$") then
		return false
	end
	-- If contains . anywhere else, it's a file (script.sh, image.png)
	if name:match("%.") then
		return true
	end
	-- No . at all, it's a directory
	return false
end

local function setup(state, opts)
	-- Clear state file on startup
	write_state("")
end

local function entry(state, job)
	local action = job.args[1] or ""
	local char = job.args[2] or ""
	
	if action == "add" then
		local current = read_state()
		local new_text = current .. char
		write_state(new_text)
		ya.emit("filter_do", { new_text, smart = true })
		
	elseif action == "backspace" then
		local current = read_state()
		if #current > 0 then
			local new_text = string.sub(current, 1, -2)
			write_state(new_text)
			
			if new_text ~= "" then
				ya.emit("filter_do", { new_text, smart = true })
			else
				ya.emit("escape", { filter = true })
			end
		end
		
	elseif action == "enter" then
		local current = read_state()
		if current ~= "" then
			-- Create file or directory based on the name
			if is_file(current) then
				-- Create file using shell command (touch doesn't error if file exists)
				ya.emit("shell", {
					"touch \"" .. current .. "\"",
					block = true,
					confirm = false,
				})
			else
				-- Create directory using shell command with -p flag (no error if exists)
				ya.emit("shell", {
					"mkdir -p \"" .. current .. "\"",
					block = true,
					confirm = false,
				})
			end
			-- Clear filter and reveal the created file
			write_state("")
			ya.emit("escape", { filter = true })
			ya.emit("reveal", { current })
		else
			-- No filter text: run open --interactive
			ya.emit("open", { interactive = true })
		end
		
	elseif action == "clear" then
		write_state("")
		ya.emit("escape", { filter = true })
	end
end

return { setup = setup, entry = entry }