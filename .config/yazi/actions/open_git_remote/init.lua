local M = {}

function M:init(opts)
	local path = opts.selected[1]
	if not path then
		ya.notify({ title = "Open Git Remote", content = "No file selected", timeout = 3.0, level = "warn" })
		return
	end

	-- Try path as directory first, then its parent
	local output = Command("git"):arg("-C"):arg(path):arg("remote"):arg("get-url"):arg("origin"):output()
	if not output or not output.status.success then
		local dir = path:match("(.+)/[^/]+$") or path
		output = Command("git"):arg("-C"):arg(dir):arg("remote"):arg("get-url"):arg("origin"):output()
	end

	if not output or not output.status.success then
		ya.notify({ title = "Open Git Remote", content = "No git remote found", timeout = 3.0, level = "warn" })
		return
	end

	local url = output.stdout:gsub("%s+$", "")

	-- Convert SSH URL to HTTPS
	-- git@github.com:user/repo.git -> https://github.com/user/repo
	-- ssh://git@github.com/user/repo.git -> https://github.com/user/repo
	if url:match("^git@") then
		url = url:gsub("^git@", "https://"):gsub(":([^/])", "/%1")
	elseif url:match("^ssh://") then
		url = url:gsub("^ssh://git@", "https://"):gsub("^ssh://", "https://")
	end

	-- Remove .git suffix
	url = url:gsub("%.git$", "")

	Command("xdg-open"):arg(url):output()
end

return M
