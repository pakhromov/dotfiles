import ast
import re
import subprocess
from gettext import gettext as _
from pathlib import Path

from kittens.tui.handler import Handler, result_handler
from kittens.tui.line_edit import LineEdit
from kittens.tui.loop import Loop, MouseButton, MouseEvent
from kittens.tui.operations import (
    MouseTracking,
    clear_screen,
    cursor,
    move_cursor_by,
    set_line_wrapping,
    set_window_title,
    styled,
)
from kitty.config import cached_values_for
from kitty.constants import config_dir
from kitty.key_encoding import EventType

# scan()/goto() run inside the interactive search process and have no
# direct access to boss/window/screen, so they ask kitty's main process to
# do that work via remote control -- `kitty @ kitten <path> scan/goto ...`
# -- which needs a literal file path. Since handle_result (below) lives in
# this same file, that path is just this file itself -- but __file__ can't
# be used to find it: when this module is loaded for a `kitty @ kitten`
# remote-control call, kitty's loader execs it with a bare {'__name__':
# 'kitten'} globals dict (confirmed by reading import_kitten_main_module in
# kittens/runner.py), so __file__ is simply never defined in that path
# (only the `kitty +kitten` direct-launch path sets it, via runpy.run_path).
# config_dir is reliably available in both, so build the path from that
# plus our own known filename instead.
SELF_PATH = Path(config_dir) / "search.py"

NON_SPACE_PATTERN = re.compile(r"\S+")
SPACE_PATTERN_END = re.compile(r"\s+$")
NON_ALPHANUM_PATTERN = re.compile(r"[^\w\d]+")
NON_ALPHANUM_PATTERN_END = re.compile(r"[^\w\d]+$")


def call_remote_control(args: list[str]) -> None:
    subprocess.run(["kitty", "@", *args], capture_output=True)


def apply_native_marker(window_id: int, raw_text: str, ftype: str) -> None:
    """ftype is one of text/itext/regex/iregex -- kitty matches and colors
    every occurrence entirely in C, no Python callback involved. For the
    text/itext types kitty does its own re.escape() on raw_text internally,
    so it must NOT be pre-escaped here (that would double-escape it)."""
    call_remote_control(["create-marker", f"--match=id:{window_id}", ftype, "1", raw_text])


def remove_native_marker(window_id: int) -> None:
    call_remote_control(["remove-marker", f"--match=id:{window_id}"])


def reindex(text: str, pattern: re.Pattern[str], right: bool = False) -> tuple[int, int]:
    if not right:
        m = pattern.search(text)
    else:
        matches = [x for x in pattern.finditer(text) if x]
        if not matches:
            raise ValueError
        m = matches[-1]
    if not m:
        raise ValueError
    return m.span()


# ===== Position tracking: talks to search_backend.py (a separate, no_ui
# kitten -- it MUST stay a separate file, since a kitten module whose
# handle_result is decorated no_ui=True always skips main()/the UI
# entirely, on every invocation; merging it in here would break the
# interactive launch). =====


def scan(window_id: int, pattern: str, ignorecase: bool) -> tuple[list, int, int, int]:
    """Ask the backend to scan the window. Returns (matches, screen_lines,
    scrolled_by, history_count): matches is every occurrence as
    [is_history, y, col], in top-to-bottom, left-to-right order;
    screen_lines/scrolled_by describe the window's current viewport, needed
    to find the match nearest the current scroll position (see
    SearchNav.rescan); history_count + screen_lines is the total scrollback
    line count, for display."""
    result = subprocess.run(
        [
            "kitty", "@", "kitten",
            f"--match=id:{window_id}",
            str(SELF_PATH),
            "scan",
            pattern,
            "1" if ignorecase else "0",
        ],
        capture_output=True,
    )
    try:
        return ast.literal_eval(result.stdout.decode())
    except (ValueError, SyntaxError):
        return [], 0, 0, 0


def goto(window_id: int, prev_group, new_group) -> None:
    """Clear the previous current-line underline (if any), underline the
    new one (if any), and scroll it into view -- all in one in-process call.

    prev_group/new_group are [is_history, y, ...] entries from group_by_line
    (only the first two fields are used). Either may be None: prev_group is
    None the first time a line is made current; new_group is None when a
    search now has zero matches and any stale underline just needs clearing."""
    if prev_group is None:
        prev_is_history, prev_y = "0", "-1"
    else:
        prev_is_history, prev_y = str(prev_group[0]), str(prev_group[1])
    if new_group is None:
        new_is_history, new_y = "0", "-1"
    else:
        new_is_history, new_y = str(new_group[0]), str(new_group[1])

    if prev_y == "-1" and new_y == "-1":
        return

    subprocess.run(
        [
            "kitty", "@", "kitten",
            f"--match=id:{window_id}",
            str(SELF_PATH),
            "goto",
            prev_is_history, prev_y,
            new_is_history, new_y,
        ],
        capture_output=True,
    )


def group_by_line(matches: list) -> list:
    """Group consecutive matches that share the same (is_history, y) into
    one entry per line, preserving order.

    Each group is [is_history, y, first_match_index], where
    first_match_index is the 0-based index of that line's first match
    within the original flat `matches` list -- this is what lets the UI
    show "first occurrence's index / total" without re-counting anything.

    Matches are already produced in top-to-bottom, left-to-right order by
    the backend, so consecutive entries belong to the same line whenever
    their (is_history, y) repeats -- no sorting needed here."""
    groups = []
    for i, (is_history, y, _col) in enumerate(matches):
        if groups and groups[-1][0] == is_history and groups[-1][1] == y:
            continue
        groups.append([is_history, y, i])
    return groups


# ===== Backend half: runs in-process inside kitty's main process, invoked
# via `kitty @ kitten <this file> scan/goto ...` (see SELF_PATH above).
# handle_result's no_ui=True means kitty calls it directly with boss
# access and skips main()/any UI entirely for these remote-control
# invocations -- main() below is only ever reached by the real interactive
# `kitty +kitten` launch. =====


def iter_rows(screen):
    """Yield (is_history, y, text) for every row in the window, in normal
    top-to-bottom reading order -- oldest history first, then the live
    screen top to bottom.

    Reads each row the same way kitty's own marker callback does
    (str(line) calls the same C function, line_as_unicode, that
    mark_text_in_line uses) -- so what we see here is guaranteed
    identical to what kitty itself considers each row's text, with no
    separate text-serialization step (get-text) to fall out of sync with.

    is_history/y are already in kitty's own native addressing for that
    buffer (historybuf.line(y) / main_linebuf.line(y)), not a flat
    oldest-first index -- so no conversion is needed before acting on a
    position later (e.g. to underline or scroll to it)."""
    history_count = screen.historybuf.count
    for y in range(history_count - 1, -1, -1):
        yield True, y, str(screen.historybuf.line(y))
    for y in range(screen.lines):
        yield False, y, str(screen.main_linebuf.line(y))


def line_for(screen, is_history: bool, y: int):
    return screen.historybuf.line(y) if is_history else screen.main_linebuf.line(y)


def depth_from_bottom(screen_lines: int, is_history: bool, y: int) -> int:
    """How many rows above the live bottom edge this row sits (0 = the
    bottommost row of the live screen). History grows upward from there:
    its own y=0 (most recent) sits immediately above the screen, at
    depth screen_lines; older rows have larger depth.

    Takes the plain row count rather than a screen object so it can also
    be used on the frontend side (no boss/screen access there) to find
    the match nearest the current scroll position -- see SearchNav.rescan."""
    if is_history:
        return screen_lines + y
    return screen_lines - 1 - y


def do_scan(args, w):
    pattern, ignorecase_flag = args[2], args[3]
    screen = w.screen
    empty = (
        [],
        screen.lines,
        screen.scrolled_by,
        screen.historybuf.count,
    )

    if not pattern:
        return repr(empty)
    flags = re.IGNORECASE if ignorecase_flag == "1" else 0
    try:
        compiled = re.compile(pattern, flags)
    except re.error:
        return repr(empty)

    matches = []
    for is_history, y, text in iter_rows(screen):
        for m in compiled.finditer(text):
            matches.append([int(is_history), y, m.start()])
    return repr((matches, screen.lines, screen.scrolled_by, screen.historybuf.count))


def do_goto(args, w):
    prev_is_history, prev_y, new_is_history, new_y = args[2], args[3], args[4], args[5]
    screen = w.screen

    if prev_y != "-1":
        line_for(screen, prev_is_history == "1", int(prev_y)).set_attribute("decoration", 0)

    if new_y != "-1":
        new_is_history = new_is_history == "1"
        new_y = int(new_y)
        line_for(screen, new_is_history, new_y).set_attribute("decoration", 1)

        depth = depth_from_bottom(screen.lines, new_is_history, new_y)
        scrolled_by = depth - screen.lines // 2
        scrolled_by = max(0, min(scrolled_by, screen.historybuf.count))
        screen.scroll_to_absolute(scrolled_by)

    screen.mark_as_dirty()
    return ""


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    # args[0] is this script's own path (kitty's argv[0] convention);
    # args[1] is our subcommand; the rest are subcommand-specific.
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return "[]"

    if args[1] == "scan":
        return do_scan(args, w)
    if args[1] == "goto":
        return do_goto(args, w)
    return ""


class SearchNav:
    """Owns all per-window search state: the current match list, the
    line-groups derived from it, which group is "current", and keeping the
    on-screen underline in sync with that. The interactive UI only ever
    calls rescan() (text changed) and navigate() (up/down) -- everything
    else is bookkeeping."""

    def __init__(self, window_id: int):
        self.window_id = window_id
        self.matches: list = []
        self.groups: list = []
        self.current_index: int | None = None
        self._underlined = None  # the group currently underlined on screen, or None
        self.total_lines: int = 0

    def rescan(self, pattern: str, ignorecase: bool) -> None:
        self.matches, screen_lines, scrolled_by, history_count = scan(
            self.window_id, pattern, ignorecase
        )
        self.total_lines = screen_lines + history_count
        self.groups = group_by_line(self.matches)
        if self.groups:
            # Default to whichever line is nearest to wherever you're
            # currently scrolled, not always the most recent line in the
            # whole buffer -- if you're reading old history and search for
            # something, you want the match near where you're looking, not
            # one that yanks you down to the live prompt. "Currently
            # looking at" is approximated as the vertical center of the
            # viewport, matching the same centering goto() uses when it
            # scrolls to a match.
            reference_depth = scrolled_by + screen_lines // 2
            self.current_index = min(
                range(len(self.groups)),
                key=lambda i: abs(
                    depth_from_bottom(screen_lines, self.groups[i][0], self.groups[i][1])
                    - reference_depth
                ),
            )
        else:
            self.current_index = None
        self._apply_current()

    def navigate(self, *, prev: bool) -> None:
        if not self.groups:
            return
        if prev:
            self.current_index = self.current_index - 1 if self.current_index > 0 else len(self.groups) - 1
        else:
            self.current_index = self.current_index + 1 if self.current_index < len(self.groups) - 1 else 0
        self._apply_current()

    def _apply_current(self) -> None:
        new_group = self.groups[self.current_index] if self.current_index is not None else None
        if new_group == self._underlined:
            return
        goto(self.window_id, self._underlined, new_group)
        self._underlined = new_group

    def counter_text(self) -> str:
        if not self.groups:
            return "0/0"
        first_match_index = self.groups[self.current_index][2]
        return f"{first_match_index + 1}/{len(self.matches)}"

    def clear(self) -> None:
        """Remove any underline this instance is responsible for, e.g. on exit."""
        if self._underlined is not None:
            goto(self.window_id, self._underlined, None)
            self._underlined = None

    def recenter(self) -> None:
        """Re-scroll the target window to the current match without
        changing which one is current or touching its underline -- goto()
        with the same group as both "previous" and "new" just re-runs the
        scroll-to-it part (clearing then immediately re-setting the same
        line's decoration is a harmless no-op in between)."""
        if self._underlined is not None:
            goto(self.window_id, self._underlined, self._underlined)


class Search(Handler):
    # Without this, kitty doesn't send us mouse events at all -- it falls
    # back to its own compatibility behavior of synthesizing arrow-key
    # presses for scroll wheel input (for terminal apps with no native mouse
    # support), and the number of key presses per wheel "click" is governed
    # by wheel_scroll_multiplier (default ~5), which is exactly why one
    # wheel click was moving 5 matches at once. buttons_only is enough to
    # receive wheel events directly ourselves; we don't need motion/drag.
    mouse_tracking = MouseTracking.buttons_only

    def __init__(self, cached_values: dict, window_id: int, error: str = "") -> None:
        self.cached_values = cached_values
        self.window_id = window_id
        self.error = error
        self.line_edit = LineEdit()
        last_search = cached_values.get("last_search", "")
        self.line_edit.add_text(last_search)
        self.text_marked = bool(last_search)
        self.mode = cached_values.get("mode", "text")
        self.nav = SearchNav(window_id)
        self.update_prompt()
        # Deliberately no scanning/drawing here -- self.write isn't wired up
        # by the Loop machinery until after __init__ returns. Doing it here
        # crashes the kitten instantly on launch. initialize() is where the
        # first real scan+draw happens.

    def update_prompt(self) -> None:
        self.prompt = "~> " if self.mode == "regex" else "=> "

    def init_terminal_state(self) -> None:
        self.write(set_line_wrapping(False))
        self.write(set_window_title(_("Search")))

    def initialize(self) -> None:
        self.init_terminal_state()
        self.refresh_search()

    def draw_screen(self) -> None:
        self.write(clear_screen())
        input_text = self.line_edit.current_input
        if self.text_marked:
            self.line_edit.current_input = styled(input_text, reverse=True)
        self.line_edit.write(self.write, self.prompt)
        self.line_edit.current_input = input_text
        with cursor(self.write):
            # Centered on the screen, not right after the input text --
            # LineEdit.write() leaves the real cursor at cursor_pos (wherever
            # the edit cursor is *within* the text), so writing anywhere
            # relative to that would risk overwriting text as the cursor
            # moves (see the end-of-text fix below for why that matters);
            # centering on screen width sidesteps it entirely by not
            # depending on cursor_pos or the text's length at all.
            counter_text = self.nav.counter_text()
            target_col = max(0, (self.screen_size.cols - len(counter_text)) // 2)
            self.write("\r")
            if target_col:
                self.write(move_cursor_by(target_col, "right"))
            self.write(counter_text)
        with cursor(self.write):
            # Total scrollback line count, right-aligned to the screen's
            # right edge. Same \r + relative-move trick as the counter
            # above, just targeting a column computed from the right edge
            # instead of the end of the input text.
            total_text = f"{self.nav.total_lines} lines "
            target_col = max(0, self.screen_size.cols - len(total_text))
            self.write("\r")
            if target_col:
                self.write(move_cursor_by(target_col, "right"))
            self.write(total_text)
        if self.error:
            with cursor(self.write):
                self.print("")
                for line in self.error.split("\n"):
                    self.print(line)

    def refresh_search(self) -> None:
        text = self.line_edit.current_input
        ignorecase = text.islower()
        if text:
            ftype = ("i" if ignorecase else "") + self.mode
            apply_native_marker(self.window_id, text, ftype)
        else:
            remove_native_marker(self.window_id)
        our_pattern = text if self.mode == "regex" else re.escape(text)
        self.nav.rescan(our_pattern, ignorecase)
        self.draw_screen()

    def switch_mode(self) -> None:
        self.mode = "text" if self.mode == "regex" else "regex"
        self.cached_values["mode"] = self.mode
        self.update_prompt()
        self.refresh_search()

    def on_text(self, text: str, in_bracketed_paste: bool = False) -> None:
        if self.text_marked:
            self.text_marked = False
            self.line_edit.clear()
        self.line_edit.on_text(text, in_bracketed_paste)
        self.refresh_search()

    def on_key(self, key_event) -> None:
        if (
            self.text_marked
            and key_event.type == EventType.PRESS
            and key_event.key
            not in [
                "TAB", "LEFT_CONTROL", "RIGHT_CONTROL", "LEFT_ALT", "RIGHT_ALT",
                "LEFT_SHIFT", "RIGHT_SHIFT", "LEFT_SUPER", "RIGHT_SUPER",
            ]
        ):
            self.text_marked = False
            self.refresh_search()

        if self.line_edit.on_key(key_event):
            self.refresh_search()
            return

        if key_event.matches("ctrl+u"):
            self.line_edit.clear()
            self.refresh_search()
        elif key_event.matches("ctrl+a"):
            self.line_edit.home()
            self.draw_screen()
        elif key_event.matches("ctrl+e"):
            self.line_edit.end()
            self.draw_screen()
        elif key_event.matches("ctrl+backspace") or key_event.matches("ctrl+w"):
            before, _after = self.line_edit.split_at_cursor()
            try:
                start, _ = reindex(before, SPACE_PATTERN_END, right=True)
            except ValueError:
                start = -1
            try:
                space = before[:start].rindex(" ")
            except ValueError:
                space = 0
            self.line_edit.backspace(len(before) - space)
            self.refresh_search()
        elif key_event.matches("alt+backspace") or key_event.matches("alt+w"):
            before, _after = self.line_edit.split_at_cursor()
            try:
                start, _ = reindex(before, NON_ALPHANUM_PATTERN_END, right=True)
            except ValueError:
                start = -1
            else:
                self.line_edit.backspace(len(before) - start)
                self.refresh_search()
                return
            try:
                start, _ = reindex(before, NON_ALPHANUM_PATTERN, right=True)
            except ValueError:
                self.line_edit.backspace(len(before))
                self.refresh_search()
                return
            self.line_edit.backspace(len(before) - (start + 1))
            self.refresh_search()
        elif key_event.matches("tab"):
            self.switch_mode()
        elif key_event.matches("up"):
            self.nav.navigate(prev=True)
            self.draw_screen()
        elif key_event.matches("down"):
            self.nav.navigate(prev=False)
            self.draw_screen()
        elif key_event.matches("enter"):
            self.quit(0)
        elif key_event.matches("esc"):
            self.quit(1)

    def on_interrupt(self) -> None:
        self.quit(1)

    def on_eot(self) -> None:
        self.quit(1)

    def on_resize(self, screen_size) -> None:
        self.draw_screen()

    def on_mouse_event(self, mouse_event: MouseEvent) -> None:
        if mouse_event.buttons == MouseButton.WHEEL_UP:
            self.nav.navigate(prev=True)
            self.draw_screen()
        elif mouse_event.buttons == MouseButton.WHEEL_DOWN:
            self.nav.navigate(prev=False)
            self.draw_screen()
        else:
            # Let the base class do its own press/release tracking so it
            # can tell a genuine click apart from a drag -- it calls
            # on_click() below only once that's confirmed.
            super().on_mouse_event(mouse_event)

    def on_click(self, mouse_event: MouseEvent) -> None:
        if mouse_event.buttons == MouseButton.LEFT:
            # Re-scroll the target window to the current match without
            # changing which one is current -- e.g. you scrolled the target
            # window away from it (by hand, or its content moved) and want
            # to jump back to where the search currently is.
            self.nav.recenter()
        elif mouse_event.buttons == MouseButton.RIGHT:
            # Same as Esc: cancel, leave the scrollback wherever it is.
            # Currently unreachable with this user's kitty.conf -- their
            # existing "mouse_map right press ungrabbed,grabbed
            # mouse_selection rectangle" claims right-press in both grabbed
            # and ungrabbed states, so kitty marks it handled and never
            # forwards it to us at all. Left in place for if that mapping
            # ever changes.
            self.quit(1)

    def quit(self, return_code: int) -> None:
        self.cached_values["last_search"] = self.line_edit.current_input
        remove_native_marker(self.window_id)
        self.nav.clear()
        if return_code == 0:  # Enter: confirm and jump back to the live prompt
            call_remote_control(["scroll-window", f"--match=id:{self.window_id}", "end"])
        # Esc: cancel, leave the scrollback wherever the search left it
        self.quit_loop(return_code)


def main(args: list[str]) -> None:
    error = ""
    if len(args) < 2 or not args[1].isdigit():
        error = "Error: Window id must be provided as the first argument."
    window_id = int(args[1]) if len(args) >= 2 and args[1].isdigit() else 0

    loop = Loop()
    with cached_values_for("search") as cached_values:
        handler = Search(cached_values, window_id, error)
        loop.loop(handler)
