# cool exmples:
# https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-15338410
# https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-5553107
# https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-3831256
# my tmux

# configuration - separators between tabs, separators between status elements

from kitty.tab_bar import as_rgb
from kitty.utils import color_as_int
from kitty.rgb import to_color
from kitty.fast_data_types import add_timer, get_boss
from datetime import datetime
import os
import signal
import subprocess

TAB_BAR_BG = "#121212"

TAB_ACTIVE_INDEX_FG = "#16161e"
TAB_ACTIVE_FG = "#a0a0a0"
TAB_INACTIVE_INDEX_FG = "#16161e"
TAB_INACTIVE_FG = "#a0a0a0"

TAB_ACTIVE_INDEX_BG = "#d77757"
TAB_ACTIVE_BG = "#242424"
TAB_INACTIVE_INDEX_BG = "#5e7175"
TAB_INACTIVE_BG = "#242424"

STATUS_FG = "#a0a0a0"
STATUS_BG = "#242424"
STATUS_INDEX_FG = "#16161e"
STATUS_INDEX_BG = "#5e7175"

TAB_ACTIVE_BOLD = False
TAB_ACTIVE_ITALIC = False
TAB_INACTIVE_BOLD = False
TAB_INACTIVE_ITALIC = False
STATUS_BOLD = False
STATUS_ITALIC = False

STATUS_LEFT = "date"
STATUS_RIGHT = "battery,updates,time"


LEFT_CORNER = "◖"   #
RIGHT_CORNER = "◗"  #
TAB_INDEX_SEPARATOR = ""
STATUS_INDEX_SEPARATOR = ""
TIME_ICON = "󰥔"
DATE_ICON = ""
BATTERY_10 = "󰁺"
BATTERY_50 = "󰁾"
BATTERY_90 = "󰂂"
BATTERY_10_CHARGING = "󰢜"
BATTERY_50_CHARGING = "󰢝 "
BATTERY_90_CHARGING = "󰂋"
UPDATES_ICON = ""
UPDATES_FETCH = "󰭽 "

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


def get_icon(title):
    return TITLE_ICONS.get(title.lower(), DEFAULT_ICON)


def _format_title(title):
    if title == '~':
        title = os.path.basename(os.path.expanduser('~'))
    if '/' in title or title.startswith('...'):
        last_part = os.path.basename(title.rstrip('/'))
        title = last_part if last_part else title
    if MAX_TITLE_LENGTH is not None and len(title) > MAX_TITLE_LENGTH:
        title = title[:MAX_TITLE_LENGTH - 1] + '…'
    return title


def transform_title(tab):
    return _format_title(tab.title)


def _widgets_width(widgets):
    if not widgets:
        return 0
    # LEFT_CORNER + icon + space + STATUS_INDEX_SEPARATOR + space + text + RIGHT_CORNER
    fixed = 5 + len(STATUS_INDEX_SEPARATOR)
    return sum(fixed + len(text) for _, text in widgets) + (len(widgets) - 1)


_timer_id = None


def _redraw_tab_bar(_timer_id):
    boss = get_boss()
    for tab_manager in boss.all_tab_managers:
        tab_manager.mark_tab_bar_dirty()


def _draw_widget(screen, icon, text, index_fg, index_bg, tab_bg, tab_fg, default_bg):
    screen.cursor.fg = index_bg
    screen.cursor.bg = default_bg
    screen.draw(LEFT_CORNER)
    screen.cursor.fg = index_fg
    screen.cursor.bg = index_bg
    screen.draw(icon)
    screen.draw(' ')
    screen.cursor.fg = index_bg
    screen.cursor.bg = tab_bg
    screen.draw(STATUS_INDEX_SEPARATOR)
    screen.cursor.fg = tab_fg
    screen.cursor.bg = tab_bg
    screen.draw(' ')
    screen.draw(text)
    screen.cursor.fg = tab_bg
    screen.cursor.bg = default_bg
    screen.draw(RIGHT_CORNER)


def _draw_widgets(screen, widgets, index_fg, index_bg, tab_bg, tab_fg, default_bg):
    for i, (icon, text) in enumerate(widgets):
        _draw_widget(screen, icon, text, index_fg, index_bg, tab_bg, tab_fg, default_bg)
        if i < len(widgets) - 1:
            screen.cursor.fg = 0
            screen.cursor.bg = 0
            screen.draw(' ')


def _get_battery_status():
    try:
        batteries = [d for d in os.listdir('/sys/class/power_supply') if d.startswith('BAT')]
        if not batteries:
            return None
        base = f'/sys/class/power_supply/{batteries[0]}'
        with open(f'{base}/capacity') as f:
            percent = int(f.read().strip())
        with open(f'{base}/status') as f:
            status = f.read().strip()
    except Exception:
        return None

    charging = status in ('Charging', 'Full')
    if percent >= 70:
        icon = BATTERY_90_CHARGING if charging else BATTERY_90
    elif percent >= 30:
        icon = BATTERY_50_CHARGING if charging else BATTERY_50
    else:
        icon = BATTERY_10_CHARGING if charging else BATTERY_10

    return (icon, f'{percent}%')


def _preexec():
    signal.pthread_sigmask(signal.SIG_SETMASK, set())
    os.setsid()


_updates_count = None
_updates_popen = None
_updates_last_launch = None


def _get_updates_status():
    global _updates_count, _updates_popen, _updates_last_launch

    now = datetime.now().timestamp()

    if _updates_popen is not None and _updates_popen.poll() is not None:
        out = _updates_popen.stdout.read().decode().strip()
        _updates_count = int(out) if out.isdigit() else None
        _updates_popen = None

    if _updates_popen is None and (
        _updates_last_launch is None or (now - _updates_last_launch) >= 3600
    ):
        _updates_last_launch = now
        _updates_popen = subprocess.Popen(
            ['sh', '-c', 'a=$(checkupdates 2>/dev/null | wc -l); b=$(yay -Qua 2>/dev/null | wc -l); echo $((a+b))'],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            preexec_fn=_preexec,
        )

    age = (now - _updates_last_launch) if _updates_last_launch is not None else None
    if _updates_count is None or age is None or age >= 3900:
        return (UPDATES_ICON, str(UPDATES_FETCH))
    return (UPDATES_ICON, str(_updates_count))


# Shared state across draw_tab calls within one render pass
_render_right_widgets = None
_render_colors = None

# Tab width cache: saved at end of each render, used in the next render for centering
_cached_tabs_width = 0
_current_render_tabs_width = 0


def _build_widgets(spec, now):
    widgets = []
    for name in [s.strip() for s in spec.split(',') if s.strip()]:
        if name == 'date':
            widgets.append((DATE_ICON, now.strftime("%-d %B, %A")))
        elif name == 'time':
            widgets.append((TIME_ICON, now.strftime("%H:%M")))
        elif name == 'battery':
            w = _get_battery_status()
            if w:
                widgets.append(w)
        elif name == 'updates':
            w = _get_updates_status()
            if w:
                widgets.append(w)
    return widgets


def draw_tab(draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data):
    global _timer_id, _render_right_widgets, _render_colors
    global _cached_tabs_width, _current_render_tabs_width

    if _timer_id is None:
        _timer_id = add_timer(_redraw_tab_bar, 10.0, True)

    # Compute title first — needed for both layout and drawing
    title = transform_title(tab)
    tab_width = 6 + len(title)  # LEFT_CORNER + ICON + sp + SEP + sp + title + RIGHT_CORNER

    default_bg = as_rgb(color_as_int(to_color(TAB_BAR_BG))) if TAB_BAR_BG else as_rgb(int(draw_data.default_bg))
    s_index_fg = as_rgb(color_as_int(to_color(STATUS_INDEX_FG)))
    s_index_bg = as_rgb(color_as_int(to_color(STATUS_INDEX_BG)))
    s_tab_bg   = as_rgb(color_as_int(to_color(STATUS_BG)))
    s_tab_fg   = as_rgb(color_as_int(to_color(STATUS_FG)))

    if tab.is_active:
        tab_fg   = as_rgb(color_as_int(to_color(TAB_ACTIVE_FG)))
        tab_bg   = as_rgb(color_as_int(to_color(TAB_ACTIVE_BG)))
        index_fg = as_rgb(color_as_int(to_color(TAB_ACTIVE_INDEX_FG)))
        index_bg = as_rgb(color_as_int(to_color(TAB_ACTIVE_INDEX_BG)))
    else:
        tab_fg   = as_rgb(color_as_int(to_color(TAB_INACTIVE_FG)))
        tab_bg   = as_rgb(color_as_int(to_color(TAB_INACTIVE_BG)))
        index_fg = as_rgb(color_as_int(to_color(TAB_INACTIVE_INDEX_FG)))
        index_bg = as_rgb(color_as_int(to_color(TAB_INACTIVE_INDEX_BG)))

    if index == 1:
        _current_render_tabs_width = 0  # reset accumulator for this render pass

        # Skip left-side drawing during kitty's for_layout measurement pass.
        # Drawing left/right widgets in for_layout inflates ideal_tab_lengths,
        # causing the overflow threshold check (line 736 of kitty/tab_bar.py)
        # to fire on subsequent tabs and show " …" instead of real content.
        if not extra_data.for_layout:
            screen.cursor.bold = STATUS_BOLD
            screen.cursor.italic = STATUS_ITALIC

            now = datetime.now()
            left_widgets = _build_widgets(STATUS_LEFT, now)
            right_widgets = _build_widgets(STATUS_RIGHT, now)

            _render_right_widgets = right_widgets
            _render_colors = (s_index_fg, s_index_bg, s_tab_bg, s_tab_fg, default_bg)

            left_w  = _widgets_width(left_widgets)
            right_w = _widgets_width(right_widgets)

            try:
                boss = get_boss()
                tm = boss.active_tab_manager
                all_tabs = list(tm.tabs)
                tabs_w = sum(6 + len(_format_title(t.title)) for t in all_tabs) + max(0, len(all_tabs) - 1)
            except Exception:
                tabs_w = _cached_tabs_width

            # Center tabs relative to full window width, not the available gap.
            tab_start = max(left_w, (screen.columns - tabs_w) // 2)

            _draw_widgets(screen, left_widgets, s_index_fg, s_index_bg, s_tab_bg, s_tab_fg, default_bg)

            gap = tab_start - screen.cursor.x
            if gap > 0:
                screen.cursor.fg = 0
                screen.cursor.bg = 0
                screen.draw(' ' * gap)

    # Accumulate this tab's width into the current render total
    _current_render_tabs_width += tab_width
    if not is_last:
        _current_render_tabs_width += 1  # space between tabs

    # Draw the tab
    screen.cursor.bold = TAB_ACTIVE_BOLD if tab.is_active else TAB_INACTIVE_BOLD
    screen.cursor.italic = TAB_ACTIVE_ITALIC if tab.is_active else TAB_INACTIVE_ITALIC

    screen.cursor.fg = index_bg
    screen.cursor.bg = default_bg
    screen.draw(LEFT_CORNER)

    screen.cursor.fg = index_fg
    screen.cursor.bg = index_bg
    screen.draw(get_icon(title))
    screen.draw(' ')

    screen.cursor.fg = index_bg
    screen.cursor.bg = tab_bg
    screen.draw(TAB_INDEX_SEPARATOR)

    screen.draw(' ')
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
    elif not extra_data.for_layout:
        # Skip right-side drawing in for_layout pass for the same reason as above.
        _cached_tabs_width = _current_render_tabs_width
        screen.draw(' ')
        screen.cursor.bold = STATUS_BOLD
        screen.cursor.italic = STATUS_ITALIC
        if _render_right_widgets and _render_colors:
            si_fg, si_bg, st_bg, st_fg, d_bg = _render_colors
            right_w = _widgets_width(_render_right_widgets)
            gap = screen.columns - screen.cursor.x - right_w
            if gap >= 0:
                if gap > 0:
                    screen.cursor.fg = 0
                    screen.cursor.bg = 0
                    screen.draw(' ' * gap)
                _draw_widgets(screen, _render_right_widgets, si_fg, si_bg, st_bg, st_fg, d_bg)
            else:
                boss = get_boss()
                for tm in boss.all_tab_managers:
                    tm.mark_tab_bar_dirty()

    return end
