import webbrowser
import sublime
import sublime_plugin


URL_REGEX = r'\bhttps?://[-A-Za-z0-9+&@#/%?=~_()|!:,.;\']*[-A-Za-z0-9+&@#/%=~_(|]'
_urls_for_view = {}
_pending_open = {}



class UrlHighlighter(sublime_plugin.EventListener):
    def on_activated_async(self, view): self._update(view)
    def on_load_async(self, view): self._update(view)
    def on_modified_async(self, view): self._update(view)

    def on_close(self, view):
        _urls_for_view.pop(view.id(), None)
        _pending_open.pop(view.id(), None)

    def on_selection_modified(self, view):
        if view.id() in _pending_open and not all(s.empty() for s in view.sel()):
            _pending_open.pop(view.id(), None)

    def on_post_text_command(self, view, command_name, args):
        if command_name != 'drag_select':
            return
        vid = view.id()
        _pending_open.pop(vid, None)
        if args and (args.get('extend') or args.get('additive') or args.get('by')):
            return
        if not view.sel():
            return
        pt = view.sel()[0].begin()
        for region in _urls_for_view.get(vid, []):
            if region.begin() < pt < region.end():
                url = view.substr(region)
                _pending_open[vid] = url
                sublime.set_timeout(lambda: self._open_pending(vid, url), 300)
                return

    def _open_pending(self, vid, url):
        if _pending_open.get(vid) == url:
            _pending_open.pop(vid, None)
            webbrowser.open(url)

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
            if region.begin() < pt < region.end():
                webbrowser.open(self.view.substr(region))
                return
