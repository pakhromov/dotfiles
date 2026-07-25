#!/usr/bin/env python3
import time
from wayfire import WayfireSocket

sock = WayfireSocket()
sock.watch(["view-mapped", "view-title-changed", "view-app-id-changed"])

start = time.monotonic()
while True:
    msg = sock.read_next_event()
    ev = msg.get("event")
    view = msg.get("view")
    if view is None:
        continue
    t = round(time.monotonic() - start, 2)
    print(f"t={t:>6}  {ev:<22} id={view['id']:<4} app-id={view['app-id']!r:<20} title={view['title']!r}")
