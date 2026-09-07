#!/usr/bin/env bash
set -eu

_sort_key="id"; _sort_label="time"
_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) shift
            case "${1:-}" in
                time)    _sort_key="id";       _sort_label="time" ;;
                size)    _sort_key="size";     _sort_label="size" ;;
                seeders) _sort_key="seeders";  _sort_label="seeders" ;;
                *) printf 'Usage: nyaazf [-s time|size|seeders] <query>\n' >&2; exit 1 ;;
            esac
            shift ;;
        *) _args+=("$1"); shift ;;
    esac
done
[[ ${#_args[@]} -eq 0 ]] && { printf 'Usage: nyaazf [-s time|size|seeders] <query>\n' >&2; exit 1; }

BASE_URL="${NYAA_URL:-https://nyaa.si}"
_query=$(python3 -c "import sys,urllib.parse; print(urllib.parse.quote_plus(' '.join(sys.argv[1:])))" -- "${_args[@]}")
_cols=$(tput cols 2>/dev/null || echo 120)

_pf=$(mktemp)           # current page number
_pyfmt=$(mktemp)        # Python formatter
_fetch=$(mktemp)        # fetch+format shell script
_ftr=$(mktemp)          # footer builder (Python)
_update_page=$(mktemp)  # updates page file (used via execute-silent, synchronous)
_fetch_reload=$(mktemp) # fetch using page from file (used via reload)
_ftr_cmd=$(mktemp)      # footer-update command (for transform binding)
_cookies=$(mktemp)      # shared curl cookie jar (search + download share session)
echo 1 > "$_pf"
trap 'rm -f "$_pf" "$_pyfmt" "$_fetch" "$_ftr" "$_update_page" "$_fetch_reload" "$_ftr_cmd" "$_cookies"' EXIT

# ── Python formatter (parses HTML search results) ────────────────────────────
cat > "$_pyfmt" << 'PYEOF'
import os, re, sys, unicodedata
from html import unescape
from datetime import datetime, timezone

def vis_len(s):
    w = 0
    for c in s:
        w += 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1
    return w

def vis_truncate(s, max_w):
    if vis_len(s) <= max_w:
        return s
    w, out = 0, []
    for c in s:
        cw = 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1
        if w + cw > max_w - 1:
            break
        out.append(c); w += cw
    return ''.join(out) + '…'

def vis_ljust(s, width):
    return s + ' ' * max(0, width - vis_len(s))

def size_color(size_str):
    try:
        val, unit = size_str.strip().split()
        val = float(val)
        mul = {'B': 1, 'KIB': 1<<10, 'KB': 1000,
               'MIB': 1<<20, 'MB': 10**6,
               'GIB': 1<<30, 'GB': 10**9,
               'TIB': 1<<40, 'TB': 10**12}
        b = val * mul.get(unit.upper(), 1)
    except Exception:
        return '\033[0m'
    if   b < 700e6:  return '\033[31m'
    elif b < 1e9:    return '\033[92m'
    elif b < 3e9:    return '\033[32m'
    elif b < 10e9:   return '\033[34m'
    else:            return '\033[38;5;208m'

CAT_MAP = {
    '0_0': ('---', '\033[0m'),
    '1_0': ('Ani', '\033[33m'),
    '1_1': ('AMV', '\033[35m'),
    '1_2': ('Ani', '\033[92m'),
    '1_3': ('Ani', '\033[31m'),
    '1_4': ('Raw', '\033[90m'),
    '2_0': ('Aud', '\033[0m'),
    '2_1': ('Aud', '\033[31m'),
    '2_2': ('Aud', '\033[33m'),
    '3_0': ('Lit', '\033[0m'),
    '3_1': ('Lit', '\033[92m'),
    '3_2': ('Lit', '\033[33m'),
    '3_3': ('Lit', '\033[90m'),
    '4_0': ('Liv', '\033[0m'),
    '4_1': ('Liv', '\033[33m'),
    '4_2': ('Liv', '\033[93m'),
    '4_3': ('Liv', '\033[96m'),
    '4_4': ('Liv', '\033[90m'),
    '5_0': ('Pic', '\033[0m'),
    '5_1': ('Pic', '\033[95m'),
    '5_2': ('Pic', '\033[35m'),
    '6_0': ('Sof', '\033[0m'),
    '6_1': ('Sof', '\033[34m'),
    '6_2': ('Sof', '\033[94m'),
}

strip_tags = lambda s: re.sub(r'<[^>]+>', '', s).strip()

BASE = 'https://nyaa.si'
MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

data = sys.stdin.read()
rows = re.findall(r'<tr class="(default|success|danger)"[^>]*>(.*?)</tr>', data, re.DOTALL)

if not rows:
    sys.stderr.write('No results found\n'); sys.exit(1)

term_w     = int(os.environ.get('COLUMNS', 120))
RIGHT_W    = 48
CAT_W      = 4
TAG_W      = 4
FZF_CHROME = 8

hdr_title_w = max(10, term_w - FZF_CHROME - CAT_W - RIGHT_W)
title_w     = max(10, hdr_title_w - TAG_W)
hdr = ('Cat'.ljust(4) +
       'Name'.center(hdr_title_w) +
       '    ' + 'Size'.center(12) +
       '    ' + 'Date & Time'.center(18) +
       '    ' + 'Seeds'.rjust(6))
print(hdr)

for tr_class, row in rows:
    cat_m   = re.search(r'href="[^"]*\?c=([0-9_]+)"', row)
    title_m = re.search(r'<a href="/view/\d+"[^>]*title="([^"]*)"', row)
    dl_m    = re.search(r'href="(/download/\d+\.torrent)"', row)
    mag_m   = re.search(r'href="(magnet:[^"]+)"', row)
    ts_m    = re.search(r'data-timestamp="(\d+)"', row)

    if not title_m:
        continue

    cat_id      = cat_m.group(1) if cat_m else '0_0'
    title       = unescape(title_m.group(1))
    torrent_url = BASE + dl_m.group(1) if dl_m else ''
    magnet      = unescape(mag_m.group(1)) if mag_m else ''

    tds = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL)
    if len(tds) < 6:
        continue

    size  = strip_tags(tds[3])
    seeds = strip_tags(tds[5])

    if ts_m:
        dt = datetime.fromtimestamp(int(ts_m.group(1)), tz=timezone.utc)
        date_str = f"{dt.day:02d} {MONTHS[dt.month-1]} {dt.year} {dt.hour:02d}:{dt.minute:02d}"
    else:
        date_str = strip_tags(tds[4])

    tag = 'T' if tr_class == 'success' else 'R' if tr_class == 'danger' else ' '
    try:
        s = int(seeds)
        sc = '\033[32m' if s >= 50 else '\033[33m' if s >= 10 else '\033[31m'
    except ValueError:
        sc = '\033[0m'

    if tag == 'T':
        tag_str = '\033[32m[T]\033[0m '
    elif tag == 'R':
        tag_str = '\033[31m[R]\033[0m '
    else:
        tag_str = '    '

    cat_label, cat_color = CAT_MAP.get(cat_id, ('???', '\033[0m'))
    cat_col = f"{cat_color}{cat_label}\033[0m "

    title_col = vis_ljust(vis_truncate(title, title_w), title_w)
    size_col  = f"{size_color(size)}{size.center(12)}\033[0m"
    date_col  = date_str.ljust(18)
    seed_col  = f"{sc}{seeds.rjust(6)}\033[0m"
    display   = f"{cat_col}{tag_str}{title_col}    {size_col}    {date_col}    {seed_col}"

    view_url  = torrent_url.replace('/download/', '/view/').replace('.torrent', '') if torrent_url else ''
    print(f"{display}\t{magnet}\t{torrent_url}\t{title}\t{size}\t{date_str}\t{seeds}\t{view_url}")
PYEOF

# ── Fetch script (HTML search, supports pagination via p=) ───────────────────
cat > "$_fetch" << FETCHEOF
#!/usr/bin/env bash
set -eu
query="\$1"; page="\$2"; cols="\$3"; sort="\${4:-id}"
raw=\$(curl -fsSL -c "${_cookies}" -b "${_cookies}" \
    -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0' \
    "${BASE_URL}/?q=\${query}&c=0_0&f=0&s=\${sort}&o=desc&p=\${page}") || {
    printf 'curl failed\n' >&2; exit 1
}
[[ -z "\$raw" ]] && { printf 'Empty response\n' >&2; exit 1; }
printf '%s' "\$raw" | COLUMNS="\$cols" python3 "${_pyfmt}"
FETCHEOF
chmod +x "$_fetch"

# ── Page-update script (run via execute-silent: synchronous) ──────────────────
cat > "$_update_page" << UPEOF
#!/usr/bin/env bash
delta=\$1
n=\$(cat "${_pf}")
new_n=\$(( n + delta ))
new_n=\$(( new_n < 1 ? 1 : new_n ))
printf '%d\n' "\$new_n" > "${_pf}"
UPEOF
chmod +x "$_update_page"

# ── Fetch-for-reload (reads page from file, no args needed) ───────────────────
cat > "$_fetch_reload" << FREOF
#!/usr/bin/env bash
page=\$(cat "${_pf}")
raw=\$(curl -fsSL -c "${_cookies}" -b "${_cookies}" \
    -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0' \
    "${BASE_URL}/?q=${_query}&c=0_0&f=0&s=${_sort_key}&o=desc&p=\${page}") || {
    printf 'curl failed\n' >&2; exit 1
}
[[ -z "\$raw" ]] && { printf 'Empty response\n' >&2; exit 1; }
printf '%s' "\$raw" | COLUMNS="${_cols}" python3 "${_pyfmt}"
FREOF
chmod +x "$_fetch_reload"

# ── Footer-update command (for transform binding) ─────────────────────────────
cat > "$_ftr_cmd" << FTRCEOF
#!/usr/bin/env bash
n=\$(cat "${_pf}")
footer=\$("${_ftr}" "\$n")
echo "change-footer(\$footer)"
FTRCEOF
chmod +x "$_ftr_cmd"

# ── Footer builder ────────────────────────────────────────────────────────────
cat > "$_ftr" << FTREOF
#!/usr/bin/env python3
import sys
page = sys.argv[1] if len(sys.argv) > 1 else '1'
cols = ${_cols}

r_text = ('\033[38;2;160;160;160mCTRL+LEFT\033[36m prev   '
          '\033[38;2;160;160;160mCTRL+RIGHT\033[36m next   '
          '\033[38;2;160;160;160mTAB\033[36m select   '
          '\033[38;2;160;160;160mALT+ENTER\033[36m open   '
          '\033[38;2;160;160;160mENTER\033[36m download\033[m')
r_plain = 'CTRL+LEFT prev   CTRL+RIGHT next   TAB select   ALT+ENTER open   ENTER download'

l_text = '\033[38;2;160;160;160mPage \033[36m' + page + '\033[m'
l_vis  = len('Page ') + len(page)

pad = cols - l_vis - len(r_plain) - 7
print(l_text + (' ' * max(1, pad)) + r_text, end='')
FTREOF
chmod +x "$_ftr"


# ── Initial fetch ─────────────────────────────────────────────────────────────
results=$("$_fetch" "$_query" 1 "$_cols" "$_sort_key") || { printf 'No results found.\n' >&2; exit 1; }
[[ -z "$results" ]] && { printf 'No results found.\n' >&2; exit 1; }

_footer=$("$_ftr" 1)

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-}
  --no-sort --exact --reverse --no-hscroll --no-input --height=100% --multi
  --highlight-line
  --scroll-off 7
  --info=inline-right
  --border
  --footer-border=line
  --header-border=horizontal
  --border-label ' NYAA [${_sort_label}]: ${_args[*]} '
  --info-command='echo -e \"\$FZF_POS/\$FZF_MATCH_COUNT(\$FZF_SELECT_COUNT)\"'
  --footer \"$_footer\"
  --pointer '>'
  --gutter '┃'
  --marker '┃'
  --ellipsis '  '
  --scrollbar ''
  --separator ''
  --color fg:242,bg:233,hl:65,fg+:222,bg+:234,hl+:108
  --color info:108,prompt:110,spinner:150,pointer:167,marker:65
"

selected=$(printf '%s\n' "$results" | fzf --ansi \
  --delimiter=$'\t' \
  --with-nth=1 \
  --header-lines=1 \
  --bind "ctrl-right:execute-silent(${_update_page} 1)+reload(${_fetch_reload})+transform(${_ftr_cmd})+first" \
  --bind "ctrl-left:execute-silent(${_update_page} -1)+reload(${_fetch_reload})+transform(${_ftr_cmd})+first" \
  --bind "alt-enter:execute-silent(printf '%s\n' {+8} | xargs -d '\n' -I@ xdg-open @)") || exit 0

mkdir -p ~/Videos
while IFS= read -r line; do
    torrent_url=$(printf '%s' "$line" | cut -f3)
    title=$(printf '%s' "$line" | cut -f4 | tr -d '/\\:*?"<>|')
    curl -fsSL -b "$_cookies" \
        -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0' \
        -H 'Referer: https://nyaa.si/' \
        "$torrent_url" -o ~/Videos/"${title}.torrent"
done <<< "$selected"
