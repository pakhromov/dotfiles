--- @since 25.12.29

-- Open and close are separate and idempotent, rather than one toggle. A toggle
-- can only stay balanced if every exit path calls it exactly once; the modal
-- being left on screen with no input loop behind it is what that costs when it
-- doesn't. `active` also stops a second invocation starting a second loop.
local claim_ui = ya.sync(function(self)
	if self.active then
		return false
	end
	self.active = true
	self.children = self.children or Modal:children_add(self, 10)
	ui.render()
	return true
end)

local release_ui = ya.sync(function(self)
	self.active, self.busy = false, nil
	if self.children then
		Modal:children_remove(self.children)
		self.children = nil
	end
	ui.render()
end)

-- Shown in the border while an operation runs, since the input loop cannot read
-- keys until it returns.
local set_busy = ya.sync(function(self, what)
	self.busy = what
	ui.render()
end)

local update_partitions = ya.sync(function(self, partitions)
	self.partitions = partitions
	self.cursor = math.max(0, math.min(self.cursor or 0, #self.partitions - 1))
	ui.render()
end)

local active_partition = ya.sync(function(self) return self.partitions[self.cursor + 1] end)

local update_cursor = ya.sync(function(self, cursor)
	if #self.partitions == 0 then
		self.cursor = 0
	else
		local new_cursor = self.cursor + cursor
		-- Wrap around: if going past end, go to start; if going before start, go to end
		if new_cursor < 0 then
			self.cursor = #self.partitions - 1
		elseif new_cursor >= #self.partitions then
			self.cursor = 0
		else
			self.cursor = new_cursor
		end
	end
	ui.render()
end)

local M = {
	keys = {
		{ on = "q", run = "quit" },
		{ on = "<Esc>", run = "quit" },

		{ on = "<Space>", run = "mount" },
		{ on = "<Enter>", run = "mount" },

		{ on = "<Up>", run = "up" },
		{ on = "<Down>", run = "down" },
		{ on = "<Right>", run = "mount_and_open" },
		{ on = "<Left>", run = "unmount" },

		{ on = "e", run = "eject" },
	},
}

function M:new(area)
	self:layout(area)
	return self
end

function M:layout(area)
	local chunks = ui.Layout()
		:constraints({
			ui.Constraint.Percentage(25),
			ui.Constraint.Percentage(50),
			ui.Constraint.Percentage(25),
		})
		:split(area)

	local chunks = ui.Layout()
		:direction(ui.Layout.HORIZONTAL)
		:constraints({
			ui.Constraint.Percentage(25),
			ui.Constraint.Percentage(50),
			ui.Constraint.Percentage(25),
		})
		:split(chunks[2])

	self._area = chunks[2]
end

function M:entry(job)
	if job.args[1] == "refresh" then
		return update_partitions(self.obtain())
	end

	if not claim_ui() then
		return -- already open; a second input loop would fight this one for keys
	end
	update_partitions(self.obtain())

	-- An operation that fails must not take the whole UI down with it: report it
	-- and carry on reading keys.
	local function run(what, op)
		set_busy(what)
		local ok, err = pcall(function()
			self.operate(op)
			update_partitions(self.obtain())
		end)
		set_busy(nil)
		if not ok then
			M.fail("Mount: %s", tostring(err))
		end
	end

	local function input_loop()
		while true do
			local cand = self.keys[ya.which { cands = self.keys, silent = true }] or { run = {} }
			for _, r in ipairs(type(cand.run) == "table" and cand.run or { cand.run }) do
				if r == "quit" then
					return
				elseif r == "up" then
					update_cursor(-1)
				elseif r == "down" then
					update_cursor(1)
				elseif r == "mount_and_open" then
					local active = active_partition()
					if active and active.dist then
						ya.emit("cd", { active.dist })
						return
					end
					run("Mounting…", "mount")
				elseif r == "mount" then
					run("Mounting…", "mount")
				elseif r == "unmount" then
					run("Unmounting…", "unmount")
				elseif r == "eject" then
					run("Ejecting…", "eject")
				end
			end
		end
	end

	ya.join(function()
		local ok, err = pcall(input_loop)
		-- Runs on every path, including an unexpected error, so the modal can
		-- never be left on screen with nothing reading keys.
		release_ui()
		if not ok then
			M.fail("Mount: %s", tostring(err))
		end
	end)
end

function M:reflow() return { self } end

function M:redraw()
	local rows = {}
	for _, p in ipairs(self.partitions or {}) do
		if not p.sub then
			rows[#rows + 1] = ui.Row { p.main }
		elseif p.sub == "" then
			local size_str = p.size and ya.readable_size(p.size) or ""
			rows[#rows + 1] = ui.Row { p.main, p.label or "", p.fstype or "", size_str, p.dist or "" }
		else
			local size_str = p.size and ya.readable_size(p.size) or ""
			rows[#rows + 1] = ui.Row { "  " .. p.sub, p.label or "", p.fstype or "", size_str, p.dist or "" }
		end
	end

	return {
		ui.Clear(self._area),
		ui.Border(ui.Edge.ALL)
			:area(self._area)
			:type(ui.Border.ROUNDED)
			:style(ui.Style():fg("blue"))
			:title(ui.Line(self.busy or "Mount"):align(ui.Align.CENTER)),
		ui.Table(rows)
			:area(self._area:pad(ui.Pad(1, 2, 1, 2)))
			:header(ui.Row({ "Src", "Label", "FSType", "Size", "Dist" }):style(ui.Style():bold()))
			:row(self.cursor)
			:row_style(ui.Style():fg("blue"):underline())
			:widths {
				ui.Constraint.Length(15),
				ui.Constraint.Length(15),
				ui.Constraint.Length(15),
				ui.Constraint.Length(15),
				ui.Constraint.Length(40),
			},
	}
end

function M.obtain()
	local tbl = {}
	local last
	for _, p in ipairs(fs.partitions()) do
		local main, sub = M.split(p.src)
		if main and last ~= main then
			if p.src == main then
				last, p.main, p.sub, tbl[#tbl + 1] = p.src, p.src, "", p
			else
				last, tbl[#tbl + 1] = main, { src = main, main = main, sub = "" }
			end
		end
		if sub then
			if tbl[#tbl].sub == "" and tbl[#tbl].main == main then
				tbl[#tbl].sub = nil
			end
			p.main, p.sub, tbl[#tbl + 1] = main, sub, p
		end
	end
	table.sort(M.fillin(tbl), function(a, b)
		if a.main == b.main then
			return (a.sub or "") < (b.sub or "")
		else
			return a.main > b.main
		end
	end)
	return tbl
end

function M.split(src)
	local pats = {
		{ "^/dev/sd[a-z]", "%d+$" }, -- /dev/sda1
		{ "^/dev/nvme%d+n%d+", "p%d+$" }, -- /dev/nvme0n1p1
		{ "^/dev/mmcblk%d+", "p%d+$" }, -- /dev/mmcblk0p1
		{ "^/dev/disk%d+", ".+$" }, -- /dev/disk1s1
		{ "^/dev/sr%d+", ".+$" }, -- /dev/sr0
	}
	for _, p in ipairs(pats) do
		local main = src:match(p[1])
		if main then
			return main, src:sub(#main + 1):match(p[2])
		end
	end
end

function M.fillin(tbl)
	if ya.target_os() ~= "linux" then
		return tbl
	end

	-- Collect all partition sources (both mounted and unmounted)
	local sources, indices = {}, {}
	for i, p in ipairs(tbl) do
		if p.sub then
			sources[#sources + 1], indices[p.src] = p.src, i
		end
	end
	if #sources == 0 then
		return tbl
	end

	-- Get both fstype and size from lsblk.
	--
	-- Wrapped in `timeout` because lsblk can block for a long time probing a USB
	-- device that was just unmounted or is spinning down, and this runs on the
	-- same coroutine as the key loop — a hang here reads as "the modal stopped
	-- responding". A missed refresh is far cheaper than that.
	local output, err = Command("timeout")
		:arg({ "5", "lsblk", "-p", "-b", "-o", "name,fstype,size", "-J" })
		:arg(sources)
		:output()
	if not output then
		ya.dbg("Failed to fetch partition info: " .. tostring(err))
		return tbl
	end

	local ok, t = pcall(ya.json_decode, output.stdout or "")
	if not ok then
		return tbl
	end
	for _, p in ipairs(t and t.blockdevices or {}) do
		if indices[p.name] then
			tbl[indices[p.name]].fstype = p.fstype
			tbl[indices[p.name]].size = tonumber(p.size)
		end
	end
	return tbl
end

function M.operate(type)
	local active = active_partition()
	if not active then
		return
	elseif not active.sub then
		return -- TODO: mount/unmount main disk
	end

	local output, err
	if ya.target_os() == "macos" then
		output, err = Command("diskutil"):arg({ type, active.src }):output()
	end
	if ya.target_os() == "linux" then
		local home = os.getenv("HOME")
		local mnt_base = home .. "/mnt"
		-- Get the device name (e.g., sda1 from /dev/sda1)
		local dev_name = active.src:match("/dev/(.+)$")
		local mount_point = mnt_base .. "/" .. dev_name

		if type == "mount" then
			-- Create mount directory if it doesn't exist
			Command("mkdir"):arg({ "-p", mount_point }):status()
			-- FAT/NTFS filesystems store no Unix permissions, so pass uid/gid to own the mount
			local uid = os.getenv("UID") or tostring(io.popen("id -u"):read("*n"))
			local gid = os.getenv("GID") or tostring(io.popen("id -g"):read("*n"))
			local fat_fstypes = { vfat = true, fat = true, fat32 = true, exfat = true, ntfs = true, ["ntfs-3g"] = true }
			local args = { "mount", active.src, mount_point }
			if fat_fstypes[active.fstype] then
				args = { "mount", "-o", "uid=" .. uid .. ",gid=" .. gid, active.src, mount_point }
			end
			local status = Command("sudo"):arg(args):status()
			if not status or not status.success then
				M.fail("Failed to mount `%s`", active.src)
			end
			return
		elseif type == "unmount" then
			local umount_target = active.dist or active.src
			local status = Command("sudo"):arg({ "umount", "-l", umount_target }):status()
			if not status or not status.success then
				M.fail("Failed to unmount `%s`", umount_target)
			end
			return
		elseif type == "eject" then
			-- Unmount first
			if active.dist then
				Command("sudo"):arg({ "umount", "-l", active.dist }):status()
			end
			-- Then eject/power-off
			if active.src:match("^/dev/sr%d+") then
				output, err = Command("eject"):arg({ "--traytoggle", active.src }):output()
			else
				output, err = Command("udisksctl"):arg({ "power-off", "-b", active.src }):output()
			end
		end
	end

	if not output then
		M.fail("Failed to %s `%s`: %s", type, active.src, err)
	elseif not output.status.success then
		M.fail("Failed to %s `%s`: %s", type, active.src, output.stderr)
	end
end

function M.fail(...) ya.notify { title = "Mount", content = string.format(...), timeout = 10, level = "error" } end

function M:click() end

function M:scroll() end

function M:touch() end

return M
