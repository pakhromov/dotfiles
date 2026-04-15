#!/usr/bin/env python3
"""
modchars_ft.py  –  replace specific character glyphs in a font with ones from a donor font

Usage:
    python3 modchars_ft.py <target_font> <donor_font> <output_file> <family_name>

Example:
    python3 modchars_ft.py \
        output/ComicShannsLigaNerdFont-Regular.otf \
        /usr/share/fonts/TTF/RecMonoCasualNerdFont-Regular.ttf \
        output/ComicShannsLigaModNerdFont-Regular.otf \
        "ComicShannsLigaMod Nerd Font"
"""

import sys
import copy
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.qu2cuPen import Qu2CuPen
from fontTools.pens.transformPen import TransformPen

# Unicode codepoints of characters to replace
REPLACE_CHARS_MOD = [
    0x003C,  # <
    0x003E,  # >
    0x002F,  # /
    0x007C,  # |
    0x005C,  # \
    0x003D,  # =
    0x002D,  # -
    0x002B,  # +
    0x005F,  # _
    0x0023,  # #
]

REPLACE_CHARS_MOD2 = REPLACE_CHARS_MOD + [
    0x0030,  # 0
    0x0031,  # 1
    0x0032,  # 2
    0x0033,  # 3
    0x0034,  # 4
    0x0035,  # 5
    0x0036,  # 6
    0x0037,  # 7
    0x0038,  # 8
    0x0039,  # 9
    0x0024,  # $
    0x0028,  # (
    0x0029,  # )
    0x005B,  # [
    0x005D,  # ]
    0x007B,  # {
    0x007D,  # }
]

REPLACE_CHARS = REPLACE_CHARS_MOD  # default


def replace_glyph_cff(src_font, dst_font, src_name, dst_name, dst_advance, y_scale):
    """Replace an existing CFF glyph's outline with one from the donor font."""
    src_width = src_font['hmtx'].metrics[src_name][0]
    x_scale = dst_advance / src_width if src_width else 1.0

    dst_cff = dst_font['CFF '].cff
    top = dst_cff.topDictIndex[0]
    css = top.CharStrings

    pen = T2CharStringPen(dst_advance, None)
    scaled = TransformPen(pen, (x_scale, 0, 0, y_scale, 0, 0))
    qu2cu = Qu2CuPen(scaled, max_err=1.0, all_cubic=True)
    src_font.getGlyphSet()[src_name].draw(qu2cu)

    cs = pen.getCharString()
    cs.private = top.Private

    # Replace the charstring in-place at its existing index
    idx = css.charStrings[dst_name]
    css.charStringsIndex[idx] = cs

    dst_font['hmtx'].metrics[dst_name] = (dst_advance, 0)


def update_name_records(font, family_name):
    """Update the name table so the font appears as a distinct family."""
    name_table = font['name']

    def get_name(name_id):
        for rec in name_table.names:
            if rec.nameID == name_id:
                return rec.toUnicode()
        return None

    def set_name(name_id, value):
        found = False
        for rec in name_table.names:
            if rec.nameID == name_id:
                rec.string = value
                found = True
        if not found:
            name_table.setName(value, name_id, 3, 1, 0x0409)

    style = get_name(2) or 'Regular'
    ps_family = family_name.replace(' ', '')
    ps_style  = style.replace(' ', '')
    full_name = family_name if style == 'Regular' else f"{family_name} {style}"
    ps_name   = ps_family if style == 'Regular' else f"{ps_family}-{ps_style}"

    set_name(1,  family_name)
    set_name(4,  full_name)
    set_name(6,  ps_name)
    set_name(16, family_name)

    if 'CFF ' in font:
        cff = font['CFF '].cff
        cff.fontNames = [ps_name]
        top = cff.topDictIndex[0]
        top.FullName   = full_name
        top.FamilyName = family_name
        top.FontName   = ps_name


def modchars(target_path, donor_path, output_path, family_name):
    print(f"Target : {target_path}")
    print(f"Donor  : {donor_path}")
    print(f"Output : {output_path}")
    print(f"Family : {family_name}")

    dst = TTFont(target_path)
    src = TTFont(donor_path)

    dst_advance = dst['hmtx'].metrics['m'][0]

    dst_cap = dst['OS/2'].sCapHeight
    src_cap = src['OS/2'].sCapHeight
    if dst_cap and src_cap:
        y_scale = dst_cap / src_cap
        print(f"  y scale = {dst_cap}/{src_cap} (cap height) = {y_scale:.4f}")
    else:
        y_scale = dst['head'].unitsPerEm / src['head'].unitsPerEm
        print(f"  y scale = UPM fallback = {y_scale:.4f}")

    dst_cmap = dst.getBestCmap()
    src_cmap = src.getBestCmap()

    replaced = []
    skipped  = []
    for cp in REPLACE_CHARS:
        char = chr(cp)
        if cp not in dst_cmap:
            skipped.append(f"U+{cp:04X} ({char!r}) not in target cmap")
            continue
        if cp not in src_cmap:
            skipped.append(f"U+{cp:04X} ({char!r}) not in donor cmap")
            continue

        dst_name = dst_cmap[cp]
        src_name = src_cmap[cp]

        if src_name not in src['hmtx'].metrics:
            skipped.append(f"U+{cp:04X} ({char!r}) donor glyph {src_name!r} missing from hmtx")
            continue

        try:
            replace_glyph_cff(src, dst, src_name, dst_name, dst_advance, y_scale)
            replaced.append(f"U+{cp:04X} ({char!r}): {src_name} → {dst_name}")
        except Exception as e:
            skipped.append(f"U+{cp:04X} ({char!r}) error: {e}")

    print(f"  Replaced {len(replaced)} glyphs:")
    for r in replaced:
        print(f"    {r}")
    if skipped:
        print(f"  Skipped {len(skipped)}:")
        for s in skipped:
            print(f"    {s}")

    update_name_records(dst, family_name)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    dst.save(output_path)
    size = Path(output_path).stat().st_size
    print(f"  Saved: {size:,} bytes")


if __name__ == '__main__':
    if len(sys.argv) not in (5, 6):
        print(__doc__)
        sys.exit(1)
    char_set = sys.argv[5] if len(sys.argv) == 6 else 'mod'
    if char_set == 'mod2':
        REPLACE_CHARS[:] = REPLACE_CHARS_MOD2
    modchars(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
