local M = {}

function M.init(_, opts)
	local home = os.getenv("HOME")
	-- `--cached` unstages only: the working tree file is left alone, so this stops
	-- tracking a dotfile without deleting it. `--force` skips the check for content
	-- differing from HEAD, which exists to prevent losing working tree data and so
	-- has nothing to guard while `--cached` is in play. `-r` lets a directory be
	-- selected; `--` keeps a leading-dash filename from being read as an option.
	local out = Command("git")
		:arg({
			"--git-dir=" .. home .. "/.dotfiles-git",
			"--work-tree=" .. home,
			"rm", "--cached", "-r", "--force", "--",
		})
		:arg(opts.selected)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not out or not out.status.success then
		local msg = (out and out.stderr ~= "" and out.stderr) or "unknown error"
		ya.notify({
			title = "Dotfiles",
			content = "git rm --cached failed:\n" .. msg,
			timeout = 8.0,
			level = "error",
		})
		return
	end

	-- Repaint the dotfiles column now. The index changed but no file did, so
	-- nothing else would make yazi re-read this directory.
	ya.emit("plugin", { "dotfiles" })

	-- git prints one `rm '<path>'` line per file it untracked. Counting those
	-- reports what actually left the index, which is not the number of entries
	-- selected when one of them is a directory.
	local n = 0
	for _ in out.stdout:gmatch("[^\r\n]+") do
		n = n + 1
	end

	ya.notify({
		title = "Dotfiles",
		content = string.format("Removed %d file%s from dotfiles, kept on disk", n, n == 1 and "" or "s"),
		timeout = 5.0,
		level = "info",
	})
end

return M
