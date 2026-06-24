from kittens.tui.handler import result_handler


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return
    screen = w.screen
    if not screen.is_main_linebuf():
        return
    w.finish_scroll_animation()
    # Anchor the selection start while scrolled to the very top of history,
    # then the end while scrolled to the very bottom -- each anchor captures
    # screen.scrolled_by at the moment it's set, same as a real click-drag.
    w.scroll_home()
    screen.start_selection(0, 0, False, 0, True)
    w.scroll_end()
    screen.update_selection(screen.columns - 1, screen.lines - 1, False, True, False)


def main(args):
    return None
