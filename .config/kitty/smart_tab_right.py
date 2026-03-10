#!/usr/bin/env python3
"""Smart tab right: switch to next tab, or create new tab if on last one"""

from kitty.boss import Boss

def main(args):
    pass

def handle_result(args, answer, target_window_id, boss: Boss):
    tm = boss.active_tab_manager
    if tm is None:
        return

    # Get current tab and all tabs
    active_tab = tm.active_tab
    tabs = list(tm.tabs)

    if not tabs or active_tab is None:
        return

    # Find current tab index
    try:
        current_index = tabs.index(active_tab)
    except ValueError:
        return

    # Check if we're on the last tab
    if current_index == len(tabs) - 1:
        # Create new tab with current working directory
        # Uses --cwd=current which works with SSH via shell integration
        window = boss.window_id_map.get(target_window_id)
        boss.call_remote_control(window, ('launch', '--type=tab', '--cwd=current'))
    else:
        # Switch to next tab
        tm.set_active_tab(tabs[current_index + 1])

handle_result.no_ui = True
