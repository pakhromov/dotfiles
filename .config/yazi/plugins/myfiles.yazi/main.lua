local HOME         = os.getenv("HOME") or ""
local REMOTE       = "gdrive:/linux_sync"
local TRACKED_FILE = HOME .. "/.local/share/myfiles/tracked"
local CACHE_TTL    = 30 -- seconds between rclone check calls

---@enum CODES
local CODES = {
	unknown      = 0, -- not tracked or not yet fetched
	identical    = 1, -- = same on both sides
	remote_only  = 2, -- > only on remote
	local_only   = 3, -- < only on local
	differs      = 4, -- * exists on both but content differs
	error_check  = 5, -- ! error reading file
}

local update = ya.sync(function(st, status, ts)
	st.status     = status
	st.last_check = ts
	ui.render()
end)

local get = ya.sync(function(st)
	return st.status, st.last_check
end)

-- Walk every tracked file's ancestors up to HOME and record the worst
-- status seen, so directories light up like git does.
local function bubble_up(file_status)
	local dir_status = {}
	for abs_path, code in pairs(file_status) do
		if code ~= CODES.unknown then
			local url = Url(abs_path).parent
			while url do
				local s = tostring(url)
				-- Stop once we've gone above HOME
				if #s < #HOME then break end
				local existing = dir_status[s] or CODES.unknown
				if code > existing then
					dir_status[s] = code
				end
				url = url.parent
			end
		end
	end
	return dir_status
end

local function setup(st, opts)
	st.status     = {}
	st.last_check = 0

	opts       = opts or {}
	opts.order = opts.order or 1600

	-- Single character signs — no trailing space, matches git plugin width
	local signs = {
		[CODES.unknown]     = "",
		[CODES.identical]   = "=",
		[CODES.local_only]  = "<",
		[CODES.remote_only] = ">",
		[CODES.differs]     = "*",
		[CODES.error_check] = "!",
	}
	local styles = {
		[CODES.unknown]     = ui.Style(),
		[CODES.identical]   = ui.Style():fg("green"),
		[CODES.local_only]  = ui.Style():fg("blue"),
		[CODES.remote_only] = ui.Style():fg("cyan"),
		[CODES.differs]     = ui.Style():fg("yellow"),
		[CODES.error_check] = ui.Style():fg("red"),
	}

	Linemode:children_add(function(self)
		if not self._file.in_current then
			return ""
		end
		local code = st.status[tostring(self._file.url)] or CODES.unknown
		local sign = signs[code]
		if sign == "" then
			return ""
		elseif self._file.is_hovered then
			return ui.Line { " ", sign }
		else
			return ui.Line { " ", ui.Span(sign):style(styles[code]) }
		end
	end, opts.order)
end

-- Returns path relative to HOME, or strips leading / if outside HOME
local function rel(abs_path)
	if abs_path:sub(1, #HOME + 1) == HOME .. "/" then
		return abs_path:sub(#HOME + 2)
	else
		return abs_path:sub(2)
	end
end

---@type UnstableFetcher
local function fetch(_, job)
	if HOME == "" then return true end

	-- Read tracked list
	local f = io.open(TRACKED_FILE, "r")
	if not f then return true end
	local tracked = {}
	for line in f:lines() do
		if line ~= "" then tracked[line] = true end
	end
	f:close()
	if not next(tracked) then return true end

	-- Only proceed if this batch contains a tracked file or a parent of one
	local relevant = false
	for _, file in ipairs(job.files) do
		local s = tostring(file.url)
		if tracked[s] then
			relevant = true
			break
		end
		-- Also relevant if any tracked file lives inside this directory
		for abs_path in pairs(tracked) do
			if abs_path:sub(1, #s + 1) == s .. "/" then
				relevant = true
				break
			end
		end
		if relevant then break end
	end
	if not relevant then return true end

	-- Respect cache TTL to avoid hammering the API
	local _, last_check = get()
	if os.time() - (last_check or 0) < CACHE_TTL then
		return true
	end

	-- Write relative paths to a temp file for --files-from
	local tmp = os.tmpname()
	local tf  = io.open(tmp, "w")
	if not tf then return true end
	local rel_to_abs = {}
	for abs_path in pairs(tracked) do
		local r = rel(abs_path)
		tf:write(r .. "\n")
		rel_to_abs[r] = abs_path
	end
	tf:close()

	-- rclone check HOME gdrive:/linux_sync --files-from <tmp> --combined -
	-- < = local only  > = remote only  = identical  * differs  ! error
	local out = Command("rclone")
		:arg({ "check", HOME, REMOTE, "--files-from", tmp, "--combined", "-" })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	os.remove(tmp)

	local file_status = {}
	if out then
		local map = {
			["="] = CODES.identical,
			["<"] = CODES.local_only,
			[">"] = CODES.remote_only,
			["*"] = CODES.differs,
			["!"] = CODES.error_check,
		}
		for line in out.stdout:gmatch("[^\r\n]+") do
			local sym, path = line:match("^(.) (.+)$")
			if sym and path then
				local abs = rel_to_abs[path]
				if abs then
					file_status[abs] = map[sym] or CODES.unknown
				end
			end
		end
	end

	-- Merge file statuses with bubbled-up directory statuses
	local new_status = bubble_up(file_status)
	for abs, code in pairs(file_status) do
		new_status[abs] = code
	end

	update(new_status, os.time())
	return true
end

return { setup = setup, fetch = fetch }
