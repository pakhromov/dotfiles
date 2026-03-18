local msg = require('mp.msg')
local mpopt = require('mp.options')

-- Configuration options
local opt = {
    icon_size = 100,              -- Base size of the icon (radius of the circle)
    corner_radius = 8,            -- Radius for rounded corners on pause bars
    icon_alpha_start = 100,       -- Starting icon transparency (0-255, 0 = fully opaque)
    icon_alpha_end = 50,          -- Maximum icon transparency at animation end (0-255, 0 = fully opaque)
    animation_duration = 0.35,    -- Animation duration in seconds
    scale_factor = 1.5,           -- Maximum scale factor during animation
    color = "000000",             -- Icon color (hex without #)
    outline_thickness = 2,        -- Outline thickness (0 = no outline)
    outline_color = "FFFFFF",     -- Outline color (hex without #)
    outline_alpha_start = 100,     -- Starting outline transparency (0-255, 0 = fully opaque)
    outline_alpha_end = 50        -- Maximum outline transparency at animation end (0-255, 0 = fully opaque)
}

local state = {
    draw_buffer = {},
    animation_timer = nil,
    start_time = nil
}

-- Read configuration from script-opts
mpopt.read_options(opt, "pause")

local function draw_color(color, section)
    local bgr = string.sub(color, 1, 6)
    local opacity = string.len(color) > 6 and string.sub(color, 7, 8) or "00"
    local ret = '{\\' .. section .. 'c&H' .. bgr .. '&}'
    ret = ret .. '{\\' .. section .. 'a&H' .. opacity .. '&}'
    return ret
end

local function draw_rounded_rect(x, y, w, h, color, radius, outline_color, opt_param)
    opt_param = opt_param or {}
    
    if radius <= 0 or w <= radius * 2 or h <= radius * 2 then
        -- Fall back to regular rectangle if radius is too large or zero
        local s = '{\\pos(0, 0)\\an7}'
        s = s .. draw_color(color, "1")
        s = s .. draw_color(outline_color or "00000000", "3")
        s = s .. '{\\bord' .. (opt_param.bw or '0') .. '}'
        s = s .. string.format('{\\p1}m %d %d l %d %d %d %d %d %d{\\p0}', 
                              x, y, x + w, y, x + w, y + h, x, y + h)
        table.insert(state.draw_buffer, s)
        return
    end
    
    local s = '{\\pos(0, 0)\\an7}'
    s = s .. draw_color(color, "1")
    s = s .. draw_color(outline_color or "00000000", "3")
    s = s .. '{\\bord' .. (opt_param.bw or '0') .. '}'
    
    local path = '{\\p1}'
    -- Start from top-left, going clockwise with rounded corners
    path = path .. string.format('m %d %d', x, y + radius)
    -- Top-left rounded corner
    path = path .. string.format(' b %d %d %d %d %d %d', x, y, x + radius, y, x + radius, y)
    -- Top edge
    path = path .. string.format(' l %d %d', x + w - radius, y)
    -- Top-right rounded corner
    path = path .. string.format(' b %d %d %d %d %d %d', x + w, y, x + w, y + radius, x + w, y + radius)
    -- Right edge
    path = path .. string.format(' l %d %d', x + w, y + h - radius)
    -- Bottom-right rounded corner
    path = path .. string.format(' b %d %d %d %d %d %d', x + w, y + h, x + w - radius, y + h, x + w - radius, y + h)
    -- Bottom edge
    path = path .. string.format(' l %d %d', x + radius, y + h)
    -- Bottom-left rounded corner
    path = path .. string.format(' b %d %d %d %d %d %d', x, y + h, x, y + h - radius, x, y + h - radius)
    path = path .. '{\\p0}'
    
    s = s .. path
    table.insert(state.draw_buffer, s)
end

local function draw_triangle_with_right_corner_rounded(x1, y1, x2, y2, x3, y3, color, radius, outline_color, opt_param)
    opt_param = opt_param or {}
    local s = '{\\pos(0, 0)\\an7}'
    s = s .. draw_color(color, "1")
    s = s .. draw_color(outline_color or "00000000", "3")
    s = s .. '{\\bord' .. (opt_param.bw or '0') .. '}'
    
    -- If radius is 0, draw regular triangle
    if radius <= 0 then
        s = s .. string.format('{\\p1}m %d %d l %d %d %d %d{\\p0}', x1, y1, x3, y3, x2, y2)
        table.insert(state.draw_buffer, s)
        return
    end
    
    -- Calculate edge lengths
    local edge1_len = math.sqrt((x3-x1)^2 + (y3-y1)^2)  -- top-left to right
    local edge2_len = math.sqrt((x2-x3)^2 + (y2-y3)^2)  -- right to bottom-left
    local edge3_len = math.sqrt((x1-x2)^2 + (y1-y2)^2)  -- bottom-left to top-left
    
    -- Limit radius to prevent overlap
    local max_radius = math.min(edge1_len, edge2_len, edge3_len) / 6
    local effective_radius = math.min(radius, max_radius)
    
    -- Calculate unit vectors for all edges
    -- Edge from top-left to right
    local e1_ux = (x3 - x1) / edge1_len
    local e1_uy = (y3 - y1) / edge1_len
    
    -- Edge from right to bottom-left
    local e2_ux = (x2 - x3) / edge2_len
    local e2_uy = (y2 - y3) / edge2_len
    
    -- Edge from bottom-left to top-left
    local e3_ux = (x1 - x2) / edge3_len
    local e3_uy = (y1 - y2) / edge3_len
    
    -- Calculate points for upper corner (x1, y1) rounding
    local upper_start_x = x1 - e3_ux * effective_radius  -- coming from bottom-left
    local upper_start_y = y1 - e3_uy * effective_radius
    local upper_end_x = x1 + e1_ux * effective_radius    -- going to right
    local upper_end_y = y1 + e1_uy * effective_radius
    
    -- Calculate points for right corner (x3, y3) rounding - use larger radius for visual consistency
    local right_effective_radius = effective_radius * 1.3  -- Make right corner more prominent
    local right_start_x = x3 - e1_ux * right_effective_radius  -- coming from top-left
    local right_start_y = y3 - e1_uy * right_effective_radius
    local right_end_x = x3 + e2_ux * right_effective_radius    -- going to bottom-left
    local right_end_y = y3 + e2_uy * right_effective_radius
    
    -- Calculate points for lower corner (x2, y2) rounding
    local lower_start_x = x2 - e2_ux * effective_radius  -- coming from right
    local lower_start_y = y2 - e2_uy * effective_radius
    local lower_end_x = x2 + e3_ux * effective_radius    -- going to top-left
    local lower_end_y = y2 + e3_uy * effective_radius
    
    -- Create the path
    local path = '{\\p1}'
    
    -- Start from the point before the upper rounded corner
    path = path .. string.format('m %d %d', math.floor(upper_start_x), math.floor(upper_start_y))
    
    -- Upper rounded corner (x1, y1)
    local upper_ctrl1_x = upper_start_x + (x1 - upper_start_x) * 0.552
    local upper_ctrl1_y = upper_start_y + (y1 - upper_start_y) * 0.552
    local upper_ctrl2_x = upper_end_x + (x1 - upper_end_x) * 0.552
    local upper_ctrl2_y = upper_end_y + (y1 - upper_end_y) * 0.552
    
    path = path .. string.format(' b %d %d %d %d %d %d', 
                                math.floor(upper_ctrl1_x), math.floor(upper_ctrl1_y),
                                math.floor(upper_ctrl2_x), math.floor(upper_ctrl2_y),
                                math.floor(upper_end_x), math.floor(upper_end_y))
    
    -- Line to the start of the right rounded corner
    path = path .. string.format(' l %d %d', math.floor(right_start_x), math.floor(right_start_y))
    
    -- Right rounded corner (x3, y3) - using larger radius
    local right_ctrl1_x = right_start_x + (x3 - right_start_x) * 0.552
    local right_ctrl1_y = right_start_y + (y3 - right_start_y) * 0.552
    local right_ctrl2_x = right_end_x + (x3 - right_end_x) * 0.552  
    local right_ctrl2_y = right_end_y + (y3 - right_end_y) * 0.552
    
    path = path .. string.format(' b %d %d %d %d %d %d', 
                                math.floor(right_ctrl1_x), math.floor(right_ctrl1_y),
                                math.floor(right_ctrl2_x), math.floor(right_ctrl2_y),
                                math.floor(right_end_x), math.floor(right_end_y))
    
    -- Line to the start of the lower rounded corner
    path = path .. string.format(' l %d %d', math.floor(lower_start_x), math.floor(lower_start_y))
    
    -- Lower rounded corner (x2, y2)
    local lower_ctrl1_x = lower_start_x + (x2 - lower_start_x) * 0.552
    local lower_ctrl1_y = lower_start_y + (y2 - lower_start_y) * 0.552
    local lower_ctrl2_x = lower_end_x + (x2 - lower_end_x) * 0.552
    local lower_ctrl2_y = lower_end_y + (y2 - lower_end_y) * 0.552
    
    path = path .. string.format(' b %d %d %d %d %d %d', 
                                math.floor(lower_ctrl1_x), math.floor(lower_ctrl1_y),
                                math.floor(lower_ctrl2_x), math.floor(lower_ctrl2_y),
                                math.floor(lower_end_x), math.floor(lower_end_y))
    
    -- Close the triangle back to start
    path = path .. ' z'
    
    path = path .. '{\\p0}'
    s = s .. path
    table.insert(state.draw_buffer, s)
end

local function create_pause_indicator(paused, scale, icon_alpha, outline_alpha)
    -- Get screen dimensions
    local w, h = mp.get_osd_size()
    local center_x, center_y = 0.5 * w, 0.5 * h
    
    -- Clear the draw buffer
    state.draw_buffer = {}
    
    -- Calculate scaled dimensions
    local scaled_size = opt.icon_size * (scale / 100)
    local icon_alpha_hex = string.format("%02X", icon_alpha)
    
    -- Prepare outline color with separate alpha
    local outline_color_with_alpha = nil
    if opt.outline_thickness > 0 then
        local outline_alpha_hex = string.format("%02X", outline_alpha)
        outline_color_with_alpha = opt.outline_color .. outline_alpha_hex
    end
    
    
    if paused then
        -- Draw pause icon (two rounded rectangles)
        local bar_width = scaled_size * 0.25
        local bar_height = scaled_size * 0.9
        local bar_spacing = scaled_size * 0.15
        
        local left_x = center_x - bar_spacing - bar_width
        local right_x = center_x + bar_spacing
        local bar_y = center_y - bar_height / 2
        
        -- Left pause bar
        draw_rounded_rect(left_x, bar_y, bar_width, bar_height, 
                         opt.color .. icon_alpha_hex, opt.corner_radius, outline_color_with_alpha,
                         { bw = opt.outline_thickness })
        
        -- Right pause bar
        draw_rounded_rect(right_x, bar_y, bar_width, bar_height, 
                         opt.color .. icon_alpha_hex, opt.corner_radius, outline_color_with_alpha,
                         { bw = opt.outline_thickness })
    else
        -- Draw play icon (triangle with all corners rounded)
        local triangle_size = scaled_size
        local triangle_offset = scaled_size * 0.1 -- Slight offset to center visually
        
        local x1 = center_x - triangle_size/2 + triangle_offset  -- Top-left
        local y1 = center_y - triangle_size/2
        local x2 = center_x - triangle_size/2 + triangle_offset  -- Bottom-left
        local y2 = center_y + triangle_size/2
        local x3 = center_x + triangle_size/2 + triangle_offset  -- Right
        local y3 = center_y
        
        draw_triangle_with_right_corner_rounded(x1, y1, x2, y2, x3, y3, opt.color .. icon_alpha_hex, opt.corner_radius, outline_color_with_alpha,
                                               { bw = opt.outline_thickness })
    end
    
    -- Return the concatenated result
    return table.concat(state.draw_buffer, '\n')
end

local function render(indicator_text)
    local w, h = mp.get_osd_size()
    mp.set_osd_ass(w, h, indicator_text)
end

local function animate_indicator(paused)
    -- Clear existing timer
    if state.animation_timer then
        state.animation_timer:kill()
    end
    
    state.start_time = mp.get_time()
    
    local function update_frame()
        local elapsed = mp.get_time() - state.start_time
        local progress = math.min(elapsed / opt.animation_duration, 1)
        
        -- Animation logic: scale up and animate opacity from start to end
        local scale_range = (opt.scale_factor - 1) * 100 -- Convert to percentage increase
        local scale = progress * scale_range + 100  -- Scale from 100% to scale_factor
        
        -- Animate opacity from icon_alpha_start to icon_alpha_end using quadratic easing
        local alpha_progress = 1 - (progress * progress) -- Quadratic fade (starts fast, slows down)
        
        -- Calculate icon alpha
        local icon_alpha_range = opt.icon_alpha_start - opt.icon_alpha_end
        local icon_alpha = opt.icon_alpha_end + (icon_alpha_range * alpha_progress)
        
        -- Calculate outline alpha
        local outline_alpha_range = opt.outline_alpha_start - opt.outline_alpha_end
        local outline_alpha = opt.outline_alpha_end + (outline_alpha_range * alpha_progress)
        
        -- Create and display the indicator
        local indicator = create_pause_indicator(paused, scale, math.floor(icon_alpha), math.floor(outline_alpha))
        render(indicator)
        
        if progress < 1 then
            state.animation_timer = mp.add_timeout(1/60, update_frame)  -- ~60fps
        else
            render("") -- Clear display when animation completes
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

-- Watch for pause state changes
mp.observe_property("pause", "bool", on_pause_change)