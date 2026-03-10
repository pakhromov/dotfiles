local M = {}

--luacheck: ignore output err
function M.init(_, opts)
	-- 判断系统 如果是mac 需要 coreutils 因为脚本需要 grealpath
	local output, err = Command("uname"):arg("-s"):output()
	local OS = string.gsub(tostring(output.stdout), "%s$", "")
	if OS == "Darwin" then
		output, err = Command("which"):arg("grealpath"):output()
		if not output.status.success then
			ya.notify({
				title = "Coreutils Required ",
				content = "You can install coreutils by running brew install coreutils in the terminal.",
				timeout = 6.0,
				level = "warn",
			})
			return
		end
	end

	-- Always use combined mode
	local choice_mode = #opts.selected == 1 and "single" or "multiple"
	local compression_mode = "combined"

	-- Generate default archive name
	local default_name
	if #opts.selected == 1 then
		-- Single file/folder: use its name
		local item = opts.selected[1]
		default_name = item:match("([^/]+)$") or "archive"
		-- Remove extension if it's a file
		default_name = default_name:match("(.+)%..+$") or default_name
	else
		-- Multiple items: use parent directory name
		local parent = opts.selected[1]:match("(.+)/[^/]+$") or ""
		default_name = parent:match("([^/]+)$") or "archive"
	end

	-- Prompt for archive name
	local value, event = ya.input({
		title = "Archive name:",
		value = default_name,
		pos = { "top-center", w = 40 },
	})

	-- User cancelled
	if event ~= 1 or not value or value == "" then
		return
	end

	local archive_name = value

	-- The script here won't work without "./"
	-- The script file must have execution permissions
	-- stylua: ignore
	output, err = Command("./ziparchive.sh")
		:cwd(opts.workpath) -- Enter the directory of the action plugin
		:env("choice_mode", choice_mode)
		:env("compression_mode", compression_mode)
		:env("archive_name", archive_name)
		-- To avoid issues with spaces in filenames, here we use Tab to separate
		-- Therefore, in the script file, it must declare IFS=$'\t'
		:env("selection", table.concat(opts.selected, "\t"))
		:output()

	if opts.flags.debug then
		ya.err("====debug info====")
		if err ~= nil then
			ya.err("err:" .. tostring(err))
		else
			ya.err("OK? :" .. tostring(output.status.success))
			ya.err("Code:" .. tostring(output.status.code))
			ya.err("stdout:" .. output.stdout)
			ya.err("stderr" .. output.stderr)
		end
	end
	--For detailed usage of the 'output' and 'err' variables,
	--please refer to: https://yazi-rs.github.io/docs/plugins/utils#output
end

return M
