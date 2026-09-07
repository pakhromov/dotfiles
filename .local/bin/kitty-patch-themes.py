#!/usr/bin/env python3
# Downloads and patches the kitty themes zip.
# Usage: kitty-patch-themes [flags]
#   -b   override background (#111111)
#   -w   override white/color7 (#a0a0a0)
#   -f   override foreground (#a0a0a0)
#   -d   remove blurb/description
#   -r   restore originals (no patching)
#   combine freely: -bwfd (default)
# Then open the theme kitten with: kitten themes --cache-age -1

import sys
import os
import re
import json
import zipfile
import shutil
import urllib.request
from datetime import datetime, timezone

THEMES_URL = 'https://codeload.github.com/kovidgoyal/kitty-themes/zip/master'
CACHE_PATH = os.path.expanduser('~/.cache/kitty/kitty-themes.zip')

BG_COLOR    = '#111111'
WHITE_COLOR = '#a0a0a0'
FG_COLOR    = '#a0a0a0'

flag = sys.argv[1] if len(sys.argv) > 1 else '-bwfd'
if flag != '-r' and not re.fullmatch(r'-[bwfdr]+', flag):
    print(f'Usage: {sys.argv[0]} [-b|-w|-f|-d|-r|combinations]', file=sys.stderr)
    sys.exit(1)

patch_bg    = 'b' in flag
patch_white = 'w' in flag
patch_fg    = 'f' in flag
strip_desc  = 'd' in flag
restore     = flag == '-r'

bg_line    = re.compile(r'^\s*background\s+\S+',  re.IGNORECASE)
white_line = re.compile(r'^\s*color7\s+\S+',      re.IGNORECASE)
fg_line    = re.compile(r'^\s*foreground\s+\S+',  re.IGNORECASE)
blurb_start   = re.compile(r'^##\s*blurb\s*:', re.IGNORECASE)
author_line   = re.compile(r'^##\s*author\s*:', re.IGNORECASE)
meta_key      = re.compile(r'^##\s*(name|license|upstream)\s*:', re.IGNORECASE)

print('Downloading themes...', flush=True)
tmp_dl = CACHE_PATH + '.dl'

req = urllib.request.Request(THEMES_URL)
with urllib.request.urlopen(req) as resp:
    etag = resp.headers.get('ETag', '')
    with open(tmp_dl, 'wb') as f:
        f.write(resp.read())

comment = json.dumps({
    'Etag': etag,
    'Timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
})

tmp_patch = CACHE_PATH + '.tmp'
patched_bg = patched_white = patched_fg = stripped_desc = 0

with zipfile.ZipFile(tmp_dl, 'r') as zin, \
     zipfile.ZipFile(tmp_patch, 'w', compression=zipfile.ZIP_DEFLATED) as zout:
    zout.comment = comment.encode()
    for item in zin.infolist():
        data = zin.read(item.filename)
        if item.filename.endswith('.conf') and not restore:
            lines = data.decode('utf-8', errors='replace').splitlines(keepends=True)
            new_lines = []
            in_blurb = False
            for line in lines:
                stripped = line.lstrip()
                # Blurb stripping
                if strip_desc:
                    if blurb_start.match(line):
                        in_blurb = True
                        stripped_desc += 1
                        continue
                    if in_blurb:
                        if line.startswith('## ') and not meta_key.match(line):
                            continue  # blurb continuation
                        in_blurb = False
                    if author_line.match(line):
                        stripped_desc += 1
                        continue
                # Color patching
                if stripped.startswith('#'):
                    new_lines.append(line)
                    continue
                if patch_bg and bg_line.match(line):
                    new_lines.append(f'background {BG_COLOR}\n')
                    patched_bg += 1
                elif patch_white and white_line.match(line):
                    new_lines.append(f'color7 {WHITE_COLOR}\n')
                    patched_white += 1
                elif patch_fg and fg_line.match(line):
                    new_lines.append(f'foreground {FG_COLOR}\n')
                    patched_fg += 1
                else:
                    new_lines.append(line)
            data = ''.join(new_lines).encode('utf-8')
        if item.filename.endswith('themes.json') and strip_desc and not restore:
            entries = json.loads(data.decode('utf-8'))
            for entry in entries:
                entry['blurb'] = '\n\n\n\n\n'
                entry.pop('author', None)
            data = json.dumps(entries).encode('utf-8')
        zout.writestr(item.filename, data)

os.remove(tmp_dl)
shutil.move(tmp_patch, CACHE_PATH)

if patch_bg:    print(f'Patched {patched_bg} themes: background → {BG_COLOR}')
if patch_white: print(f'Patched {patched_white} themes: color7 → {WHITE_COLOR}')
if patch_fg:    print(f'Patched {patched_fg} themes: foreground → {FG_COLOR}')
if strip_desc:  print(f'Stripped descriptions from {stripped_desc} themes')
if restore:     print('Restored originals (no patching)')
