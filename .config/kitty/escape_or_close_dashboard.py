from kittens.tui.handler import result_handler

DASHBOARD_CLASS = 'float-time'
# Programs that don't quit on a plain Escape themselves -- close their
# floating window instead. Matched against the foreground process name,
# not wm_class, since some of these floating windows share a class
# (e.g. impala and the clipboard image picker both use float-full).
ESCAPE_CLOSES_PROGRAMS = {'impala'}


def _foreground_program_names(w):
    for p in w.child.foreground_processes:
        cmdline = p.get('cmdline') or []
        if cmdline:
            yield cmdline[0].rsplit('/', 1)[-1]


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return
    tab = w.tabref()
    tm = tab.tab_manager_ref() if tab else None
    is_dashboard = tm is not None and tm.wm_class == DASHBOARD_CLASS
    runs_escape_closes_program = any(name in ESCAPE_CLOSES_PROGRAMS for name in _foreground_program_names(w))
    if tm is not None and (is_dashboard or runs_escape_closes_program):
        boss.confirm_os_window_close(tm.os_window_id)
    else:
        # Not a special-cased window -- forward Escape exactly as kitty
        # itself would have, so the global Escape key is unaffected
        # everywhere else.
        w.send_key('escape')


def main(args):
    return None
