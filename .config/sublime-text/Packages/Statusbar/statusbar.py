from datetime import datetime
import os
import sublime
import sublime_plugin


def plugin_loaded():
    for window in sublime.windows():
        for view in window.views():
            StatusBarPlugin().on_activated(view)


def _fmt_size(n):
    for unit in ('B', 'KB', 'MB', 'GB', 'TB'):
        if n < 1024 or unit == 'TB':
            return f'{int(n)} {unit}' if unit == 'B' else f'{n:.1f} {unit}'
        n /= 1024


class StatusBarPlugin(sublime_plugin.EventListener):
    _ticking = set()

    def on_activated(self, view):
        view.erase_status('  time')
        view.erase_status('z_path')
        view.erase_status('WordCountStatus')
        self._render(view)
        self._ensure_ticking(view)

    def on_load(self, view):
        self._render(view)

    def on_modified(self, view):
        self._render(view)

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
        time_str = datetime.now().strftime("%H:%M")
        lines = view.rowcol(view.size())[0] + 1

        path = view.file_name()
        size_str = ''
        if path:
            try:
                size_str = _fmt_size(os.path.getsize(path))
            except OSError:
                pass

        sep = '     '
        stats = f'{lines} Lines, {size_str}' if size_str else f'{lines} Lines'
        parts = [f' {time_str}', stats]
        if path:
            parts.append(path + '     ')

        view.set_status('  statusbar', sep.join(parts))
