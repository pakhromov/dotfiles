--- Universal to-PDF preview plugin
--- Converts any file type to PDF using specified command, then uses yazi's PDF preview
--- Displays page counter for PDF files

local M = {}

local STATE_KEY = {
	page_count = "page_count_",
}

local set_state = ya.sync(function(state, key, value)
	state[key] = value
end)

local get_state = ya.sync(function(state, key)
	return state[key]
end)

-- Get total page count from PDF file
local function get_page_count(pdf_path)
	local cache_key = STATE_KEY.page_count .. tostring(pdf_path)
	local cached = get_state(cache_key)
	if cached then
		return cached
	end

	local output, err = Command("pdfinfo"):arg(tostring(pdf_path)):output()
	if not output or err then
		return nil
	end

	local pages = output.stdout:match("Pages:%s*(%d+)")
	if pages then
		local count = tonumber(pages)
		set_state(cache_key, count)
		return count
	end
	return nil
end

local function fail(job, s)
	ya.preview_widget(job, ui.Text.parse(s):area(job.area):wrap(ui.Wrap.YES))
end

function M:peek(job)
	local pdf_path
	local is_native_pdf = job.mime == "application/pdf"

	if is_native_pdf then
		-- File is already a PDF, use it directly
		pdf_path = tostring(job.file.url)
	else
		-- Get the command from job args for non-PDF files
		if not job.args or not job.args[1] then
			return fail(job, "No command specified. Usage: to-pdf-preview -- command arg1 arg2...")
		end

		local command = job.args[1]

		-- Find the PDF file (create if needed) - use consistent cache directory
		local pdf_name = job.file.name:gsub("%.[^%.]+$", ".pdf")
		local pdf_cache_dir = os.getenv("HOME") .. "/.cache/yazi/to-pdf-preview"
		pdf_path = pdf_cache_dir .. "/" .. pdf_name

		-- If PDF doesn't exist, create it
		local pdf_url = Url(pdf_path)
		if not fs.cha(pdf_url) then
			local ok, err = self:convert_to_pdf(job, pdf_path, command)
			if not ok then
				return fail(job, err or "Failed to convert to PDF")
			end
		end
	end

	-- Convert PDF page to image for display using yazi's cache
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	-- Check if image cache exists
	if fs.cha(cache) then
		ya.sleep(math.max(0, 30 / 1000 + start - os.clock()))
		self:show_with_counter(job, cache, pdf_path)
		return
	end

	-- Convert PDF page to image for display
	local page_num = (job.skip or 0) + 1
	
	-- Use yazi's configured image quality
	local quality = rt.preview.image_quality or 90
	
	-- Use higher DPI for better quality images
	local dpi = 300  -- Increase from default 150 to 300 for better quality
	
	local output = Command("pdftoppm")
		:arg({
			"-singlefile",
			"-jpeg",
			"-jpegopt",
			"quality=" .. quality,
			"-r",
			dpi,
			"-f",
			page_num,
			"-l",
			page_num,
			pdf_path,
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not output or not output.status.success then
		-- Handle end of document gracefully
		local pages = tonumber(output and output.stderr:match("the last page %((%d+)%)")) or 0
		if job.skip > 0 and pages > 0 then
			ya.emit("peek", { math.max(0, pages - 1), only_if = job.file.url, upper_bound = true })
		end
		-- Don't show error, just return silently to preserve existing display
		return
	end

	local write_result = fs.write(cache, output.stdout)
	if write_result then
		ya.sleep(math.max(0, 30 / 1000 + start - os.clock()))
		self:show_with_counter(job, cache, pdf_path)
	else
		return fail(job, "Failed to write image cache")
	end
end

function M:show_with_counter(job, cache, pdf_path)
	-- Get total pages
	local total_pages = get_page_count(pdf_path)

	if not total_pages then
		-- If we can't get page count, just show the image without counter
		ya.image_show(cache, job.area)
		ya.preview_widgets(job, {})
		return
	end

	-- Calculate current page
	local current_page = (job.skip or 0) + 1
	current_page = math.max(1, math.min(current_page, total_pages))

	-- Reserve 1 line for page counter
	local text_height = 1
	local image_height = math.max(1, job.area.h - text_height)

	-- Show PDF page image
	local rendered_rect = ya.image_show(
		cache,
		ui.Rect({
			x = job.area.x,
			y = job.area.y,
			w = job.area.w,
			h = image_height,
		})
	)

	local actual_image_height = rendered_rect and rendered_rect.h or image_height

	-- Create page counter text (centered)
	local counter_text = string.format("Page %d/%d", current_page, total_pages)
	local text_width = #counter_text
	local padding = math.max(0, math.floor((job.area.w - text_width) / 2))
	local line = ui.Line({ ui.Span(string.rep(" ", padding)), ui.Span(counter_text) })

	-- Show page counter below image
	ya.preview_widget(job, {
		ui.Text({ line })
			:area(ui.Rect({
				x = job.area.x,
				y = job.area.y + actual_image_height,
				w = job.area.w,
				h = job.area.h - actual_image_height,
			}))
			:wrap(ui.Wrap.NO),
	})
end

function M:convert_to_pdf(job, pdf_path, command)
	-- Create cache directory
	local pdf_cache_dir = os.getenv("HOME") .. "/.cache/yazi/to-pdf-preview"
	Command("mkdir"):arg({ "-p", pdf_cache_dir }):output()
	
	-- Execute the specified command with file path
	-- Commands should output to the cache directory
	local output = Command("sh")
		:arg({ "-c", command, "sh", tostring(job.file.url) })
		:env("OUTDIR", pdf_cache_dir .. "/")
		:env("CLICOLOR_FORCE", "1")
		:output()

	if not output or not output.status.success then
		return false, "Command failed: " .. command
	end

	return true
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, job.units, 1)
		ya.emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })
	end
end

return M