from kitty.tab_bar import as_rgb
from kitty.utils import color_as_int
from kitty.rgb import to_color
import os

TAB_ACTIVE_INDEX_FG = "#16161e"
TAB_ACTIVE_FG = "#a0a0a0"
TAB_INACTIVE_INDEX_FG = "#16161e"
TAB_INACTIVE_FG = "#a0a0a0"

TAB_ACTIVE_INDEX_BG = "#d77757"
TAB_ACTIVE_BG = "#242424"
TAB_INACTIVE_INDEX_BG = "#5e7175"
TAB_INACTIVE_BG = "#242424"

TAB_ACTIVE_BOLD = False
TAB_ACTIVE_ITALIC = False
TAB_INACTIVE_BOLD = False
TAB_INACTIVE_ITALIC = False


LEFT_CORNER = "◖"
RIGHT_CORNER = "◗"
TAB_INDEX_SEPARATOR = " "

DEFAULT_ICON = " "

TITLE_ICONS = {
    "yazi": " ",
    "btm": "󰨇 ",
    "torrserver": " ",
    "pacseek": " ",
    "pacsea": " ",
    "impala": " ",
    "yay": " ",
    "codex": "󱚠 ",
}

MAX_TITLE_LENGTH = 10



def transform_title(tab):
    title = tab.title
    if title == '~':
        title = os.path.basename(os.path.expanduser('~'))
    if '/' in title or title.startswith('...'):
        last_part = os.path.basename(title.rstrip('/'))
        title = last_part if last_part else title
    if MAX_TITLE_LENGTH is not None and len(title) > MAX_TITLE_LENGTH:
        title = title[:MAX_TITLE_LENGTH - 1] + '…'
    return title


def draw_tab(draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data):
    title = transform_title(tab)
    default_bg = as_rgb(int(draw_data.default_bg))

    if tab.is_active:
        tab_fg   = as_rgb(color_as_int(to_color(TAB_ACTIVE_FG)))
        tab_bg   = as_rgb(color_as_int(to_color(TAB_ACTIVE_BG)))
        index_fg = as_rgb(color_as_int(to_color(TAB_ACTIVE_INDEX_FG)))
        index_bg = as_rgb(color_as_int(to_color(TAB_ACTIVE_INDEX_BG)))
        screen.cursor.bold = TAB_ACTIVE_BOLD
        screen.cursor.italic = TAB_ACTIVE_ITALIC
    else:
        tab_fg   = as_rgb(color_as_int(to_color(TAB_INACTIVE_FG)))
        tab_bg   = as_rgb(color_as_int(to_color(TAB_INACTIVE_BG)))
        index_fg = as_rgb(color_as_int(to_color(TAB_INACTIVE_INDEX_FG)))
        index_bg = as_rgb(color_as_int(to_color(TAB_INACTIVE_INDEX_BG)))
        screen.cursor.bold = TAB_INACTIVE_BOLD
        screen.cursor.italic = TAB_INACTIVE_ITALIC

    screen.cursor.fg = index_bg
    screen.cursor.bg = default_bg
    screen.draw(LEFT_CORNER)

    screen.cursor.fg = index_fg
    screen.cursor.bg = index_bg
    screen.draw(TITLE_ICONS.get(title.lower(), DEFAULT_ICON))

    screen.cursor.fg = index_bg
    screen.cursor.bg = tab_bg
    screen.draw(TAB_INDEX_SEPARATOR)

    screen.cursor.fg = tab_fg
    screen.cursor.bg = tab_bg
    screen.draw(title)

    screen.cursor.fg = tab_bg
    screen.cursor.bg = default_bg
    screen.draw(RIGHT_CORNER)

    end = screen.cursor.x

    screen.cursor.fg = 0
    screen.cursor.bg = 0
    if not is_last:
        screen.draw(' ')

    return end
