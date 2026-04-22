import os
import re
import signal

CONF_PATH = os.path.expanduser('~/.config/kitty/kitty.conf')

FONTS = [
    ('family="ComicShannsLigaPure Nerd Font"', 13.2),
    ('family="ComicShannsLiga Nerd Font"', 13.2),
    ('family="ComicShannsLigaMod Nerd Font"', 13.2),
    ('family="SeriousShannsLigaPure Nerd Font"', 14.3),
    ('family="SeriousShannsLiga Nerd Font"', 14.3),
    ('family="SeriousShannsLigaMod Nerd Font"', 14.3),
]

#('family="Maple Mono NF"', 12.0),
#('family="RecMonoCasual Nerd Font"', 12.6),
#('family="LigaMonaco Nerd Font"', 12.0),
#('family="FantasqueSansM Nerd Font"', 13.8),
#SpaceMono
#IntoneMono
#Mononoki
#CaskaydiaCove
#Google Sans Code
#UbuntuMono
#CodeNewRoman
#FiraCode
#RecMonoLinear
#RecMonoSmCasual
#ZedMono


def main(args):
    with open(CONF_PATH) as f:
        content = f.read()

    m = re.search(r'^font_family\s+(.+)$', content, re.MULTILINE)
    current_value = m.group(1).strip() if m else None

    m = re.search(r'^font_size\s+(\S+)', content, re.MULTILINE)
    current_size = float(m.group(1)) if m else None

    try:
        idx = next(i for i, (val, size) in enumerate(FONTS) if val == current_value and size == current_size)
    except StopIteration:
        idx = -1
    direction = -1 if len(args) > 1 and args[1] == 'prev' else 1
    next_value, next_size = FONTS[(idx + direction) % len(FONTS)]

    content = re.sub(
        r'^(font_family\s+).+$',
        lambda m: m.group(1) + next_value,
        content,
        flags=re.MULTILINE,
    )
    content = re.sub(
        r'^font_size\s+\S+',
        f'font_size        {next_size}',
        content,
        flags=re.MULTILINE,
    )

    with open(CONF_PATH, 'w') as f:
        f.write(content)

    return next_value


def handle_result(args, answer, target_window_id, boss):
    if answer:
        os.kill(os.getpid(), signal.SIGUSR1)
