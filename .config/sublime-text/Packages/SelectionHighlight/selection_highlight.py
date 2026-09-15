import sublime
import sublime_plugin
import threading

REGION_KEY = 'selection-highlight'

# Panels that count as "the search is open". The console, the command palette
# and output panels are not search, so they leave highlighting alone.
FIND_PANELS = ('find', 'replace', 'incremental_find', 'find_in_files')


def _find_panel_open(window):
    """True while a find panel is up, so nothing in this plugin should run."""
    window = window or sublime.active_window()
    return bool(window) and window.active_panel() in FIND_PANELS


class SelectionHighlightListener(sublime_plugin.EventListener):
    _lock = threading.Semaphore()

    def on_selection_modified_async(self, view):
        if _find_panel_open(view.window()):
            return
        SelectionHighlightListener._lock.acquire()
        try:
            self._update(view)
        finally:
            SelectionHighlightListener._lock.release()

    def on_activated_async(self, view):
        if _find_panel_open(view.window()):
            return
        SelectionHighlightListener._lock.acquire()
        try:
            self._update(view)
        finally:
            SelectionHighlightListener._lock.release()

    def on_post_window_command(self, window, command_name, args):
        if command_name == 'show_panel':
            # Opening find wipes whatever is on screen; the listeners above
            # keep it from coming back while the panel stays up
            if not _find_panel_open(window):
                return
            for v in window.views():
                v.erase_regions(REGION_KEY)
                v.erase_status(REGION_KEY)
        elif command_name == 'hide_panel':
            view = window.active_view()
            if view:
                self._update(view)

    def _update(self, view):
        sel = view.sel()
        if not sel or sel[0].empty():
            view.erase_regions(REGION_KEY)
            view.erase_status(REGION_KEY)
            return

        regions = view.find_all(view.substr(sel[0]), sublime.LITERAL)
        view.add_regions(REGION_KEY, regions, 'region.bluish', flags=sublime.DRAW_NO_FILL)
        if len(regions) > 1:
            view.set_status(REGION_KEY, f'{len(regions)} matches')
        else:
            view.erase_status(REGION_KEY)
