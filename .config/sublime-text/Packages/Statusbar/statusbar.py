import sublime
import sublime_plugin


def plugin_loaded():
    for window in sublime.windows():
        for view in window.views():
            StatusBarPlugin().on_activated(view)


class StatusBarPlugin(sublime_plugin.EventListener):
    def on_activated(self, view):
        self._render(view)

    def on_post_save(self, view):
        self._render(view)

    def _render(self, view):
        path = view.file_name()
        view.set_status('aa', f' {path}   ' if path else '')
