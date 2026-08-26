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

local function shell_quote(s) return "'" .. s:gsub("'", [['\'']]) .. "'" end

-- Which of `file` / `dir` you invoked decides what gets made; nothing is
-- inferred from the name itself.
---@param name string filter text
---@param is_dir boolean
local function create(name, is_dir)
	name = name:gsub("/+$", "")
	if name == "" then
		return
	end

	local quoted = shell_quote(name)
	local cmd
	if is_dir then
		cmd = "mkdir -p -- " .. quoted
	else
		-- `a/b/c` needs its parent to exist before touch can create it, and
		-- mkdir -p on the parent is a no-op for a bare name.
		cmd = "mkdir -p -- \"$(dirname -- " .. quoted .. ")\" && touch -a " .. quoted
	end
	ya.emit("shell", { cmd, block = true, confirm = false })

	write_state("")
	ya.emit("escape", { filter = true })
	ya.emit("reveal", { name })
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
		
	elseif action == "file" then
		local current = read_state()
		if current == "" then
			ya.emit("open", { interactive = true })
		else
			create(current, false)
		end

	elseif action == "dir" then
		local current = read_state()
		if current == "" then
			-- Nothing typed, so `/` keeps its old meaning instead of creating an
			-- unnamed directory.
			ya.emit("plugin", { "paste-navigate" })
		else
			create(current, true)
		end


	elseif action == "clear" then
		write_state("")
		ya.emit("escape", { filter = true })
	end
end

return { setup = setup, entry = entry }