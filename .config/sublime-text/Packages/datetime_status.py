import sublime
import sublime_plugin
from datetime import datetime


class DateTimeStatusPlugin(sublime_plugin.EventListener):
    def on_activated(self, view):
        self.update_datetime(view)

    def on_load(self, view):
        self.update_datetime(view)

    def update_datetime(self, view):

        # Format: DD.MM.YY, HH:MM
        now = datetime.now()
        time_str = now.strftime("%H:%M")

        # Use key with leading space to position at leftmost
        view.set_status('  datetime', ' ' + time_str)

        # Update every minute
        sublime.set_timeout(lambda: self.update_datetime(view), 60000)
