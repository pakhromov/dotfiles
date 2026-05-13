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
    def on_activated_async(self, view):
        self._update(view)

    def on_load_async(self, view):
        self._update(view)

    def on_modified_async(self, view):
        self._update(view)

    def on_close(self, view):
        _urls_for_view.pop(view.id(), None)

    def on_post_text_command(self, view, command_name, args):
        if command_name != 'drag_select' or not args or 'event' not in args:
            return
        event = args['event']
        if event.get('button') != 1 or event.get('modifiers'):
            return
        if not all(s.empty() for s in view.sel()):
            return
        pt = view.window_to_text((event['x'], event['y']))
        for region in _urls_for_view.get(view.id(), []):
            if region.contains(pt):
                url = view.substr(region)
                sublime.set_timeout(lambda: open_url(url), 0)
                return

    def _update(self, view):
        urls = view.find_all(URL_REGEX)
        _urls_for_view[view.id()] = urls
        view.add_regions(
            'clickable-urls',
            urls,
            'region.bluish',
            flags=sublime.DRAW_NO_FILL | sublime.DRAW_NO_OUTLINE | sublime.DRAW_STIPPLED_UNDERLINE
        )
