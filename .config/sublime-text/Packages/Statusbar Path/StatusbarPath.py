import os

import sublime
import sublime_plugin


class CurrentPathStatusCommand(sublime_plugin.EventListener):
    _cleaned_up = False

    def on_activated(self, view):
        # Clear old status keys
        if not CurrentPathStatusCommand._cleaned_up:
            CurrentPathStatusCommand._cleaned_up = True

        filename = view.file_name()
        if filename:
            # Add spacing before the filename
            view.set_status('  path', '   ' + filename)  # Leading spaces sort first
