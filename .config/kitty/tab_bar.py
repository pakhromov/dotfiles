# cool exmples:
# https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-15338410
# https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-5553107
# https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-9218936
# https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-3831256
# my tmux

from kitty.tab_bar import as_rgb
from kitty.utils import color_as_int
from kitty.rgb import to_color
from kitty.fast_data_types import add_timer, get_boss
from datetime import datetime

#ACTIVE_FG = "#A9B1D6"
#ACTIVE_BG = "#2A2F41"
#INACTIVE_FG = "#A9B1D6"
INACTIVE_BG = "#121212"
#TAB_BAR_BG = "#121212"
#ACTIVE_INDEX_FG = "#2A2F41"
#ACTIVE_INDEX_BG = "#7AA2F7"
#INACTIVE_INDEX_FG = "#7AA2F7"
#INACTIVE_INDEX_BG = "#2A2F41"
TEXT_FG = "#A0A0A0"

ACTIVE_FG = None
ACTIVE_BG = None
INACTIVE_FG = None
#INACTIVE_BG = None
TAB_BAR_BG = None
ACTIVE_INDEX_FG = None
ACTIVE_INDEX_BG = None
INACTIVE_INDEX_FG = None
INACTIVE_INDEX_BG = None
#TEXT_FG = None


UNICODE_DIGITS = "🯰🯱🯲🯳🯴🯵🯶🯷🯸🯹"
LEFT_CORNER = "\ue0b6"   #
RIGHT_CORNER = "\ue0b4"  #
INDEX_SEPARATOR = ""
TIME_ICON = ""
DATE_ICON = ""

# Default icon
DEFAULT_ICON = ""

# Title to icon mapping - add your custom icons here
TITLE_ICONS = {
    "yazi": "",
    "btm": "󰨇",
    "torrserver": "",
    "pacseek": "",
    "pacsea": "",
    "impala": "",
    "yay": "",
    "codex": "󱚠",

}

# Maximum title length (set to None for no limit)
MAX_TITLE_LENGTH = 10


def to_unicode_digits(text):
    """
    Convert ALL digits in any string to unicode digits.
    This is the core function - use it for everything numeric.

    Examples:
        "123" -> "🯱🯲🯳"
        "12:34" -> "🯱🯲:🯳🯴"
        "5 updates" -> "🯵 updates"
    """
    result = []
    for char in str(text):
        if char.isdigit():
            result.append(UNICODE_DIGITS[int(char)])
        else:
            result.append(char)
    return ''.join(result)


def format_index(index):
    """Convert tab index to unicode digits"""
    return to_unicode_digits(index)


def get_icon(title):
    """Get icon for a title, fallback to default icon"""
    return TITLE_ICONS.get(title.lower(), DEFAULT_ICON)


def transform_title(tab):
    """
    Transform tab title based on custom rules.

    Rules:
    - If title is '~' (home directory), show shell name instead
    - If title is a path, show only the last directory name
    """
    from kitty.tab_bar import TabAccessor
    import os

    title = tab.title

    # If in home directory, show username (last part of home path)
    if title == '~':
        title = os.path.basename(os.path.expanduser('~'))

    # If title looks like a path (contains / or starts with ...), extract last part
    if '/' in title or title.startswith('...'):
        # Get the last component of the path
        last_part = os.path.basename(title.rstrip('/'))
        title = last_part if last_part else title

    # Truncate title if it exceeds MAX_TITLE_LENGTH
    if MAX_TITLE_LENGTH is not None and len(title) > MAX_TITLE_LENGTH:
        title = title[:MAX_TITLE_LENGTH - 1] + '…'

    return title

def draw_tab(draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data):
    """
    Minimal tab bar implementation - draws tabs with simple separators

    Args:
        draw_data: DrawData object with tab bar configuration
        screen: Screen object to draw on
        tab: TabBarData with tab information
        before: Cursor x position before drawing
        max_tab_length: Maximum length for this tab
        index: Tab index (1-based)
        is_last: Whether this is the last tab
        extra_data: ExtraData with prev_tab, next_tab info

    Returns:
        Final cursor x position after drawing
    """
    # Get colors (use custom or fall back to kitty.conf)
    if tab.is_active:
        tab_fg = as_rgb(color_as_int(to_color(ACTIVE_FG))) if ACTIVE_FG else as_rgb(int(draw_data.tab_fg(tab)))
        tab_bg = as_rgb(color_as_int(to_color(ACTIVE_BG))) if ACTIVE_BG else as_rgb(int(draw_data.tab_bg(tab)))
        index_fg = as_rgb(color_as_int(to_color(ACTIVE_INDEX_FG))) if ACTIVE_INDEX_FG else tab_fg
        index_bg = as_rgb(color_as_int(to_color(ACTIVE_INDEX_BG))) if ACTIVE_INDEX_BG else tab_bg
    else:
        tab_fg = as_rgb(color_as_int(to_color(INACTIVE_FG))) if INACTIVE_FG else as_rgb(int(draw_data.tab_fg(tab)))
        tab_bg = as_rgb(color_as_int(to_color(INACTIVE_BG))) if INACTIVE_BG else as_rgb(int(draw_data.tab_bg(tab)))
        index_fg = as_rgb(color_as_int(to_color(INACTIVE_INDEX_FG))) if INACTIVE_INDEX_FG else tab_fg
        index_bg = as_rgb(color_as_int(to_color(INACTIVE_INDEX_BG))) if INACTIVE_INDEX_BG else tab_bg

    default_bg = as_rgb(color_as_int(to_color(TAB_BAR_BG))) if TAB_BAR_BG else as_rgb(int(draw_data.default_bg))
    text_fg = as_rgb(color_as_int(to_color(TEXT_FG))) if TEXT_FG else as_rgb(int(draw_data.tab_fg(tab)))

    # Transform title
    title = transform_title(tab)

    # Draw left rounded corner with index color
    screen.cursor.fg = index_bg
    screen.cursor.bg = default_bg
    screen.draw(LEFT_CORNER)

    # Draw index section
    screen.cursor.fg = index_fg
    screen.cursor.bg = index_bg
    screen.draw(format_index(index))

    # Draw index separator (transition from index to main section)
    screen.cursor.fg = index_bg
    screen.cursor.bg = tab_bg
    screen.draw(INDEX_SEPARATOR)

    # Set colors for tab content
    screen.cursor.fg = tab_fg
    screen.cursor.bg = tab_bg

    # Draw the icon
    screen.draw(' ')
    screen.draw(get_icon(title))

    # Draw the tab title
    screen.draw(' ')
    screen.draw(title)

    # Draw a space after the tab title
    #screen.draw(' ')

    # Draw right rounded corner
    screen.cursor.fg = tab_bg
    screen.cursor.bg = default_bg
    screen.draw(RIGHT_CORNER)

    # Save the end position (for click detection)
    end = screen.cursor.x

    # Reset colors for separator
    screen.cursor.fg = 0
    screen.cursor.bg = 0

    # Draw separator space if not the last tab (outside the clickable region)
    if not is_last:
        screen.draw(' ')
    else:
        # Last tab - draw separator
        screen.draw(' ')

    # Return the end position (before the separator space)
    return end
