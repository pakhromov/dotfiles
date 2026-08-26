ps.sub("ind-app-title", function(args)
	args.value = "yazi"
	return args
end)

require("custom-filter"):setup()
require("autosave"):setup({})
require("write-id"):setup()
require("sshfs"):setup()
--require("full-border"):setup {
--    -- Available values: ui.Border.PLAIN, ui.Border.ROUNDED
--    type = ui.Border.ROUNDED,
--}


-- ── git-remote.yazi ─────────────────────────────────────────────────────────
-- git.yazi's local status, plus upstream awareness.
--   `git fetch`  runs exactly once per repo per yazi session, never again.
--   `git diff HEAD...@{upstream}` runs every batch and is local, so pulling
--   clears the update markers without any further network access.
--
-- Every value below is the plugin's own default, spelled out so it can be
-- changed in place. Must come before the setup() call.
th.git_remote = th.git_remote or {}

-- Signs. "" hides that state entirely.
th.git_remote.updated_local_sign = "⇅" -- upstream has changes AND so do you
th.git_remote.updated_sign       = "↓" -- upstream has changes
th.git_remote.untracked_sign     = "?" -- not tracked, not ignored
th.git_remote.unstaged_sign      = "M" -- edited in the work tree
th.git_remote.staged_sign        = "M" -- edited and staged
th.git_remote.added_sign         = "A" -- new file, staged
th.git_remote.deleted_sign       = "D" -- deleted
th.git_remote.conflict_sign      = "!" -- unmerged (git.yazi called this `updated`)
th.git_remote.ignored_sign       = "I" -- matched by .gitignore
th.git_remote.clean_sign         = "•" -- tracked file with no changes, or a clean up-to-date repo folder
th.git_remote.unknown_sign       = ""  -- outside any repo

-- Colours. staged and unstaged share "M" and are told apart by these.
th.git_remote.updated_local = ui.Style():fg("magenta")
th.git_remote.updated       = ui.Style():fg("cyan")
th.git_remote.untracked     = ui.Style():fg("magenta")
th.git_remote.unstaged      = ui.Style():fg("yellow")
th.git_remote.staged        = ui.Style():fg("green")
th.git_remote.added         = ui.Style():fg("green")
th.git_remote.deleted       = ui.Style():fg("red")
th.git_remote.conflict      = ui.Style():fg("red")
th.git_remote.ignored       = ui.Style():fg("darkgray")
th.git_remote.clean         = ui.Style():fg("green")
th.git_remote.unknown       = ui.Style()

-- A directory shows the worst status beneath it, ranked:
--   updated_local > updated > ignored > untracked > unstaged > staged
--   > added > deleted > conflict > clean
-- Linemode children are laid out left to right by ascending order
-- (yazi's own `solo` is 1000 and `padding` is 2000). Each plugin holds one
-- fixed-width column, so this number is which column it gets.
require("git-remote"):setup {
    order = 1600, -- rightmost column
}

-- ── dotfiles.yazi ───────────────────────────────────────────────────────────
-- Status for the bare dotfiles repo:
--     git --git-dir=~/.dotfiles-git --work-tree=$HOME
-- Local only, the remote is never contacted.
--
-- Every value below is the plugin's own default, spelled out so it can be
-- changed in place. `th.dotfiles` must be populated before setup() runs,
-- since setup() reads it once to build the sign table.
th.dotfiles = th.dotfiles or {}

-- Signs: the character drawn in the linemode. "" hides that state entirely.
th.dotfiles.clean_sign    = "✔" -- tracked, no changes
th.dotfiles.unstaged_sign = "M" -- edited in the work tree
th.dotfiles.staged_sign   = "M" -- edited and staged
th.dotfiles.added_sign    = "A" -- new file, staged
th.dotfiles.deleted_sign  = "D" -- deleted
th.dotfiles.conflict_sign = "!" -- unmerged / conflicted
th.dotfiles.unknown_sign  = ""  -- not tracked by the dotfiles repo

-- Colours. staged and unstaged share the "M" sign and are told apart by these.
th.dotfiles.clean    = ui.Style():fg("darkgray")
th.dotfiles.unstaged = ui.Style():fg("yellow")
th.dotfiles.staged   = ui.Style():fg("green")
th.dotfiles.added    = ui.Style():fg("green")
th.dotfiles.deleted  = ui.Style():fg("red")
th.dotfiles.conflict = ui.Style():fg("red")
th.dotfiles.unknown  = ui.Style()

-- A directory shows the worst status beneath it, ranked:
--     conflict > unstaged > staged > added > deleted > clean
require("dotfiles"):setup {
    git_dir = os.getenv("HOME") .. "/.dotfiles-git", -- bare repo location
    order   = 1700,                                  -- column left of git-remote
    ttl_ms  = 250,                                   -- refresh debounce, ms
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
