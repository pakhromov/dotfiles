#!/usr/bin/env python3
"""Generate ~/.local/bin/icons/unicode.txt from Python's built-in unicodedata.
Re-run after a Python upgrade to pick up newer Unicode versions.
Only includes blocks useful for UI elements."""

import unicodedata
import os

out_path = os.path.expanduser('~/.local/bin/icons/unicode.txt')

RANGES = [
    (0x2000, 0x206F, 'General Punctuation'),
    (0x2070, 0x209F, 'Superscripts and Subscripts'),
    (0x20A0, 0x20CF, 'Currency Symbols'),
    (0x2150, 0x218F, 'Number Forms'),
    (0x2190, 0x21FF, 'Arrows'),
    (0x2200, 0x22FF, 'Mathematical Operators'),
    (0x2300, 0x23FF, 'Miscellaneous Technical'),
    (0x2460, 0x24FF, 'Enclosed Alphanumerics'),
    (0x2500, 0x257F, 'Box Drawing'),
    (0x2580, 0x259F, 'Block Elements'),
    (0x25A0, 0x25FF, 'Geometric Shapes'),
    (0x2600, 0x26FF, 'Miscellaneous Symbols'),
    (0x2700, 0x27BF, 'Dingbats'),
    (0x27F0, 0x27FF, 'Supplemental Arrows-A'),
    (0x2800, 0x28FF, 'Braille Patterns'),
    (0x2900, 0x297F, 'Supplemental Arrows-B'),
    (0x2A00, 0x2AFF, 'Supplemental Mathematical Operators'),
    (0x2B00, 0x2BFF, 'Miscellaneous Symbols and Arrows'),
    (0x1FA00, 0x1FA6F, 'Chess Symbols'),
]

written = 0
skipped = 0

with open(out_path, 'w') as f:
    for (start, end, block) in RANGES:
        for cp in range(start, end + 1):
            try:
                char = chr(cp)
                cat  = unicodedata.category(char)
                if cat in ('Cc', 'Cs', 'Co', 'Cn'):
                    skipped += 1
                    continue
                name = unicodedata.name(char)
                f.write(f"{char}  {name.lower()}\n")
                written += 1
            except ValueError:
                skipped += 1

print(f"Written: {written:,}  Skipped: {skipped:,}")
print(f"Output:  {out_path}")
print(f"Unicode: {unicodedata.unidata_version}")
