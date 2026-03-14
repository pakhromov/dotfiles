--- @since 25.12.29

local WINDOWS = ya.target_family() == "windows"

-- The code of supported git status,
-- also used to determine which status to show for directories when they contain different statuses
-- see `bubble_up`
---@enum CODES
local CODES = {
	unknown = 100, -- status cannot/not yet determined
	excluded = 99, -- ignored directory
	ignored = 6, -- ignored file
	untracked = 5,
	modified = 4,
	added = 3,
	deleted = 2,
	updated = 1,
	clean = 0,
}

---@param cwd Url
---@return string?
local function root(cwd)
	local is_worktree = function(url)
		local file, head = io.open(tostring(url)), nil
		if file then
			head = file:read(8)
			file:close()
		end
		return head == "gitdir: "
	end

	repeat
		local next = cwd:join(".git")
		local cha = fs.cha(next)
		if cha and (cha.is_dir or is_worktree(next)) then
			return tostring(cwd)
		end
		cwd = cwd.parent
	until not cwd
end

---@param changed Changes
---@return Changes
local function bubble_up(changed)
	local new, empty = {}, Url("")
	for path, code in pairs(changed) do
		if code ~= CODES.ignored then
			local url = Url(path).parent
			while url and url ~= empty do
				local s = tostring(url)
				new[s] = (new[s] or CODES.clean) > code and new[s] or code
				url = url.parent
			end
		end
	end
	return new
end

---@param cwd string
---@param repo string
---@param changed Changes
local add = ya.sync(function(st, cwd, repo, changed)
	---@cast st State

	st.dirs[cwd] = repo
	st.repos[repo] = st.repos[repo] or {}
	for path, code in pairs(changed) do
		if code == CODES.clean then
			st.repos[repo][path] = nil
		elseif code == CODES.excluded then
			-- Mark the directory with a special value `excluded` so that it can be distinguished during UI rendering
			st.dirs[path] = CODES.excluded
		else
			st.repos[repo][path] = code
		end
	end
	ui.render()
end)

---@param cwd string
local remove = ya.sync(function(st, cwd)
	---@cast st State

	local repo = st.dirs[cwd]
	if not repo then
		return
	end

	ui.render()
	st.dirs[cwd] = nil
	if not st.repos[repo] then
		return
	end

	for _, r in pairs(st.dirs) do
		if r == repo then
			return
		end
	end
	st.repos[repo] = nil
end)

---@param repo string
---@param code CODES
local add_standalone = ya.sync(function(st, repo, code)
	st.standalone[repo] = code
	ui.render()
end)

-- Separate state for dotfiles bare repo — never touched by remove()
---@param cwd string
---@param home string
---@param changed Changes
local add_dotfiles = ya.sync(function(st, cwd, home, changed)
	st.dotfiles_dirs[cwd] = home
	st.dotfiles_repos[home] = st.dotfiles_repos[home] or {}
	for path, code in pairs(changed) do
		if code == CODES.unknown then
			-- untracked by dotfiles: nil means "not tracked" in dotfiles_repos
			st.dotfiles_repos[home][path] = nil
		else
			st.dotfiles_repos[home][path] = code
		end
	end
	ui.render()
end)

---@param st State
---@param opts Options
local function setup(st, opts)
	st.dirs = {}
	st.repos = {}
	st.standalone = {} -- repos that are themselves directory entries (viewed from outside)
	st.dotfiles_dirs = {} -- separate state for dotfiles bare repo, never cleared by remove()
	st.dotfiles_repos = {}

	opts = opts or {}
	opts.order = opts.order or 1500

	local t = th.git or {}
	local styles = {
		[CODES.unknown] = t.unknown or ui.Style(),
		[CODES.ignored] = t.ignored or ui.Style():fg("darkgray"),
		[CODES.untracked] = t.untracked or ui.Style():fg("magenta"),
		[CODES.modified] = t.modified or ui.Style():fg("yellow"),
		[CODES.added] = t.added or ui.Style():fg("green"),
		[CODES.deleted] = t.deleted or ui.Style():fg("red"),
		[CODES.updated] = t.updated or ui.Style():fg("yellow"),
		[CODES.clean] = t.clean or ui.Style(),
	}
	local signs = {
		[CODES.unknown] = t.unknown_sign or "",
		[CODES.ignored] = t.ignored_sign or " ",
		[CODES.untracked] = t.untracked_sign or "? ",
		[CODES.modified] = t.modified_sign or " ",
		[CODES.added] = t.added_sign or " ",
		[CODES.deleted] = t.deleted_sign or " ",
		[CODES.updated] = t.updated_sign or " ",
		[CODES.clean] = t.clean_sign or "",
	}

	Linemode:children_add(function(self)
		if not self._file.in_current then
			return ""
		end

		local url = self._file.url
		local url_str = tostring(url)
		local parent_str = tostring(url.base or url.parent)
		local repo = st.dirs[parent_str]
		local code = CODES.unknown
		if repo then
			code = repo == CODES.excluded and CODES.ignored or st.repos[repo][url_str:sub(#repo + 2)] or CODES.clean
		elseif st.standalone[url_str] then
			-- This directory is a standalone git repo (viewed from outside)
			code = st.standalone[url_str]
		else
			-- Check dotfiles bare repo state (separate from regular git state)
			local dotfiles_repo = st.dotfiles_dirs[parent_str]
			if dotfiles_repo and st.dotfiles_repos[dotfiles_repo] then
				local dot_code = st.dotfiles_repos[dotfiles_repo][url_str:sub(#dotfiles_repo + 2)]
				-- nil = not tracked by dotfiles = show nothing; otherwise use stored code
				code = dot_code or CODES.unknown
			end
		end

		if signs[code] == "" then
			return ""
		elseif self._file.is_hovered then
			return ui.Line { " ", signs[code] }
		else
			return ui.Line { " ", ui.Span(signs[code]):style(styles[code]) }
		end
	end, opts.order)
end

---@param dir_url Url
---@return CODES?
local function fetch_standalone_status(dir_url)
	local dir_str = tostring(dir_url)
	local dir_repo = root(dir_url)
	if dir_repo ~= dir_str then
		return nil -- Not a repo root
	end

	-- Fetch from remote to get up-to-date upstream info
	Command("git"):cwd(dir_str):arg({ "fetch", "--quiet" }):stderr(Command.PIPED):status()

	-- Check for local uncommitted changes
	local status_out = Command("git")
		:cwd(dir_str)
		:arg({ "--no-optional-locks", "-c", "core.quotePath=", "status", "--porcelain", "-unormal", "--no-renames" })
		:stdout(Command.PIPED)
		:output()
	if status_out and status_out.stdout ~= "" then
		return CODES.modified
	end

	-- Check if behind remote (unpulled commits)
	local behind = Command("git")
		:cwd(dir_str)
		:arg({ "--no-optional-locks", "rev-list", "--count", "HEAD..@{upstream}" })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	if behind and tonumber(behind.stdout:match("%d+") or "0") > 0 then
		return CODES.updated -- remote has changes not yet pulled
	end

	-- Check if ahead of remote (unpushed commits)
	local ahead = Command("git")
		:cwd(dir_str)
		:arg({ "--no-optional-locks", "rev-list", "--count", "@{upstream}..HEAD" })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	if ahead and tonumber(ahead.stdout:match("%d+") or "0") > 0 then
		return CODES.added
	end

	return CODES.clean
end

---@param job table
---@param cwd string
---@return boolean found_tracked_files
local function fetch_dotfiles(job, cwd)
	local home = os.getenv("HOME")
	if not home then return false end
	local git_dir = home .. "/.dotfiles-git"
	if not fs.cha(Url(git_dir)) then return false end

	-- Build both absolute paths (for ls-files) and relative paths (for diff/status)
	local abs_paths, rel_paths = {}, {}
	for _, file in ipairs(job.files) do
		local abs = tostring(file.url)
		abs_paths[#abs_paths + 1] = abs
		rel_paths[#rel_paths + 1] = abs:sub(#home + 2)
	end

	local base_args = { "--git-dir", git_dir, "--work-tree", home, "--no-optional-locks", "-c", "core.quotePath=" }

	-- Find which paths are tracked by the dotfiles repo.
	-- cwd=home ensures git outputs paths relative to the work-tree root, not yazi's cwd
	local ls_out = Command("git"):cwd(home):arg(base_args):arg({ "ls-files", "--" }):arg(abs_paths):stdout(Command.PIPED):output()
	if not ls_out or ls_out.stdout == "" then return true end -- repo exists but no tracked files in this batch

	local tracked = {}
	for line in ls_out.stdout:gmatch("[^\r\n]+") do
		tracked[line] = true
	end

	-- Fetch from remote
	Command("git"):cwd(home):arg({ "--git-dir", git_dir, "--work-tree", home, "fetch", "--quiet" }):stderr(Command.PIPED):status()

	-- Check upstream
	local has_upstream = Command("git"):cwd(home)
		:arg({ "--git-dir", git_dir, "--work-tree", home, "--no-optional-locks", "rev-parse", "--verify", "--quiet", "@{upstream}" })
		:stderr(Command.PIPED):status()

	local diff_out
	if has_upstream and has_upstream.success then
		-- Use relative paths and explicit HEAD..@{upstream} to correctly detect "behind remote" files
		diff_out = Command("git"):cwd(home):arg(base_args)
			:arg({ "diff", "--name-status", "--no-renames", "HEAD", "@{upstream}", "--" })
			:arg(rel_paths):stdout(Command.PIPED):output()
	end

	-- Use relative paths for status too (porcelain output is already relative to cwd=home)
	local status_out = Command("git"):cwd(home):arg(base_args)
		:arg({ "status", "--porcelain", "--untracked-files=no", "--no-renames", "--" })
		:arg(rel_paths):stdout(Command.PIPED):output()

	local status_codes = {
		["M"] = CODES.modified, ["T"] = CODES.modified,
		["A"] = CODES.added,    ["D"] = CODES.deleted, ["U"] = CODES.updated,
	}
	local raw_changed = {}

	for line in (diff_out and diff_out.stdout or ""):gmatch("[^\r\n]+") do
		local status, path = line:match("^(%a)%s+(.+)$")
		if status and path then
			raw_changed[WINDOWS and path:gsub("/", "\\") or path] = CODES.updated
		end
	end

	if status_out then
		for line in status_out.stdout:gmatch("[^\r\n]+") do
			local xy = line:sub(1, 2)
			local path = line:sub(4, 4) == '"' and line:sub(5, -2) or line:sub(4)
			path = (WINDOWS and path:gsub("/", "\\") or path):gsub("[/\\]$", "")
			local code = status_codes[xy:sub(1, 1)] or status_codes[xy:sub(2, 2)]
			if code then raw_changed[path] = code end
		end
	end

	-- Tracked files get their status (or clean); everything else gets unknown (shows nothing)
	local changed = {}
	for path in pairs(tracked) do
		changed[path] = raw_changed[path] or CODES.clean
	end

	-- Bubble up to parent directories
	ya.dict_merge(changed, bubble_up(changed))

	-- Mark untracked paths in current view as unknown so they show nothing
	for _, abs_path in ipairs(abs_paths) do
		local rel = abs_path:sub(#home + 2)
		if changed[rel] == nil then
			changed[rel] = CODES.unknown
		end
	end

	add_dotfiles(cwd, home, changed)
	return true
end

---@type UnstableFetcher
local function fetch(_, job)
	local cwd = job.files[1].url.base or job.files[1].url.parent
	local repo = root(cwd)
	if not repo then
		local dotfiles_handled = fetch_dotfiles(job, tostring(cwd))
		if not dotfiles_handled then
			remove(tostring(cwd))
		end
		-- Always check if any directories are standalone git repos,
		-- even if dotfiles handled the batch (e.g. mediainfo.yazi is a standalone repo)
		for _, file in ipairs(job.files) do
			if file.cha.is_dir then
				local code = fetch_standalone_status(file.url)
				if code then
					add_standalone(tostring(file.url), code)
				end
			end
		end
		return true
	end

	local paths = {}
	for _, file in ipairs(job.files) do
		paths[#paths + 1] = tostring(file.url)
	end

	-- Fetch from remote to get up-to-date upstream info
	Command("git"):cwd(repo):arg({ "fetch", "--quiet" }):stderr(Command.PIPED):status()

	-- Check if upstream tracking branch exists
	local has_upstream = Command("git")
		:cwd(tostring(cwd))
		:arg({ "--no-optional-locks", "rev-parse", "--verify", "--quiet", "@{upstream}" })
		:stderr(Command.PIPED)
		:status()

	-- Compare local files against remote upstream (only if upstream exists)
	local diff_out
	if has_upstream and has_upstream.success then
		local err
		diff_out, err = Command("git")
			:cwd(tostring(cwd))
			:arg({ "--no-optional-locks", "-c", "core.quotePath=", "diff", "--name-status", "--no-renames", "@{upstream}", "--" })
			:arg(paths)
			:stdout(Command.PIPED)
			:output()
		if not diff_out then
			return true, Err("Cannot spawn `git` command, error: %s", err)
		end
	end

	-- Also check local uncommitted changes (untracked, staged, modified)
	local status_out = Command("git")
		:cwd(tostring(cwd))
		:arg({ "--no-optional-locks", "-c", "core.quotePath=", "status", "--porcelain", "-unormal", "--no-renames" })
		:arg(paths)
		:stdout(Command.PIPED)
		:output()

	local status_codes = {
		["?"] = CODES.untracked, ["M"] = CODES.modified, ["T"] = CODES.modified,
		["A"] = CODES.added,     ["D"] = CODES.deleted,  ["U"] = CODES.updated,
	}
	local changed = {}

	-- Files differing from remote get CODES.updated (unpulled remote changes)
	for line in (diff_out and diff_out.stdout or ""):gmatch("[^\r\n]+") do
		local status, path = line:match("^(%a)%s+(.+)$")
		if status and path then
			path = WINDOWS and path:gsub("/", "\\") or path
			changed[path] = CODES.updated
		end
	end

	-- Local uncommitted changes override with their specific codes (higher priority)
	if status_out then
		for line in status_out.stdout:gmatch("[^\r\n]+") do
			local xy = line:sub(1, 2)
			local path = line:sub(4, 4) == '"' and line:sub(5, -2) or line:sub(4)
			path = WINDOWS and path:gsub("/", "\\") or path
			path = path:gsub("[/\\]$", "") -- strip trailing slash from untracked directories
			local code = status_codes[xy:sub(1,1)] or status_codes[xy:sub(2,2)]
			if code then
				changed[path] = code
			end
		end
	end

	if job.files[1].cha.is_dir then
		ya.dict_merge(changed, bubble_up(changed))
	end

	-- Reset files not in diff output to clean
	for _, path in ipairs(paths) do
		local s = path:sub(#repo + 2)
		changed[s] = changed[s] or CODES.clean
	end

	add(tostring(cwd), repo, changed)

	return false
end

return { setup = setup, fetch = fetch }
