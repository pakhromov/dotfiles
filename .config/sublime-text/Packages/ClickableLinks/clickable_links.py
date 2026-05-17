import subprocess
import threading
import sublime
import sublime_plugin


URL_REGEX = r'\bhttps?://[-A-Za-z0-9+&@#/%?=~_()|!:,.;\']*[-A-Za-z0-9+&@#/%=~_(|]'
_urls_for_view = {}


def open_url(url):
    def _run():
        p = subprocess.Popen(
            ['sh', '-c', 'xdg-open "$1" &', '_', url],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        p.wait()
    threading.Thread(target=_run, daemon=True).start()


class UrlHighlighter(sublime_plugin.EventListener):
    def on_activated_async(self, view): self._update(view)
    def on_load_async(self, view): self._update(view)
    def on_modified_async(self, view): self._update(view)

    def on_close(self, view):
        _urls_for_view.pop(view.id(), None)

    def _update(self, view):
        if view.size() > 1048576:
            _urls_for_view.pop(view.id(), None)
            view.erase_regions('clickable-urls')
            return
        urls = view.find_all(URL_REGEX)
        _urls_for_view[view.id()] = urls
        view.add_regions('clickable-urls', urls, 'region.bluish',
            flags=sublime.DRAW_NO_FILL | sublime.DRAW_NO_OUTLINE | sublime.DRAW_STIPPLED_UNDERLINE)


class OpenUrlAtCursorCommand(sublime_plugin.TextCommand):
    def want_event(self):
        return True

    def run(self, edit, event=None):
        if not all(s.empty() for s in self.view.sel()):
            return
        if not self.view.sel():
            return
        pt = self.view.sel()[0].begin()
        for region in _urls_for_view.get(self.view.id(), []):
            if region.begin() <= pt < region.end():
                open_url(self.view.substr(region))
                return
