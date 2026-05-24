from datetime import datetime
import sublime
import sublime_plugin


def plugin_loaded():
    for window in sublime.windows():
        for view in window.views():
            StatusBarPlugin().on_activated(view)


class StatusBarPlugin(sublime_plugin.EventListener):
    _ticking = set()

    def on_activated(self, view):
        self._render(view)
        self._ensure_ticking(view)

    def on_post_save(self, view):
        self._render(view)

    def on_close(self, view):
        StatusBarPlugin._ticking.discard(view.id())

    def _ensure_ticking(self, view):
        vid = view.id()
        if vid not in StatusBarPlugin._ticking:
            StatusBarPlugin._ticking.add(vid)
            self._tick(view)

    def _tick(self, view):
        if not view.is_valid() or view.id() not in StatusBarPlugin._ticking:
            return
        self._render(view)
        sublime.set_timeout(lambda: self._tick(view), 60000)

    def _render(self, view):
        sep = '     '
        time_str = datetime.now().strftime("%H:%M")
        path = view.file_name()
        if path:
            view.set_status('  statusbar', f'  {time_str}{sep}{path}{sep}')
        else:
            view.set_status('  statusbar', f'  {time_str}')
