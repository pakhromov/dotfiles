--- @since 26.8.15

-- Status of files tracked in a bare dotfiles repo whose work-tree is $HOME,
-- i.e. the `git --git-dir=~/.dotfiles-git --work-tree=$HOME` pattern.
--
-- Everything is derived from one whole-repo snapshot rather than per-directory
-- queries: `ls-files` gives the tracked set and `status -uno` gives the dirty
-- set, together ~8ms on a 3k-file repo. That is cheap enough to redo whenever
-- the view reloads, and it means a directory knows the worst status beneath it
-- without having to have been visited.
--
-- The remote is never consulted.

-- Ordered by severity: a directory shows the worst status found beneath it.
-- A conflict outranks everything, being the most urgent thing under a directory.
---@enum CODES
local CODES = {
	unknown = 100, -- not tracked by the dotfiles repo; renders nothing
	conflict = 6,
	unstaged = 5,
	staged = 4,
	added = 3,
	deleted = 2,
	clean = 0,
}

local HOME = os.getenv("HOME") or ""

---@param key string
local function pick(key)
	return (th.dotfiles or {})[key]
end

local function theme()
	return {
		[CODES.unknown] = pick("unknown") or ui.Style(),
		[CODES.conflict] = pick("conflict") or ui.Style():fg("red"),
		[CODES.deleted] = pick("deleted") or ui.Style():fg("red"),
		[CODES.unstaged] = pick("unstaged") or ui.Style():fg("yellow"),
		[CODES.staged] = pick("staged") or ui.Style():fg("green"),
		[CODES.added] = pick("added") or ui.Style():fg("green"),
		[CODES.clean] = pick("clean") or ui.Style():fg("darkgray"),
	}, {
		-- Plain ASCII/BMP on purpose: these must render without a Nerd Font.
		-- Staged and unstaged share "M" and are told apart by colour.
		[CODES.unknown] = pick("unknown_sign") or "",
		[CODES.conflict] = pick("conflict_sign") or "!",
		[CODES.deleted] = pick("deleted_sign") or "D",
		[CODES.unstaged] = pick("unstaged_sign") or "M",
		[CODES.staged] = pick("staged_sign") or "M",
		[CODES.added] = pick("added_sign") or "A",
		[CODES.clean] = pick("clean_sign") or "✔",
	}
end

-- The two porcelain columns are index status and work-tree status. The
-- work-tree wins where both are set, since that is the edit you just made.
---@param xy string
---@return CODES?
local function code_of(xy)
	local x, y = xy:sub(1, 1), xy:sub(2, 2)
	if x == "U" or y == "U" or (x == "A" and y == "A") or (x == "D" and y == "D") then
		return CODES.conflict
	elseif y == "M" or y == "T" then
		return CODES.unstaged
	elseif y == "D" then
		return CODES.deleted
	elseif x == "M" or x == "T" or x == "R" then
		return CODES.staged
	elseif x == "A" or x == "C" then
		return CODES.added
	elseif x == "D" then
		return CODES.deleted
	end
end

---@param git_dir string
---@return table? files, table? dirs, string? err
local function snapshot(git_dir)
	local base = { "--git-dir", git_dir, "--work-tree", HOME, "--no-optional-locks" }

	-- Every tracked path, straight off the index.
	local ls, err = Command("git")
		:cwd(HOME)
		:arg(base)
		:arg({ "ls-files", "-z" })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	if not ls then
		return nil, nil, "cannot spawn `git`: " .. tostring(err)
	elseif not ls.status.success then
		return nil, nil, "`git ls-files` failed: " .. ls.stderr
	end

	-- `-uno` is what keeps this fast: git stats the index instead of walking
	-- all of $HOME. It also suppresses the untracked noise we don't want.
	local so
	so, err = Command("git")
		:cwd(HOME)
		:arg(base)
		:arg({ "status", "--porcelain", "-z", "-uno", "--no-renames" })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	if not so then
		return nil, nil, "cannot spawn `git`: " .. tostring(err)
	elseif not so.status.success then
		return nil, nil, "`git status` failed: " .. so.stderr
	end

	-- `-z` means NUL-delimited and never quoted, so no unescaping to do.
	local files = {}
	for rel in ls.stdout:gmatch("[^\0]+") do
		files[rel] = CODES.clean
	end
	for rec in so.stdout:gmatch("[^\0]+") do
		local code, rel = code_of(rec:sub(1, 2)), rec:sub(4)
		if code and rel ~= "" then
			files[rel] = code
		end
	end

	-- Roll each status up through its ancestors. Stopping as soon as an
	-- ancestor already holds a worse code keeps this linear: whoever put that
	-- code there already carried it the rest of the way up.
	local dirs = {}
	for path, code in pairs(files) do
		local rel = path
		local slash = rel:find("/[^/]*$")
		while slash do
			local dir = rel:sub(1, slash - 1)
			if (dirs[dir] or -1) >= code then
				break
			end
			dirs[dir] = code
			rel, slash = dir, dir:find("/[^/]*$")
		end
	end

	return files, dirs
end

-- Claims the right to refresh. Returns nil when the plugin is inactive, and
-- `refresh = false` when a snapshot is already in flight or still fresh --
-- yazi splits a directory into several fetch batches, and without this each
-- one would spawn its own pair of git processes.
local claim = ya.sync(function(st)
	if not st.git_dir then
		return nil
	elseif st.busy or (not st.stale and st.at and ya.time() - st.at < st.ttl) then
		return { git_dir = st.git_dir, refresh = false }
	end
	st.busy, st.stale = true, false
	return { git_dir = st.git_dir, refresh = true }
end)

local commit = ya.sync(function(st, files, dirs)
	st.busy, st.at = false, ya.time()
	if files then
		st.files, st.dirs = files, dirs
		ui.render()
	end
end)

---@param st State
---@param opts Options
local function setup(st, opts)
	opts = opts or {}

	st.files, st.dirs = {}, {}
	st.at, st.busy, st.stale = nil, false, true
	st.ttl = (opts.ttl_ms or 250) / 1000

	local git_dir = opts.git_dir or (HOME .. "/.dotfiles-git")
	st.git_dir = HOME ~= "" and fs.cha(Url(git_dir)) and git_dir or nil
	if not st.git_dir then
		return -- No dotfiles repo here; stay completely out of the way.
	end

	local styles, signs = theme()
	ps.sub("theme", function() styles, signs = theme() end)

	-- There is no DDS event for a file's contents changing; that case is
	-- covered by yazi's own watcher reloading the directory, which re-runs the
	-- fetcher. These are the events that change paths out from under us.
	for _, kind in ipairs { "cd", "rename", "bulk", "move", "delete", "trash" } do
		ps.sub(kind, function() st.stale = true end)
	end

	Linemode:children_add(function(self)
		if not self._file.in_current then
			return ""
		end

		local url = tostring(self._file.url)
		local code = CODES.unknown
		if url:sub(1, #HOME + 1) == HOME .. "/" then
			local rel = url:sub(#HOME + 2)
			code = st.files[rel] or st.dirs[rel] or CODES.unknown
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
	end, opts.order or 1550)
end

---@param cwd Url
---@return boolean
local function nested_repo(cwd)
	local url = cwd
	while url and tostring(url) ~= HOME do
		if fs.cha(url:join(".git")) then
			return true
		end
		url = url.parent
	end
	return false
end

---@type UnstableFetcher
local function retry(job)
	return ya.co(function()
		for _, file in ipairs(job.files) do
			-- `retry` leaves the files fetchable, so a later reload re-runs us.
			-- Without it a status would be computed once and then frozen.
			coroutine.yield(file, { retry = true })
		end
	end)
end

---@type UnstableFetcher
local function fetch(_, job)
	local cwd = job.files[1].url.base or job.files[1].url.parent
	if not cwd then
		return require("noop"):fetch(job)
	end

	-- Outside $HOME there is nothing for this repo to say.
	local str = tostring(cwd)
	if str ~= HOME and str:sub(1, #HOME + 1) ~= HOME .. "/" then
		return require("noop"):fetch(job)
	end

	-- A directory with its own repo is not this repo's business.
	if nested_repo(cwd) then
		return require("noop"):fetch(job)
	end

	local claimed = claim()
	if not claimed then
		return require("noop"):fetch(job)
	elseif not claimed.refresh then
		return retry(job)
	end

	local files, dirs, err = snapshot(claimed.git_dir)
	if err then
		ya.err("dotfiles: " .. err)
	end
	commit(files, dirs)

	return retry(job)
end

-- Forces the TTL open so the next claim always refreshes.
local invalidate = ya.sync(function(st)
	st.stale = true
	return st.git_dir ~= nil
end)

-- `plugin dotfiles` recomputes the snapshot and repaints straight away.
--
-- Staging a file changes the index but not the file, so nothing would otherwise
-- make yazi re-read the directory and re-run the fetcher. Rather than trying to
-- provoke a reload, this recomputes the state the linemode reads and calls
-- `ui.render()` itself, so the column updates without the cursor moving.
local function entry()
	if not invalidate() then
		return -- no dotfiles repo configured
	end

	local claimed = claim()
	if not claimed or not claimed.refresh then
		return -- inactive, or a refresh is already in flight
	end

	local files, dirs, err = snapshot(claimed.git_dir)
	if err then
		ya.err("dotfiles: " .. err)
	end
	commit(files, dirs)
end

return { setup = setup, fetch = fetch, entry = entry }
