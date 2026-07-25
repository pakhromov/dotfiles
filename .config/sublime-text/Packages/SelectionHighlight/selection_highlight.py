import sublime
import sublime_plugin
import threading

REGION_KEY = 'selection-highlight'

class SelectionHighlightListener(sublime_plugin.EventListener):
    _lock = threading.Semaphore()
    _search_term = None

    def on_selection_modified_async(self, view):
        SelectionHighlightListener._lock.acquire()
        try:
            self._update(view)
        finally:
            SelectionHighlightListener._lock.release()

    def on_activated_async(self, view):
        SelectionHighlightListener._lock.acquire()
        try:
            self._update(view)
        finally:
            SelectionHighlightListener._lock.release()

    def on_post_window_command(self, window, command_name, args):
        if command_name != 'show_panel':
            return
        view = window.active_view()
        sel = view.sel() if view else None
        SelectionHighlightListener._search_term = (
            view.substr(sel[0]) if view and sel and not sel[0].empty() else None
        )
        for v in window.views():
            v.erase_regions(REGION_KEY)
            v.erase_status(REGION_KEY)

    def _update(self, view):
        sel = view.sel()
        if not sel or sel[0].empty():
            view.erase_regions(REGION_KEY)
            view.erase_status(REGION_KEY)
            return

        text = view.substr(sel[0])
        panel_active = view.window() and view.window().active_panel()

        if panel_active and text == SelectionHighlightListener._search_term:
            view.erase_regions(REGION_KEY)
            view.erase_status(REGION_KEY)
            return

        regions = view.find_all(text, sublime.LITERAL)
        view.add_regions(REGION_KEY, regions, 'region.bluish', flags=sublime.DRAW_NO_FILL)
        if len(regions) > 1:
            view.set_status(REGION_KEY, f'{len(regions)} matches')
        else:
            view.erase_status(REGION_KEY)
