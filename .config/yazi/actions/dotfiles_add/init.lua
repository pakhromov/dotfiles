local M = {}

function M.init(_, opts)
	local home = os.getenv("HOME")
	local out = Command("git")
		:arg({ "--git-dir=" .. home .. "/.dotfiles-git", "--work-tree=" .. home, "add" })
		:arg(opts.selected)
		:stderr(Command.PIPED)
		:output()

	if not out or not out.status.success then
		local msg = (out and out.stderr ~= "" and out.stderr) or "unknown error"
		ya.notify({
			title = "Dotfiles",
			content = "git add failed:\n" .. msg,
			timeout = 8.0,
			level = "error",
		})
		return
	end

	local n = #opts.selected
	ya.notify({
		title = "Dotfiles",
		content = string.format("Added %d file%s to dotfiles", n, n == 1 and "" or "s"),
		timeout = 5.0,
		level = "info",
	})
end

return M
