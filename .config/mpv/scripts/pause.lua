local mpopt = require('mp.options')

local opt = {
    icon_size = 100,
    corner_radius = 12,
    icon_alpha_start = 100,
    icon_alpha_end = 50,
    animation_duration = 0.35,
    scale_factor = 1.5,
    color = "#000000",
    outline_thickness = 3,
    outline_color = "#FFFFFF",
    outline_alpha_start = 100,
    outline_alpha_end = 50
}

local state = {
    draw_buffer = {}
}

mpopt.read_options(opt, "pause")
opt.color = opt.color:gsub("^#", "")
opt.outline_color = opt.outline_color:gsub("^#", "")

local function draw_color(color, section)
    local r, g, b = color:sub(1,2), color:sub(3,4), color:sub(5,6)
    local opacity = color:sub(7, 8)
    return '{\\' .. section .. 'c&H' .. b..g..r .. '&}{\\' .. section .. 'a&H' .. opacity .. '&}'
end

local function draw_rounded_rect(x, y, w, h, color, radius, outline_color, bw)
    local s = '{\\pos(0, 0)\\an7}'
    s = s .. draw_color(color, "1")
    s = s .. draw_color(outline_color or "00000000", "3")
    s = s .. '{\\bord' .. bw .. '}'

    local path = '{\\p1}'
    path = path .. string.format('m %d %d', x, y + radius)
    path = path .. string.format(' b %d %d %d %d %d %d', x, y, x + radius, y, x + radius, y)
    path = path .. string.format(' l %d %d', x + w - radius, y)
    path = path .. string.format(' b %d %d %d %d %d %d', x + w, y, x + w, y + radius, x + w, y + radius)
    path = path .. string.format(' l %d %d', x + w, y + h - radius)
    path = path .. string.format(' b %d %d %d %d %d %d', x + w, y + h, x + w - radius, y + h, x + w - radius, y + h)
    path = path .. string.format(' l %d %d', x + radius, y + h)
    path = path .. string.format(' b %d %d %d %d %d %d', x, y + h, x, y + h - radius, x, y + h - radius)
    path = path .. '{\\p0}'

    table.insert(state.draw_buffer, s .. path)
end

local function draw_triangle_rounded(x1, y1, x2, y2, x3, y3, color, radius, outline_color, bw)
    local s = '{\\pos(0, 0)\\an7}'
    s = s .. draw_color(color, "1")
    s = s .. draw_color(outline_color or "00000000", "3")
    s = s .. '{\\bord' .. bw .. '}'

    local edge1_len = math.sqrt((x3-x1)^2 + (y3-y1)^2)
    local edge2_len = math.sqrt((x2-x3)^2 + (y2-y3)^2)
    local edge3_len = math.sqrt((x1-x2)^2 + (y1-y2)^2)

    local e1_ux = (x3 - x1) / edge1_len
    local e1_uy = (y3 - y1) / edge1_len
    local e2_ux = (x2 - x3) / edge2_len
    local e2_uy = (y2 - y3) / edge2_len
    local e3_ux = (x1 - x2) / edge3_len
    local e3_uy = (y1 - y2) / edge3_len

    local upper_start_x = x1 - e3_ux * radius
    local upper_start_y = y1 - e3_uy * radius
    local upper_end_x = x1 + e1_ux * radius
    local upper_end_y = y1 + e1_uy * radius

    local right_radius = radius * 1.3
    local right_start_x = x3 - e1_ux * right_radius
    local right_start_y = y3 - e1_uy * right_radius
    local right_end_x = x3 + e2_ux * right_radius
    local right_end_y = y3 + e2_uy * right_radius

    local lower_start_x = x2 - e2_ux * radius
    local lower_start_y = y2 - e2_uy * radius
    local lower_end_x = x2 + e3_ux * radius
    local lower_end_y = y2 + e3_uy * radius

    local path = '{\\p1}'
    path = path .. string.format('m %d %d', math.floor(upper_start_x), math.floor(upper_start_y))

    local upper_ctrl1_x = upper_start_x + (x1 - upper_start_x) * 0.552
    local upper_ctrl1_y = upper_start_y + (y1 - upper_start_y) * 0.552
    local upper_ctrl2_x = upper_end_x + (x1 - upper_end_x) * 0.552
    local upper_ctrl2_y = upper_end_y + (y1 - upper_end_y) * 0.552
    path = path .. string.format(' b %d %d %d %d %d %d',
        math.floor(upper_ctrl1_x), math.floor(upper_ctrl1_y),
        math.floor(upper_ctrl2_x), math.floor(upper_ctrl2_y),
        math.floor(upper_end_x), math.floor(upper_end_y))

    path = path .. string.format(' l %d %d', math.floor(right_start_x), math.floor(right_start_y))

    local right_ctrl1_x = right_start_x + (x3 - right_start_x) * 0.552
    local right_ctrl1_y = right_start_y + (y3 - right_start_y) * 0.552
    local right_ctrl2_x = right_end_x + (x3 - right_end_x) * 0.552
    local right_ctrl2_y = right_end_y + (y3 - right_end_y) * 0.552
    path = path .. string.format(' b %d %d %d %d %d %d',
        math.floor(right_ctrl1_x), math.floor(right_ctrl1_y),
        math.floor(right_ctrl2_x), math.floor(right_ctrl2_y),
        math.floor(right_end_x), math.floor(right_end_y))

    path = path .. string.format(' l %d %d', math.floor(lower_start_x), math.floor(lower_start_y))

    local lower_ctrl1_x = lower_start_x + (x2 - lower_start_x) * 0.552
    local lower_ctrl1_y = lower_start_y + (y2 - lower_start_y) * 0.552
    local lower_ctrl2_x = lower_end_x + (x2 - lower_end_x) * 0.552
    local lower_ctrl2_y = lower_end_y + (y2 - lower_end_y) * 0.552
    path = path .. string.format(' b %d %d %d %d %d %d',
        math.floor(lower_ctrl1_x), math.floor(lower_ctrl1_y),
        math.floor(lower_ctrl2_x), math.floor(lower_ctrl2_y),
        math.floor(lower_end_x), math.floor(lower_end_y))

    path = path .. ' z{\\p0}'
    table.insert(state.draw_buffer, s .. path)
end

local function create_pause_indicator(paused, scale, icon_alpha, outline_alpha)
    local w, h = mp.get_osd_size()
    local center_x, center_y = 0.5 * w, 0.5 * h

    state.draw_buffer = {}

    local scaled_size = opt.icon_size * (scale / 100)
    local icon_alpha_hex = string.format("%02X", icon_alpha)

    local outline_color_with_alpha = nil
    if opt.outline_thickness > 0 then
        outline_color_with_alpha = opt.outline_color .. string.format("%02X", outline_alpha)
    end

    if paused then
        local bar_width = scaled_size * 0.25
        local bar_height = scaled_size * 0.9
        local bar_spacing = scaled_size * 0.15

        local left_x = center_x - bar_spacing - bar_width
        local right_x = center_x + bar_spacing
        local bar_y = center_y - bar_height / 2

        draw_rounded_rect(left_x, bar_y, bar_width, bar_height,
            opt.color .. icon_alpha_hex, opt.corner_radius, outline_color_with_alpha, opt.outline_thickness)
        draw_rounded_rect(right_x, bar_y, bar_width, bar_height,
            opt.color .. icon_alpha_hex, opt.corner_radius, outline_color_with_alpha, opt.outline_thickness)
    else
        local offset = scaled_size * 0.1

        local x1 = center_x - scaled_size/2 + offset
        local y1 = center_y - scaled_size/2
        local x2 = center_x - scaled_size/2 + offset
        local y2 = center_y + scaled_size/2
        local x3 = center_x + scaled_size/2 + offset
        local y3 = center_y

        draw_triangle_rounded(x1, y1, x2, y2, x3, y3,
            opt.color .. icon_alpha_hex, opt.corner_radius, outline_color_with_alpha, opt.outline_thickness)
    end

    return table.concat(state.draw_buffer, '\n')
end

local function render(indicator_text)
    local w, h = mp.get_osd_size()
    mp.set_osd_ass(w, h, indicator_text)
end

local function animate_indicator(paused)
    if state.animation_timer then
        state.animation_timer:kill()
    end

    state.start_time = mp.get_time()

    local function update_frame()
        local elapsed = mp.get_time() - state.start_time
        local progress = math.min(elapsed / opt.animation_duration, 1)

        local scale = progress * (opt.scale_factor - 1) * 100 + 100
        local alpha_progress = 1 - (progress * progress)

        local icon_alpha = opt.icon_alpha_end + (opt.icon_alpha_start - opt.icon_alpha_end) * alpha_progress
        local outline_alpha = opt.outline_alpha_end + (opt.outline_alpha_start - opt.outline_alpha_end) * alpha_progress

        render(create_pause_indicator(paused, scale, math.floor(icon_alpha), math.floor(outline_alpha)))

        if progress < 1 then
            state.animation_timer = mp.add_timeout(1/60, update_frame)
        else
            render("")
        end
    end

    update_frame()
end

local function on_pause_change(name, paused)
    if paused == nil then return end
    if paused == false then
        state.unpause_time = mp.get_time()
        if state.unpause_timer then state.unpause_timer:kill() end
        state.unpause_timer = mp.add_timeout(0.1, function()
            state.unpause_timer = nil
            if not mp.get_property_bool("pause") then
                animate_indicator(false)
            end
        end)
    else
        if state.unpause_timer then
            state.unpause_timer:kill()
            state.unpause_timer = nil
        end
        local is_framestep = state.unpause_time and (mp.get_time() - state.unpause_time) < 0.1
        if not is_framestep then
            animate_indicator(true)
        end
    end
end

mp.observe_property("pause", "bool", on_pause_change)
