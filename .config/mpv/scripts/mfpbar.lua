--TODO: performance/restructuring

local msg = require('mp.msg')
local utils = require('mp.utils')
local mpopt = require('mp.options')

local state = {
	osd = nil,
	dpy_w = 0,
	dpy_h = 0,
	pbar = true,
	mouse = nil,
	cache_state = nil,
	duration = nil,
	chapters = nil,
	press_bounded = false,
	thumbfast = {
		width = 0,
		height = 0,
		disabled = true,
		available = false
	},
	draw_buffer = {},
	timer = nil,
	last_time_pos = nil,
	user_hidden = false
}

local opt = {
	pbar_mode = "bar",
	pbar_line_thickness = 3,
	pbar_height = 4,
	pbar_color = "CCCCCC",
	pbar_bg_color = "000000C0",
	cachebar_height = 1,
	cachebar_color = "1C6C89",
	timeline_rhs = "time-remaining",
	hover_bar_color = "BDAE93",
	hover_bar_thickness = 2,
	hb_font_color = "EBEBEB",
	hb_font_size = 16,
	hb_font_pad_x = 10,
	hb_font_pad_y = 0,
	hb_font_border_width = 3,
	hb_font_border_color = 000000,
	font_color = "EBEBEB",
	font_size = 16,
	font_pad_x = 0,
	font_pad_y = 0,
	font_border_width = 2,
	font_border_color = "000000",
	preview_border_width = 2,
	preview_border_color = "BDAE93",
	chapter_marker_size = 3,
	chapter_marker_color = "BDAE93",
	chapter_marker_border_width = 1,
	chapter_marker_border_color = "161616",
	chapter_marker_scale = 1.5,
	chapter_cut_marker_color = "00008B",
	chapter_proximity = 20,
	pbar_margin_left = 200,
	pbar_margin_right = 200,
	rounded_lower_corners = true,
	rounded_higher_corners = true,
	corner_radius = 16,
	floating_height = 0,
	timeout = 0.5,
	screen_percentage = 20,
	show_when_paused = true
}


local function format_time(t)
	local h = math.floor(t / (60 * 60))
	t = t - (h * 60 * 60)
	local m = math.floor(t / 60)
	local s = t - (m * 60)
    if state.duration >= 3600 then
        return string.format("%.2d:%.2d:%.2d", h, m, s)
    else
        return string.format("%.2d:%.2d", m, s)
    end
end

local function esc_ass(s)
	s = s:gsub('\\', '\\\\\239\187\191')
	s = s:gsub('{', '\\{')
	s = s:gsub('}', '\\}')
	return s
end

local function format_cache_display()
	local cache_duration = state.cache_state["cache-duration"]
    local min = math.floor(cache_duration / 60)
    local sec = math.floor(cache_duration % 60)
    return (min > 0 and
        string.format("%sm%02.0fs", min, sec) or
        string.format("%3.0fs", sec))
end

local function get_pbar_dimensions(dpy_w)
	local left_margin = opt.pbar_margin_left
	local right_margin = opt.pbar_margin_right
	local pbar_width = dpy_w - left_margin - right_margin
	local pbar_x = left_margin
	return pbar_x, pbar_width
end

local function mouse_on_progress_bar(m)
	if not m or not m.hover then return false end
	local pb_h = opt.pbar_height -- Calculate progress bar height and position
	pb_h = math.max(math.floor(pb_h + 0.5), 4)
	local pb_y = state.dpy_h - pb_h - opt.floating_height
	local pbar_x, pbar_width = get_pbar_dimensions(state.dpy_w) -- Get progress bar X position and width
	return m.y >= pb_y and m.y <= (state.dpy_h - opt.floating_height) and m.x >= pbar_x and m.x <= (pbar_x + pbar_width) -- Check if mouse is within the progress bar area (both X and Y)
end


local function mouse_near_chapter(m, duration)
	if not m or not m.hover or not state.chapters or not duration or opt.chapter_proximity == 0 then return false, nil end
	local pb_h = opt.pbar_height
	pb_h = math.max(math.floor(pb_h + 0.5), 4)
	local marker_y = state.dpy_h - pb_h - opt.floating_height
	local pbar_x, pbar_width = get_pbar_dimensions(state.dpy_w)

	for _, c in ipairs(state.chapters) do
		if c.time >= 0 and c.time < duration then
			local x = pbar_x + (pbar_width * (c.time / duration))
			local check_y = marker_y -- Special Y position for start chapter
			if c.time == 0 then
				check_y = marker_y + (pb_h / 2)  -- Center of progress bar
			end
			local prox = (c.time == 0) and opt.chapter_proximity * 1.3 or opt.chapter_proximity
			if (math.abs(x - m.x) <= prox and math.abs(check_y - m.y) <= prox) then
				return true, c.time
			end
		end
	end
	return false, nil
end

local function hover_to_sec(mx, dw, duration)
	if not duration then return 0 end
	local pbar_x, pbar_width = get_pbar_dimensions(dw)
	local relative_x = mx - pbar_x  -- Convert to relative position within progress bar
	local n = duration * ((relative_x + 0.5) / pbar_width)
	return math.min(math.max(n, 0), duration)
end

-- Optimized rendering functions
local function render()
	if #state.draw_buffer > 0 then
		state.osd.data = table.concat(state.draw_buffer, '\n')
		state.draw_buffer = {}
	end
	state.osd:update()
end


local function draw_color(color, section)
	local bgr = string.sub(color, 1, 6)
	local opacity = string.sub(color, 7, 8)
	local ret  = '{\\' .. section .. 'c&' .. bgr     .. '&}'
	ret = ret .. '{\\' .. section .. 'a&' .. opacity .. '&}'
	return ret
end

local function draw_rect_point(x0, y0, x1, y1, x2, y2, x3, y3, color, opt)
	local s = '{\\pos(0, 0)\\an7}'
	opt = opt or {}
	s = s .. draw_color(color, "1");
	s = s .. draw_color(opt.bcolor or "00000000", "3");
	s = s .. '{\\bord' .. (opt.bw or '0') .. '}'
	s = s .. string.format(
		'{\\p1}m %d %d l %d %d %d %d %d %d{\\p0}',
		x0, y0, x1, y1, x2, y2, x3, y3
	)
	table.insert(state.draw_buffer, s)
end

local function draw_rect(x, y, w, h, color, opt)
	draw_rect_point(
		x,      y,
		x + w,  y,
		x + w,  y + h,
		x,      y + h,
		color, opt
	)
end

local function draw_text(x, y, size, text, opt)
	local s = string.format('{\\pos(%d, %d)}{\\fs%d}', x, y, size)
	opt = opt or {}
	s = s .. draw_color(opt.color  or "EBEBEB00", "1");
	s = s .. draw_color(opt.bcolor or "00000000", "3");
	s = s .. '{\\bord' .. (opt.bw or '0') .. '}'
	s = s .. text
	table.insert(state.draw_buffer, s)
end

local function draw_rounded_rect(x, y, w, h, color, opt_param)
	opt_param = opt_param or {}
	local radius = opt.corner_radius
	if (not opt.rounded_lower_corners and not opt.rounded_higher_corners) or w <= radius then
		draw_rect(x, y, w, h, color, opt_param)
		return
	end

	local s = '{\\pos(0, 0)\\an7}'
	s = s .. draw_color(color, "1");
	s = s .. draw_color(opt_param.bcolor or "00000000", "3");
	s = s .. '{\\bord' .. (opt_param.bw or '0') .. '}'

	local path = '{\\p1}'
	if opt.rounded_higher_corners then -- Start from top-left, going clockwise
		path = path .. string.format('m %d %d', x, y + radius) -- Top-left rounded corner
		path = path .. string.format(' b %d %d %d %d %d %d', x, y, x + radius, y, x + radius, y)
	else
		path = path .. string.format('m %d %d l %d %d', x, y, x + radius, y) -- Top-left sharp corner
	end

	path = path .. string.format(' l %d %d', x + w - radius, y) -- Top edge
	if opt.rounded_higher_corners then
		path = path .. string.format(' b %d %d %d %d %d %d', x + w, y, x + w, y + radius, x + w, y + radius) -- Top-right rounded corner
	else
		path = path .. string.format(' l %d %d', x + w, y + radius) -- Top-right sharp corner
	end

	path = path .. string.format(' l %d %d', x + w, y + h - radius) -- Right edge
	if opt.rounded_lower_corners then
		path = path .. string.format(' b %d %d %d %d %d %d', x + w, y + h, x + w - radius, y + h, x + w - radius, y + h) -- Bottom-right rounded corner
	else
		path = path .. string.format(' l %d %d l %d %d', x + w, y + h, x + w - radius, y + h) -- Bottom-right sharp corner
	end

	path = path .. string.format(' l %d %d', x + radius, y + h) -- Bottom edge
	if opt.rounded_lower_corners then
		path = path .. string.format(' b %d %d %d %d %d %d', x, y + h, x, y + h - radius, x, y + h - radius) -- Bottom-left rounded corner
	else
		path = path .. string.format(' l %d %d l %d %d', x, y + h, x, y + h - radius) -- Bottom-left sharp corner
	end

	path = path .. '{\\p0}'
	s = s .. path
	table.insert(state.draw_buffer, s)
end

-- Optimized drawing with state change detection
local function pbar_draw()
	local dpy_w = state.dpy_w
	local dpy_h = state.dpy_h
	local ypos = 0
	local play_pos = mp.get_property_native("percent-pos")
	local duration = state.duration
	local clist = state.chapters

	if (play_pos == nil or dpy_w == 0 or dpy_h == 0 or not duration) then
		return
	end

	state.draw_buffer = {} -- Clear buffer

	-- L0: background
	local pb_h = opt.pbar_height
	pb_h = math.max(math.floor(pb_h + 0.5), 4)
	local pbar_x, pbar_width = get_pbar_dimensions(dpy_w)
	local pb_w = pbar_width * (play_pos/100.0)  -- Progress within the bar
	local pb_y = dpy_h - (pb_h + ypos) - opt.floating_height
	local fs = opt.font_size
	local fopt = { color = opt.font_color, bw = opt.font_border_width, bcolor = opt.font_border_color }
	local timeline_y = dpy_h - opt.floating_height - opt.font_pad_y
	draw_rounded_rect(pbar_x, pb_y, pbar_width, pb_h, opt.pbar_bg_color)

	-- L1: cache line
	-- Use torrent piece ranges (sent by webtorrent server) when available;
	local cache_ranges = nil
	if state.torrent_ranges then
		-- webtorrent: convert piece fractions to seconds
		cache_ranges = {}
		for _, r in ipairs(state.torrent_ranges) do
			table.insert(cache_ranges, { start = r[1] * duration, ["end"] = r[2] * duration })
		end
	elseif not state.is_local and state.cache_state and state.cache_state["seekable-ranges"] then
		-- remote (YouTube, etc.): use mpv's demuxer read-ahead
		cache_ranges = state.cache_state["seekable-ranges"]
	end
	-- local files: cache_ranges stays nil, no bar drawn
	if (cache_ranges and #cache_ranges > 0 and opt.cachebar_height > 0) then
		local ch = opt.cachebar_height
		ch = math.max(math.floor(ch + 0.5), 2)
		local cache_y = pb_y + (pb_h - ch) / 2 + 1
		local cache_pbar_x, cache_pbar_width = get_pbar_dimensions(dpy_w)
		for _, range in ipairs(cache_ranges) do
			local s = range['start']
			local e = range['end']
			local sp = cache_pbar_x + (cache_pbar_width * (s / duration))
			local ep = (cache_pbar_width * ((e - s) / duration))
			draw_rect(sp, cache_y, ep, ch, opt.cachebar_color)
		end
	end

	--L2: progress line/bar
	if opt.pbar_mode == "line" then
		local line_thickness = opt.pbar_line_thickness
		local line_x = math.max(pbar_x + pb_w - (line_thickness / 2), pbar_x)
		local line_w = math.min(line_thickness, pbar_x + pbar_width - line_x)
		draw_rect(line_x, pb_y, line_w, pb_h, opt.pbar_color)
		-- L3: cached time
		if not state.torrent_ranges and not state.is_local and (state.cache_state and state.cache_state["seekable-ranges"] and state.cache_state["cache-duration"] and #state.cache_state["seekable-ranges"] > 0) then
			local cache_time = format_cache_display()
			local cache_x = line_x + line_thickness + opt.hb_font_pad_x
			local time_x = opt.hb_font_size*8
			if state.duration >= 3600 then
				time_x = opt.hb_font_size*12
			end
			if cache_x < time_x + opt.font_pad_x - 10 then
				cache_x = time_x + opt.font_pad_x - 10
			elseif cache_x > dpy_w - time_x - opt.font_pad_x - string.len(cache_time)*opt.hb_font_size*2 + 110 then
				cache_x = dpy_w - time_x - opt.font_pad_x - string.len(cache_time)*opt.hb_font_size*2 + 110
			end
			local hb_fopt = { color = opt.hb_font_color, bw = opt.hb_font_border_width, bcolor = opt.hb_font_border_color }
			draw_text(cache_x, pb_y + pb_h/2 + 1 - opt.hb_font_pad_y, opt.hb_font_size, "{\\an4}" .. cache_time, fopt)
		end
	else
		if pb_w > 0 then
			draw_rounded_rect(pbar_x, pb_y, pb_w, pb_h, opt.pbar_color)
		end
	end
	ypos = ypos + pb_h

	-- L4: chapters
	local near_chapter = false
	local chapter_time = nil
	if state.mouse and state.mouse.hover then
		near_chapter, chapter_time = mouse_near_chapter(state.mouse, duration)
	end
	if (clist and opt.chapter_marker_size > 0) then
		local bw = opt.chapter_marker_border_width
		local tw = opt.chapter_marker_size
		local y = dpy_h - pb_h - opt.floating_height
		local chapter_pbar_x, chapter_pbar_width = get_pbar_dimensions(dpy_w)
		for _, c in ipairs(clist) do
			if c.time >= 0 and c.time < duration then
				local x = chapter_pbar_x + (chapter_pbar_width * (c.time / duration))
				local scale = tw
				if (near_chapter and math.abs(chapter_time - c.time) < 0.1) then
					scale = math.floor(scale * opt.chapter_marker_scale + 0.5)
				end
				local marker_y = y -- Special positioning for start chapter (time = 0)
				if c.time == 0 then
					marker_y = y + (pb_h / 2)  -- Center the marker vertically for start
				end
				if c.time > 0 then -- Only draw marker if not at start (to keep it invisible)
					local marker_color = opt.chapter_marker_color
					if c.title and string.sub(c.title, 1, 4) == "cut_" then
						marker_color = opt.chapter_cut_marker_color
					end

					draw_rect_point(
						x - scale,  marker_y,
						x,          marker_y - scale,
						x + scale,  marker_y,
						x,          marker_y + scale,
						marker_color,
						{ bw = bw, bcolor = opt.chapter_marker_border_color }
					)
				end
			end
		end
	end

	-- L5: current/remaining time
	local time_pos = mp.get_property_native("time-pos") or 0
	local time = format_time(time_pos)
	draw_text(opt.font_pad_x, timeline_y, fs, "{\\an1}" .. time, fopt)
	local remaining = mp.get_property_native(opt.timeline_rhs) or 0
	local rem = "-" .. format_time(remaining)
	draw_text(dpy_w - opt.font_pad_x, timeline_y, fs, "{\\an3}" .. rem, fopt)

	-- filename bar at top
	local filename = mp.get_property("filename", "")
	if filename ~= "" then
		draw_rect(0, opt.font_pad_y, dpy_w, pb_h, opt.pbar_bg_color)
		draw_text(math.floor(dpy_w / 2), opt.font_pad_y + math.floor(pb_h / 2), fs, "{\\an5}" .. esc_ass(filename), fopt)
	end

	-- L6: hovered timeline
	if state.mouse and state.mouse.hover and (mouse_on_progress_bar(state.mouse) or near_chapter) then
		local hover_sec
		if near_chapter then
			hover_sec = chapter_time
		else
			hover_sec = hover_to_sec(state.mouse.x, dpy_w, duration)
		end
		local hover_text = format_time(hover_sec)
		local hover_pbar_x, hover_pbar_width = get_pbar_dimensions(dpy_w)
		local snapped_x = hover_pbar_x + (hover_pbar_width * (hover_sec / duration))
		local hover_thickness = opt.hover_bar_thickness
		draw_rect(
			math.max(snapped_x - (hover_thickness / 2), hover_pbar_x), dpy_h - ypos - opt.floating_height,
			hover_thickness, ypos, opt.hover_bar_color
		)
		local x = math.min(math.max(snapped_x, hover_pbar_x), hover_pbar_x + hover_pbar_width)
		draw_text(
			x, dpy_h - (ypos + fs + 2) - opt.floating_height, fs,
			"{\\an8}" .. hover_text, fopt
		)
		ypos = ypos + fs + (fopt.bw * 2)

		-- preview thumbnail
		if not state.thumbfast.disabled then
			local pw = opt.preview_border_width
			local hpad = 4 + pw
			local tw = state.thumbfast.width
			local th = state.thumbfast.height
			local y = dpy_h - (ypos + th + pw) - opt.floating_height
			local thumb_pbar_x, thumb_pbar_width = get_pbar_dimensions(dpy_w)
			local snapped_x = thumb_pbar_x + (thumb_pbar_width * (hover_sec / duration))
			local x = snapped_x - (tw / 2)
			x = math.min(math.max(x, hpad), dpy_w - (hpad + tw))

			-- Show chapter name if snapped to a chapter
			local chapter_name_height = 0
			if near_chapter then
				local chapter_name = nil
				for _, c in ipairs(state.chapters) do
					if (chapter_time >= c.time) then
						chapter_name = c.title
					end
				end
				if chapter_name then
					chapter_name_height = fs + (fopt.bw * 2) + 1
					local name_y = y - chapter_name_height
					draw_text(
						x + (tw / 2), name_y, fs,
						"{\\an8}" .. chapter_name, fopt
					)
				end
			end

			mp.commandv(
				"script-message-to", "thumbfast", "thumb",
				hover_sec, x, y
			)
			ypos = ypos + th + pw + chapter_name_height

			-- preview border
			if pw > 0 then
				local c = opt.preview_border_color
				draw_rect(
					x, y, tw, th, "1616167F",
					{ bw = pw, bcolor = c }
				)
				ypos = ypos + pw
			end
		end
	else
		-- Clear thumbnail when mouse is not on progress bar or near chapter
		if (state.thumbfast.available) then
			mp.commandv("script-message-to", "thumbfast", "clear")
		end
	end
	render()
end

local function pbar_pressed()
local near_chapter, chapter_time = mouse_near_chapter(state.mouse, state.duration)
	local seek_time
	if near_chapter then
		seek_time = chapter_time
	else
		seek_time = hover_to_sec(
			state.mouse.x, state.dpy_w, state.duration
		)
	end
	mp.set_property("time-pos", seek_time)
end


local function set_dpy_size(kind, osd)
	state.dpy_w     = osd.w
	state.osd.res_x = osd.w
	state.dpy_h     = osd.h
	state.osd.res_y = osd.h

	-- ensure we don't obstruct the console (excluding the preview and hovered timeline)
	local b = (opt.font_size + (opt.font_border_width * 2) + 8) / state.dpy_h -- +8 padding
	b = b + (opt.pbar_height / state.dpy_h)
	b = b + (opt.floating_height / state.dpy_h) -- Add floating height to margin calculation
	mp.set_property_native("user-data/osc/margins", { l = 0, r = 0, t = 2*b, b = b })
end

local function set_duration(kind, d)
	state.duration = d
end

local function set_chapter_list(kind, c)
	local chapters = {} -- Always create a list with at least the start chapter
	local start_chapter_title = "Start"  -- Default title
	if (c and #c > 0 and c[1].time == 0) then -- Check if there's already a chapter at 00:00:00 (it would be first if it exists)
		start_chapter_title = c[1].title
	end
	table.insert(chapters, { time = 0, title = start_chapter_title }) -- Add 00:00:00 as the first chapter with appropriate title
	if (c and #c > 0) then -- Add existing chapters if any
		for _, chapter in ipairs(c) do
			if chapter.time > 0 then  -- Only add non-zero chapters
				table.insert(chapters, chapter)
			end
		end
	end
	state.chapters = chapters
	table.sort(state.chapters, function(a, b) return a.time < b.time end)
end

local function set_thumbfast(json)
	local data = utils.parse_json(json)
	if (type(data) ~= "table" or not data.width or not data.height) then
		msg.error("thumbfast-info: received json didn't produce a table with thumbnail information")
	else
		state.thumbfast = data
	end
end

local function update_state(st)
    if state.pbar ~= st then
        state.pbar = st
		if st == false then
			state.draw_buffer = {} -- Clear buffer
			state.osd.data = '' -- clear everything
			state.osd:update()
			state.mouse = nil
			if (state.thumbfast.available) then
				mp.commandv("script-message-to", "thumbfast", "clear")
			end
		else
			pbar_draw()
		end
    end
end

local function is_in_edge_area()
    local pos = mp.get_property_native("mouse-pos")
    local dims = mp.get_property_native("osd-dimensions")
    if pos and pos.hover and dims then
        local y = pos.y
        local height = dims.h
        return y > (1 - opt.screen_percentage/100) * height
    end
    return false
end

local function reset_timer()
    if state.timer then
        state.timer:kill()
    end
    state.timer = mp.add_timeout(opt.timeout, function()
        local paused = mp.get_property_native("pause")
        if opt.show_when_paused and paused and not state.user_hidden then
            update_state(true)
        else
            update_state(is_in_edge_area())
        end
    end)
end

local function init()
	mpopt.read_options(opt, "mfpbar")
	state.osd = mp.create_osd_overlay("ass-events")
	mp.observe_property("osd-dimensions", "native", set_dpy_size)
	mp.observe_property('duration', 'native', set_duration)

	mp.observe_property('chapter-list', 'native', function(kind, c)
		set_chapter_list(kind, c)
		if state.pbar == true then
			pbar_draw()
		end
	end)

	mp.register_script_message("thumbfast-info", set_thumbfast)

	mp.register_script_message("torrent-cache-ranges", function(json)
		local data = utils.parse_json(json)
		state.torrent_ranges = (type(data) == "table" and #data > 0) and data or nil
		if state.pbar == true then pbar_draw() end
	end)

	mp.register_event("file-loaded", function()
		state.torrent_ranges = nil
		local path = mp.get_property("path", "")
		state.is_local = not path:match("://")
	end)

	mp.register_event("mouse-leave", function() -- Handle mouse leaving window
		update_state(false)
		if state.timer then
			state.timer:kill()
		end
	end)

	mp.observe_property('demuxer-cache-state', 'native', function(kind, c)
		state.cache_state = c  -- Store the full cache state object
		if state.pbar == true and state.cache_state and state.cache_state["seekable-ranges"] and #state.cache_state["seekable-ranges"] > 0 then
			pbar_draw()
		end
	end)

	mp.observe_property("mouse-pos", "native", function(kind, mouse)
		state.mouse = mouse
		if mouse and mouse.hover then
			update_state(true)
			reset_timer()
		end
		if is_in_edge_area() then
			update_state(true)
			local near_chapter, chapter_time = mouse_near_chapter(state.mouse, state.duration)
			if (mouse_on_progress_bar(state.mouse) or near_chapter) then
				if (not state.press_bounded) then
					mp.add_forced_key_binding('mbtn_left', 'pbar_pressed', pbar_pressed)
					state.press_bounded = true
				end
			elseif (state.press_bounded) then
				mp.remove_key_binding('pbar_pressed')
				state.press_bounded = false
			end
		end
		if state.pbar == true then
			pbar_draw()
		end
	end)

	mp.observe_property("time-pos", "number", function(name, value)
		if value and state.last_time_pos then
			local diff = math.abs(value - state.last_time_pos)

			if diff > 0.1 then -- Threshold of 0.1 seconds to filter out normal playback
				update_state(true)
				reset_timer()
			end
		end
		state.last_time_pos = value
		if state.pbar == true then
			pbar_draw()
		end
	end)

	mp.add_key_binding("b", "mfpbar-toggle", function()
		state.user_hidden = not state.user_hidden
		if state.timer then state.timer:kill() end
		update_state(not state.user_hidden)
	end)

	mp.observe_property("pause", "bool", function(_, val)
		if val == true then
			if opt.show_when_paused and not state.user_hidden then
				if state.timer then state.timer:kill() end
				update_state(true)
			end
		elseif val == false then
			state.user_hidden = false
			reset_timer()
		end
	end)
end

init()
