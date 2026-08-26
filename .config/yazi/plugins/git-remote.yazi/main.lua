--- @since 26.8.15

-- git.yazi plus upstream awareness.
--
-- Local status behaves exactly as git.yazi does: one pathspec-scoped
-- `git status` per fetch batch, recomputed on every directory load (~2ms).
--
-- Upstream is split across two clocks, which is the whole point of this plugin:
--
--   * `git fetch` is network-bound (~800ms/repo) and runs EXACTLY ONCE per
--     repo per session. A repo is claimed before the fetch is attempted, so a
--     failed fetch is never retried either.
--   * `git diff HEAD...@{upstream}` is local (~2ms) and runs every batch, so
--     pulling clears the update markers immediately even though the refs are
--     never fetched again.
--
-- Three dots, not two: `HEAD...@{upstream}` is what upstream gained since the
-- merge base, so your own unpushed commits are not reported as incoming.

local WINDOWS = ya.target_family() == "windows"

-- Severity order; a directory shows the worst status beneath it (see `bubble_up`).
-- Upstream states sit above every local one, so an incoming change wins.
---@enum CODES
local CODES = {
	unknown = 100, -- status cannot/not yet determined
	excluded = 99, -- ignored directory
	updated_local = 9, -- upstream has changes AND there are local changes
	updated = 8, -- upstream has changes
	ignored = 7,
	untracked = 6,
	unstaged = 5,
	staged = 4,
	added = 3,
	deleted = 2,
	conflict = 1, -- unmerged; this is git.yazi's `updated`, renamed
	clean = 0,
}

local PATTERNS = {
	{ "!$", CODES.ignored },
	{ "?$", CODES.untracked },
	{ ".[MT]", CODES.unstaged },
	{ "[MT] ", CODES.staged },
	{ "[AC]", CODES.added },
	{ "D", CODES.deleted },
	{ "U", CODES.conflict },
	{ "[AD][AD]", CODES.conflict },
}

local function theme()
	local t = th.git_remote or {}
	return {
		[CODES.unknown] = t.unknown or ui.Style(),
		[CODES.updated_local] = t.updated_local or ui.Style():fg("magenta"),
		[CODES.updated] = t.updated or ui.Style():fg("cyan"),
		[CODES.ignored] = t.ignored or ui.Style():fg("darkgray"),
		[CODES.untracked] = t.untracked or ui.Style():fg("magenta"),
		[CODES.unstaged] = t.unstaged or ui.Style():fg("yellow"),
		[CODES.staged] = t.staged or ui.Style():fg("green"),
		[CODES.added] = t.added or ui.Style():fg("green"),
		[CODES.deleted] = t.deleted or ui.Style():fg("red"),
		[CODES.conflict] = t.conflict or ui.Style():fg("red"),
		[CODES.clean] = t.clean or ui.Style():fg("green"),
	}, {
		-- Plain ASCII/BMP: these must render without a Nerd Font.
		[CODES.unknown] = t.unknown_sign or "",
		[CODES.updated_local] = t.updated_local_sign or "⇅",
		[CODES.updated] = t.updated_sign or "↓",
		[CODES.ignored] = t.ignored_sign or "I",
		[CODES.untracked] = t.untracked_sign or "?",
		[CODES.unstaged] = t.unstaged_sign or "M",
		[CODES.staged] = t.staged_sign or "M",
		[CODES.added] = t.added_sign or "A",
		[CODES.deleted] = t.deleted_sign or "D",
		[CODES.conflict] = t.conflict_sign or "!",
		-- Marks anything under git with nothing to report: a tracked file with
		-- no changes, and a repo folder that is clean and up to date.
		[CODES.clean] = t.clean_sign or "•",
	}
end

---@param url Url
---@return boolean
local function is_worktree(url)
	local file, head = io.open(tostring(url)), nil
	if file then
		head = file:read(8)
		file:close()
	end
	return head == "gitdir: "
end

---@param url Url
---@return boolean
local function is_root(url)
	local git = url:join(".git")
	local cha = fs.cha(git)
	return cha ~= nil and (cha.is_dir or is_worktree(git))
end

---@param cwd Url
---@return string?
local function root(cwd)
	repeat
		if is_root(cwd) then
			return tostring(cwd)
		end
		cwd = cwd.parent
	until not cwd
end

---@param line string
---@return CODES?, string?
local function match(line)
	local signs = line:sub(1, 2)
	for _, p in ipairs(PATTERNS) do
		local path, pattern, code = nil, p[1], p[2]
		if signs:find(pattern) then
			path = line:sub(4, 4) == '"' and line:sub(5, -2) or line:sub(4)
			path = WINDOWS and path:gsub("/", "\\") or path
		end
		if not path then
		elseif path:find("[/\\]$") then
			-- Mark the ignored directory as `excluded` for `propagate_down`
			return code == CODES.ignored and CODES.excluded or code, path:sub(1, -2)
		else
			return code, path
		end
	end
end

---@type UnstableFetcher
local function retry(job)
	return ya.co(function()
		for _, file in ipairs(job.files) do
			coroutine.yield(file, { retry = true })
		end
	end)
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

---@param excluded string[]
---@param cwd Url
---@param repo Url
---@return Changes
local function propagate_down(excluded, cwd, repo)
	local new, rel = {}, cwd:strip_prefix(repo)
	for _, path in ipairs(excluded) do
		if rel:starts_with(path) then
			new[tostring(cwd)] = CODES.excluded
		elseif cwd == repo:join(path).parent then
			new[path] = CODES.ignored
		end
	end
	return new
end

---@param cwd string
---@param repo string
---@param changed Changes
local add = ya.sync(function(st, cwd, repo, changed)
	st.dirs[cwd] = repo
	st.repos[repo] = st.repos[repo] or {}
	for path, code in pairs(changed) do
		if code == CODES.clean then
			st.repos[repo][path] = nil
		elseif code == CODES.excluded then
			st.dirs[path] = CODES.excluded
		else
			st.repos[repo][path] = code
		end
	end
	ui.render()
end)

---@param cwd string
local remove = ya.sync(function(st, cwd)
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

---@param summaries table<string, CODES>
local add_summaries = ya.sync(function(st, summaries)
	for path, code in pairs(summaries) do
		st.summary[path] = code
	end
	ui.render()
end)

-- Claims repos for their one and only network fetch. Claiming happens before
-- the fetch is attempted, so a repo whose fetch fails is never retried.
---@param repos string[]
---@return string[] todo
local claim = ya.sync(function(st, repos)
	local todo = {}
	for _, repo in ipairs(repos) do
		if not st.fetched[repo] then
			st.fetched[repo] = true
			todo[#todo + 1] = repo
		end
	end
	return todo
end)

-- Spawns every fetch first, then waits: the processes overlap, so wall time is
-- the slowest single fetch rather than the sum. Nothing here may block forever,
-- hence the prompt-disabling env and git's own transfer timeouts.
---@param repos string[]
local function fetch_remotes(repos)
	local children = {}
	for _, repo in ipairs(repos) do
		local child = Command("git")
			:cwd(repo)
			:arg({
				"-c", "credential.helper=",
				"-c", "http.lowSpeedLimit=1000",
				"-c", "http.lowSpeedTime=10",
				"--no-optional-locks", "fetch", "--quiet",
			})
			:env("GIT_TERMINAL_PROMPT", "0")
			:env("GIT_SSH_COMMAND", "ssh -o BatchMode=yes -o ConnectTimeout=5")
			:stdout(Command.NULL)
			:stderr(Command.NULL)
			:spawn()
		if child then
			children[#children + 1] = child
		end
	end
	for _, child in ipairs(children) do
		child:wait()
	end
end

-- Paths that upstream changed since the merge base. Local and cheap; the refs
-- it reads against are whatever the one-time fetch left behind.
---@param cwd string
---@param paths string[]
---@return table<string, boolean>
local function incoming(cwd, paths)
	local output = Command("git")
		:cwd(cwd)
		:arg({
			"--no-optional-locks", "-c", "core.quotePath=",
			"diff", "--name-only", "-z", "--no-renames", "HEAD...@{upstream}", "--",
		})
		:arg(paths)
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:output()

	local set = {}
	if output and output.status.success then
		for path in output.stdout:gmatch("[^\0]+") do
			set[WINDOWS and path:gsub("/", "\\") or path] = true
		end
	end
	return set
end

-- Whole-repo verdict for a repo shown as a directory entry from outside it.
---@param repo string
---@return CODES
local function summarize(repo)
	local worst = CODES.clean
	local status = Command("git")
		:cwd(repo)
		:arg({ "--no-optional-locks", "-c", "core.quotePath=", "status", "--porcelain", "-unormal", "--no-renames" })
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:output()
	if status then
		for line in status.stdout:gmatch("[^\r\n]+") do
			local code = match(line)
			if code and code ~= CODES.excluded and code > worst then
				worst = code
			end
		end
	end

	local behind = 0
	local counts = Command("git")
		:cwd(repo)
		:arg({ "--no-optional-locks", "rev-list", "--count", "--left-right", "HEAD...@{upstream}" })
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:output()
	if counts and counts.status.success then
		behind = tonumber(counts.stdout:match("%d+%s+(%d+)")) or 0
	end

	if behind > 0 then
		return worst > CODES.clean and CODES.updated_local or CODES.updated
	end
	-- Clean and up to date falls through to `clean`, which is marked rather
	-- than blank, so every repo stays visible as a repo.
	return worst
end

---@param st State
---@param opts Options
local function setup(st, opts)
	st.dirs = {}
	st.repos = {}
	st.summary = {} -- repo root -> whole-repo verdict, for entries seen from outside
	st.fetched = {} -- repo root -> true once its one network fetch was attempted

	opts = opts or {}
	opts.order = opts.order or 1500

	local styles, signs = theme()
	ps.sub("theme", function() styles, signs = theme() end)

	Linemode:children_add(function(self)
		if not self._file.in_current then
			return ""
		end

		local url = self._file.url
		local str = tostring(url)
		local code = CODES.unknown

		local summary = st.summary[str]
		if summary then
			-- A repo seen from outside: its own verdict beats the outer repo's
			-- opinion of the directory.
			code = summary
		else
			local repo = st.dirs[tostring(url.base or url.parent)]
			if repo then
				code = repo == CODES.excluded and CODES.ignored
					or st.repos[repo][str:sub(#repo + 2)]
					or CODES.clean
			end
		end

		-- A blank still occupies the slot: this plugin owns one fixed-width
		-- column, so nothing to report must not let another column slide into
		-- its place.
		local sign = signs[code]
		if sign == "" then
			sign = " "
		end

		if self._file.is_hovered then
			return ui.Line { " ", sign }
		else
			return ui.Line { " ", ui.Span(sign):style(styles[code]) }
		end
	end, opts.order)
end

---@type UnstableFetcher
local function fetch(_, job)
	local cwd = job.files[1].url.base or job.files[1].url.parent
	local repo = root(cwd)

	-- Directory entries that are themselves repo roots.
	local roots = {}
	for _, file in ipairs(job.files) do
		if file.cha.is_dir and is_root(file.url) then
			roots[#roots + 1] = tostring(file.url)
		end
	end

	if not repo and #roots == 0 then
		remove(tostring(cwd))
		return require("noop"):fetch(job)
	end

	local paths = {}
	for _, file in ipairs(job.files) do
		paths[#paths + 1] = tostring(file.url)
	end

	-- Everything below runs once before the network fetch, so local status
	-- paints immediately, and again afterwards once the refs have moved.
	local function refresh()
		if repo then
			-- stylua: ignore
			local output, err = Command("git")
				:cwd(tostring(cwd))
				:arg({ "--no-optional-locks", "-c", "core.quotePath=", "status", "--porcelain", "-unormal", "--no-renames", "--ignored=matching" })
				:arg(paths)
				:output()
			if not output then
				ya.err("Cannot spawn `git` command, error: " .. tostring(err))
				return false
			end

			local changed, excluded = {}, {}
			for line in output.stdout:gmatch("[^\r\n]+") do
				local code, path = match(line)
				if code == CODES.excluded then
					excluded[#excluded + 1] = path
				elseif code then
					changed[path] = code
				end
			end

			-- Upstream wins, and remembers whether anything local was there too.
			for path in pairs(incoming(tostring(cwd), paths)) do
				changed[path] = changed[path] and CODES.updated_local or CODES.updated
			end

			if job.files[1].cha.is_dir then
				ya.dict_merge(changed, bubble_up(changed))
			end
			ya.dict_merge(changed, propagate_down(excluded, cwd, Url(repo)))

			for _, path in ipairs(paths) do
				local s = path:sub(#repo + 2)
				changed[s] = changed[s] or CODES.clean
			end

			add(tostring(cwd), repo, changed)
		end

		if #roots > 0 then
			local summaries = {}
			for _, r in ipairs(roots) do
				summaries[r] = summarize(r)
			end
			add_summaries(summaries)
		end
		return true
	end

	refresh()

	-- One fetch per repo, ever. `claim` marks them before we try, so a repo
	-- that fails to fetch is not retried either.
	local todo = claim(repo and { repo, table.unpack(roots) } or roots)
	if #todo > 0 then
		fetch_remotes(todo)
		refresh()
	end

	return retry(job)
end

return { setup = setup, fetch = fetch }
