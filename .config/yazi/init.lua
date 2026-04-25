require("custom-filter"):setup()
require("recycle-bin"):setup()
require("autosave"):setup({})
require("write-id"):setup()
require("sshfs"):setup()
require("full-border"):setup {
    -- Available values: ui.Border.PLAIN, ui.Border.ROUNDED
    type = ui.Border.ROUNDED,
}
th.git = th.git or {}





th.git.unknown_sign = " "
th.git.added_sign = "A"
th.git.untracked_sign = "U"
th.git.ignored_sign = "I"
th.git.updated_sign = ""
th.git.modified_sign = "M"
th.git.deleted_sign = "D"
th.git.clean_sign = "✔"
require("git"):setup {
    -- Order of status signs showing in the linemode
    order = 1600,
}
require("myfiles"):setup {
    order = 1500,
}

local tokyo_night_theme = require("yatline-tokyo-night"):setup("night") -- storm moon
local gruvbox_material_theme = require("yatline-gruvbox-material"):setup({ mode = "dark", toughness = "hard" })  -- "hard" | "soft" | "medium"
require("yatline"):setup({
    theme = gruvbox_material_theme,
   --section_separator = { open = "", close = "" },
   --part_separator = { open = "", close = "" },
   --inverse_separator = { open = "", close = "" },

   --style_a = {
   --    fg = "black",
   --    bg_mode = {
   --        normal = "white",
   --        select = "white",
   --        un_set = "white"
   --    }
   --},
   --style_b = { bg = "brightblack", fg = "brightwhite" },
   --style_c = { bg = "black", fg = "brightwhite" },

   --permissions_t_fg = "green",
   --permissions_r_fg = "yellow",
   --permissions_w_fg = "red",
   --permissions_x_fg = "cyan",
   --permissions_s_fg = "white",

    tab_width = 20,
    tab_use_inverse = false,

    selected = { icon = "󰻭", fg = "yellow" },
    copied = { icon = "", fg = "green" },
    cut = { icon = "", fg = "red" },

    total = { icon = "󰮍", fg = "yellow" },
    succ = { icon = "", fg = "green" },
    fail = { icon = "", fg = "red" },
    found = { icon = "󰮕", fg = "blue" },
    processed = { icon = "󰐍", fg = "green" },

    show_background = true,

    display_header_line = true,
    display_status_line = true,

    component_positions = { "header", "tab", "status" },

    header_line = {
        left = {
            section_a = {
                    {type = "line", custom = false, name = "tabs", params = {"left"}},
            },
            section_b = {
            },
            section_c = {
                {type = "string", custom = false, name = "filter_query", params = { "FILTER:" }},
                {type = "string", custom = false, name = "search_query", params = { "SEARCH:" }},
            }
        },
        right = {
            section_a = {
            },
            --section_b = {
            --        {type = "string", custom = false, name = "date", params = {" %d.%m.%y  %H:%M"}},
            --},
            section_c = {
                {type = "coloreds", custom = false, name = "disk-usage"},
            }
        }
    },

    status_line = {
        left = {
            section_a = {
                    {type = "string", custom = false, name = "cursor_position"},
            },
            section_b = {
                    {type = "coloreds", custom = false, name = "count"},
                    {type = "coloreds", custom = false, name = "selected-files-size"},
            },
            section_c = {
                    {type = "string", custom = false, name = "tab_path"},
            }
        },
        right = {
            section_a = {
                    {type = "string", custom = false, name = "hovered_size"},
            },
            section_b = {
                    {type = "coloreds", custom = false, name = "crtime"},
                    {type = "coloreds", custom = false, name = "modtime"},
            },
            section_c = {
                    {type = "string", custom = false, name = "hovered_mime"},
            }
        }
    },
})
require("yatline-disk-usage"):setup()
require("yatline-modtime"):setup()
require("yatline-crtime"):setup()
require("yatline-selected-size"):setup()

-- Override tab_path to show only directory path (without filter)
function Yatline.string.get:tab_path()
    local cwd = tostring(cx.active.current.cwd)
    -- Replace home directory with ~
    local home = os.getenv("HOME")
    if home then
        if cwd == home then
            return "~"
        elseif cwd:sub(1, #home) == home then
            return "~" .. cwd:sub(#home + 1)
        end
    end
    return cwd
end

-- Override count component to always show 3 separate icons
function Yatline.coloreds.get:count(filter)
    local num_selected = #cx.active.selected
    local num_yanked = #cx.yanked

    local num_copied = 0
    local num_cut = 0

    if num_yanked > 0 then
        if cx.yanked.is_cut then
            num_cut = num_yanked
        else
            num_copied = num_yanked
        end
    end

    return {
        { string.format(" 󰻭 %d ", num_selected), "yellow" },
        { string.format("  %d ", num_copied), "green" },
        { string.format("  %d ", num_cut), "red" },
    }
end

-- Custom mouse click behavior
function Entity:click(event, up)
    if up then
        return  -- Ignore mouse release
    end

    if event.is_left then
        -- Left click: navigate to file then select it
        ya.emit("reveal", { self._file.url })
        ya.emit("toggle", { state = true })
    elseif event.is_middle then
        -- Middle click: dragon-drop selected files (or hovered if none selected)
        ya.emit("shell", { "dragon-drop -a -x -i -T %s" })
    end
end
