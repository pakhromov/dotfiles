local M = {}

local SCRIPT = (os.getenv("HOME") or "") .. "/.config/yazi/plugins/xcursor-preview.yazi/xcursor2png.py"
local CACHE_DIR = (os.getenv("HOME") or "") .. "/.cache/yazi/xcursor-preview"
local LOG = "/tmp/xcursor_debug.log"

local function log(msg)
	local f = io.open(LOG, "a")
	if f then f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n"); f:close() end
end

local _cache_dir_ready = false
local function ensure_cache_dir()
	if not _cache_dir_ready then
		Command("mkdir"):arg({ "-p", CACHE_DIR }):output()
		_cache_dir_ready = true
	end
end


local function url_key(url)
	return tostring(url):gsub("[^%w%-]", "_")
end

local function cache_png(url, frame)
	return Url(CACHE_DIR .. "/" .. url_key(url) .. "_f" .. tostring(frame) .. ".png")
end

local set_state = ya.sync(function(state, k, v) state[k] = v end)
local get_state = ya.sync(function(state, k) return state[k] end)

local function read_line(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local l = f:read("*l"); f:close(); return l
end

local function write_line(path, content)
	local f = io.open(path, "w")
	if f then f:write(content); f:close() end
end

local function meta_file(url)
	return CACHE_DIR .. "/" .. url_key(url) .. ".meta"
end

local function is_xcursor(url)
	-- Check magic bytes "Xcur" to confirm this is actually an Xcursor file
	local f = io.open(tostring(url), "rb")
	if not f then return false end
	local magic = f:read(4); f:close()
	return magic == "Xcur"
end

local function render_frame(url, frame)
	ensure_cache_dir()
	local dest = cache_png(url, frame)
	if fs.cha(dest) then
		local m = read_line(meta_file(url))
		if m then set_state("meta_" .. tostring(url), m) end
		return true
	end

	local out, err = Command("python3")
		:arg({ SCRIPT, tostring(url), tostring(frame) })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if err or not out or not out.status.success then
		local raw = (out and out.stderr or "") .. tostring(err or "")
		local msg = raw:match("([^\n]+)") or "render failed"
		log("render_frame ERROR: " .. msg)
		return false, msg
	end

	local ok = fs.write(dest, out.stdout)
	if not ok then return false, "fs.write failed" end

	local meta = out.stderr:match("XCMETA: ([^\n]+)")
	if meta then
		set_state("meta_" .. tostring(url), meta)
		write_line(meta_file(url), meta)
	end

	return true
end

local function load_meta(url)
	local m = get_state("meta_" .. tostring(url))
	if m then return m end
	m = read_line(meta_file(url))
	if m then set_state("meta_" .. tostring(url), m) end
	return m
end

-- ── Entry points ─────────────────────────────────────────────────────────────

function M:preload(job)
	local url = job.file.url
	log("preload: " .. tostring(url))
	if not is_xcursor(url) then return true end
	local ok, err = render_frame(url, job.skip or 0)
	return ok or false, err
end

function M:peek(job)
	local url = job.file.url
	log("peek: mime=" .. tostring(job.mime) .. " url=" .. tostring(url))

	if not is_xcursor(url) then
		log("peek: not an xcursor file, skipping")
		return
	end

	local start = os.clock()
	local frame = job.skip or 0

	local ok, err = render_frame(url, frame)
	if not ok then
		log("peek: render failed: " .. tostring(err))
		ya.preview_widget(job, {
			ui.Text({ ui.Line("xcursor-preview error: " .. (err or "?")) })
				:area(job.area):wrap(ui.Wrap.YES),
		})
		return
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

	local dest = cache_png(url, frame)
	local meta = load_meta(url)
	local lines = {}
	local total_frames = 1

	if meta then
		local w, h, xhot, yhot, delay, _fi, tf, sizes_str =
			meta:match("(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (.*)")
		if w then
			total_frames = tonumber(tf) or 1
			local cur = frame % total_frames
			table.insert(lines, ui.Line({ ui.Span(w .. "×" .. h):style(ui.Style():fg("blue"):bold()) }))
			table.insert(lines, ui.Line({
				ui.Span("hotspot: "):style(ui.Style():fg("reset")),
				ui.Span(xhot .. "," .. yhot):style(ui.Style():fg("yellow")),
			}))
			if total_frames > 1 then
				table.insert(lines, ui.Line({
					ui.Span("frame: "):style(ui.Style():fg("reset")),
					ui.Span((cur + 1) .. "/" .. tf):style(ui.Style():fg("green")),
				}))
				table.insert(lines, ui.Line({
					ui.Span("delay: "):style(ui.Style():fg("reset")),
					ui.Span(delay .. "ms"):style(ui.Style():fg("yellow")),
				}))
			end
			if sizes_str and sizes_str ~= "" then
				table.insert(lines, ui.Line({
					ui.Span("sizes: "):style(ui.Style():fg("reset")),
					ui.Span(sizes_str:gsub(" ", ", ")):style(ui.Style():fg("cyan")),
				}))
			end
		end
	end

	set_state("total_frames_" .. tostring(url), total_frames)

	local text_h = #lines
	local img_area = ui.Rect({
		x = job.area.x, y = job.area.y,
		w = job.area.w,
		h = text_h > 0 and math.max(1, job.area.h - text_h) or job.area.h,
	})

	local rendered = ya.image_show(dest, img_area)
	local img_h = rendered and rendered.h or img_area.h

	if text_h > 0 then
		ya.preview_widget(job, {
			ui.Text(lines)
				:area(ui.Rect({
					x = job.area.x, y = job.area.y + img_h,
					w = job.area.w, h = job.area.h - img_h,
				}))
				:wrap(ui.Wrap.NO),
		})
	end
	log("peek: done, img_h=" .. tostring(img_h))
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local url = job.file.url
		local total = get_state("total_frames_" .. tostring(url)) or 1
		local new_skip = ((cx.active.preview.skip or 0) + job.units) % total
		if new_skip < 0 then new_skip = new_skip + total end
		ya.emit("peek", { new_skip, only_if = job.file.url })
	end
end

return M
