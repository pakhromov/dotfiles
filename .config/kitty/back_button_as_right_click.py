from kittens.tui.handler import result_handler
from kitty.fast_data_types import (
    GLFW_MOUSE_BUTTON_RIGHT,
    PRESS,
    RELEASE,
    get_mouse_data_for_window,
    send_mouse_event,
)


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return
    pos = get_mouse_data_for_window(w.os_window_id, w.tab_id, w.id)
    if pos is None:
        return
    cell_x, cell_y = pos['cell_x'], pos['cell_y']
    in_left = pos['in_left_half_of_cell']
    send_mouse_event(w.screen, cell_x, cell_y, GLFW_MOUSE_BUTTON_RIGHT, PRESS, 0, in_left_half_of_cell=in_left)
    send_mouse_event(w.screen, cell_x, cell_y, GLFW_MOUSE_BUTTON_RIGHT, RELEASE, 0, in_left_half_of_cell=in_left)


def main(args):
    return None
