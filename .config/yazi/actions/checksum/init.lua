local M = {}

-- Calculate checksum for a single target (file or directory)
local function calculate_checksum(target, algo)
	-- Check if target is a directory
	local stat_output = Command("test"):arg({ "-d", target }):status()
	local is_directory = stat_output and stat_output.success

	local output, err

	if is_directory then
		-- For directories: recursively hash all files, sort, and hash the result
		local cmd = string.format(
			"find %s -type f -exec %s {} + 2>/dev/null | sort | %s",
			ya.quote(target),
			algo.cmd,
			algo.cmd
		)

		output, err = Command("sh")
			:arg({ "-c", cmd })
			:stdout(Command.PIPED)
			:output()
	else
		-- For files: direct checksum
		output, err = Command(algo.cmd)
			:arg(target)
			:stdout(Command.PIPED)
			:output()
	end

	if not output or output.status.code ~= 0 then
		return nil, is_directory
	end

	-- Extract checksum from output (format: "hash  filename")
	local checksum = string.match(output.stdout, "^(%S+)")
	return checksum, is_directory
end

function M.init(_, opts)
	local targets = opts.selected
	local num_targets = #targets

	-- Algorithm options for popup menu
	local menuOptions = {
		"MD5",
		"SHA1",
		"SHA256",
		"SHA512",
	}

	-- Map cursor position to algorithm command
	local algo_map = {
		[1] = { cmd = "md5sum", name = "MD5" },
		[2] = { cmd = "sha1sum", name = "SHA1" },
		[3] = { cmd = "sha256sum", name = "SHA256" },
		[4] = { cmd = "sha512sum", name = "SHA512" },
	}

	local selected_algo
	local cancel = false

	-- Confirmation callback
	local onConfirm = function(cursor)
		selected_algo = algo_map[cursor]
	end

	-- Cancel callback
	local onCancel = function()
		cancel = true
	end

	-- Show popup menu
	local menu = Popup.Menu:init(menuOptions, opts.flags.around, onConfirm, onCancel)
	menu:show()

	-- User cancelled
	if cancel or not selected_algo then
		return
	end

	local algo = selected_algo

	if num_targets == 1 then
		-- Single file/directory mode
		local target = targets[1]
		local checksum, is_directory = calculate_checksum(target, algo)

		if checksum then
			-- Copy to clipboard
			ya.clipboard(checksum)

			-- Show notification with the checksum
			local target_type = is_directory and "Directory" or "File"
			ya.notify({
				title = string.format("%s %s Checksum", algo.name, target_type),
				content = string.format("%s\n\n(Copied to clipboard)", checksum),
				timeout = 10.0,
				level = "info",
			})
		else
			ya.notify({
				title = "Checksum Error",
				content = string.format("Failed to calculate %s checksum", algo.name),
				timeout = 6.0,
				level = "error",
			})
		end
	else
		-- Multiple files mode
		local results = {}
		local errors = 0

		for _, target in ipairs(targets) do
			local checksum, _ = calculate_checksum(target, algo)
			local filename = target:match("([^/]+)$") or target

			if checksum then
				table.insert(results, string.format("%s  %s", checksum, filename))
			else
				errors = errors + 1
			end
		end

		if #results > 0 then
			-- Join all results
			local all_checksums = table.concat(results, "\n")

			-- Copy all checksums to clipboard
			ya.clipboard(all_checksums)

			-- Show notification
			local content = string.format("%d files processed", #results)
			if errors > 0 then
				content = content .. string.format(", %d errors", errors)
			end
			content = content .. "\n\n(All checksums copied to clipboard)"

			ya.notify({
				title = string.format("%s Checksums", algo.name),
				content = content,
				timeout = 10.0,
				level = "info",
			})
		else
			ya.notify({
				title = "Checksum Error",
				content = "Failed to calculate any checksums",
				timeout = 6.0,
				level = "error",
			})
		end
	end
end

return M
