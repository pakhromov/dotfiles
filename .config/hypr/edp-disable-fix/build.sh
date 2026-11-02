#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"

# The installed version.h can contain older dependency versions. Use the
# installed dependency versions when constructing Hyprland's plugin ABI hash.
python3 - <<'PY'
import pathlib
import subprocess

dependencies = {
    "AQUAMARINE": "aquamarine",
    "HYPRUTILS": "hyprutils",
    "HYPRGRAPHICS": "hyprgraphics",
    "HYPRCURSOR": "hyprcursor",
    "HYPRLANG": "hyprlang",
}
lines = ["#pragma once", "#include <hyprland/src/version.h>"]
for macro, package in dependencies.items():
    version = subprocess.check_output(["pkg-config", "--modversion", package], text=True).strip()
    lines += [f"#undef {macro}_VERSION", f'#define {macro}_VERSION "{version}"']
pathlib.Path("version-compat.hpp").write_text("\n".join(lines) + "\n")
PY

# Replace the library atomically so rebuilding cannot corrupt a loaded copy.
trap 'rm -f libedp-disable-fix.so.new' EXIT
g++ -std=c++23 -O2 -fPIC -shared -fno-gnu-unique -Wall -Wextra \
    -include ./version-compat.hpp \
    $(pkg-config --cflags hyprland aquamarine) \
    main.cpp -o libedp-disable-fix.so.new \
    $(pkg-config --libs aquamarine) -ldl
mv -f libedp-disable-fix.so.new libedp-disable-fix.so
