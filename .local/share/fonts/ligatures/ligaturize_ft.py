#!/usr/bin/env python3
"""
ligaturize_ft.py  –  fonttools-based ligaturizer (no fontforge needed)

Copies the CALT GSUB ligature structure and ligature glyphs from a source
font into a target font, producing a new font file with ligatures.

Usage:
    python3 ligaturize_ft.py <target_font> <source_font> <output_file> <family_name>

Example:
    python3 ligaturize_ft.py \
        /usr/share/fonts/OTF/ComicShannsMonoNerdFont-Regular.otf \
        /usr/share/fonts/TTF/RecMonoCasualNerdFont-Regular.ttf \
        output/ComicShanns+RecMono-Regular.otf \
        "ComicShanns + RecMono"
"""

import sys
import copy
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.ttGlyphPen import TTGlyphPointPen
from fontTools.pens.qu2cuPen import Qu2CuPen
from fontTools.pens.transformPen import TransformPen
from fontTools import otlLib


def collect_calt_lookup_indices(gsub):
    """Return the set of all lookup indices used by the CALT feature (direct + sub-lookups)."""
    calt_direct = set()
    for feat_rec in gsub.FeatureList.FeatureRecord:
        if feat_rec.FeatureTag == 'calt':
            calt_direct.update(feat_rec.Feature.LookupListIndex)

    all_indices = set(calt_direct)
    for idx in list(calt_direct):
        lk = gsub.LookupList.Lookup[idx]
        if lk.LookupType == 6:
            for sub in lk.SubTable:
                if hasattr(sub, 'SubstLookupRecord'):
                    for rec in sub.SubstLookupRecord:
                        all_indices.add(rec.LookupListIndex)
    return all_indices


def _collect_otl_strings(obj, names, _seen=None):
    """Recursively walk an OTL subtable object and collect all string values (glyph names)."""
    if _seen is None:
        _seen = set()
    oid = id(obj)
    if oid in _seen:
        return
    _seen.add(oid)
    for attr in vars(obj):
        val = getattr(obj, attr)
        if isinstance(val, str):
            names.add(val)
        elif isinstance(val, list):
            for item in val:
                if isinstance(item, str):
                    names.add(item)
                elif hasattr(item, '__dict__'):
                    _collect_otl_strings(item, names, _seen)
        elif isinstance(val, dict):
            for k, v in val.items():
                if isinstance(k, str):
                    names.add(k)
                if isinstance(v, str):
                    names.add(v)
                elif isinstance(v, list):
                    for i in v:
                        if isinstance(i, str):
                            names.add(i)
                        elif hasattr(i, '__dict__'):
                            _collect_otl_strings(i, names, _seen)
                elif hasattr(v, '__dict__'):
                    _collect_otl_strings(v, names, _seen)
        elif hasattr(val, '__dict__') and not isinstance(val, type):
            _collect_otl_strings(val, names, _seen)


def collect_gsub_glyph_names(gsub, lookup_indices):
    """Return the set of all glyph names referenced in the given lookups (all types)."""
    names = set()
    for idx in lookup_indices:
        lk = gsub.LookupList.Lookup[idx]
        for sub in lk.SubTable:
            inner = getattr(sub, 'ExtSubTable', sub)
            _collect_otl_strings(inner, names)
    return names


def _add_blank_glyph_cff(dst_font, glyph_name, dst_advance):
    """Add an empty (invisible) glyph to a CFF font."""
    from fontTools.pens.t2CharStringPen import T2CharStringPen
    cff = dst_font['CFF '].cff
    top = cff.topDictIndex[0]
    css = top.CharStrings
    pen = T2CharStringPen(dst_advance, None)
    pen.endPath()  # no contours
    cs = pen.getCharString()
    cs.private = top.Private
    idx = len(css.charStrings)
    css.charStrings[glyph_name] = idx
    css.charStringsIndex.append(cs)
    dst_font['hmtx'].metrics[glyph_name] = (dst_advance, 0)


def copy_glyph_cff(src_font, dst_font, glyph_name, dst_advance, y_scale):
    """Copy one glyph from a TTF source into a CFF/OTF destination, scaling x to dst_advance."""
    src_width = src_font['hmtx'].metrics[glyph_name][0]
    if src_width == 0:
        x_scale = 1.0
    else:
        x_scale = dst_advance / src_width

    dst_cff = dst_font['CFF '].cff
    top     = dst_cff.topDictIndex[0]
    css     = top.CharStrings

    pen = T2CharStringPen(dst_advance, None)
    scaled = TransformPen(pen, (x_scale, 0, 0, y_scale, 0, 0))
    qu2cu  = Qu2CuPen(scaled, max_err=1.0, all_cubic=True)
    src_font.getGlyphSet()[glyph_name].draw(qu2cu)

    cs = pen.getCharString()
    cs.private = top.Private

    # Add to CFF CharStrings (css.charStrings is the name→index dict,
    # css.charStringsIndex is the backing list of T2CharString objects)
    idx = len(css.charStrings)
    css.charStrings[glyph_name] = idx
    css.charStringsIndex.append(cs)

    dst_font['hmtx'].metrics[glyph_name] = (dst_advance, 0)


def copy_glyph_ttf(src_font, dst_font, glyph_name, dst_advance, y_scale):
    """Copy one glyph from a TTF source into a TTF destination, scaling x to dst_advance."""
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    src_width = src_font['hmtx'].metrics[glyph_name][0]
    x_scale = dst_advance / src_width if src_width else 1.0

    pen = TTGlyphPen(dst_font.getGlyphSet())
    scaled = TransformPen(pen, (x_scale, 0, 0, y_scale, 0, 0))
    src_font.getGlyphSet()[glyph_name].draw(scaled)
    dst_font['glyf'][glyph_name] = pen.glyph()
    dst_font['hmtx'].metrics[glyph_name] = (dst_advance, 0)


def add_gsub_calt(dst_font, src_gsub):
    """Deep-copy the full GSUB from src and install it in dst_font."""
    import copy
    from fontTools.ttLib import newTable
    gsub_table = newTable('GSUB')
    gsub_table.table = copy.deepcopy(src_gsub)
    dst_font['GSUB'] = gsub_table


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
            name_table.setName(value, name_id, 3, 1, 0x0409)  # Windows, BMP, English

    # Read existing style name (e.g. "Bold", "Italic", "Bold Italic")
    style = get_name(2) or 'Regular'

    # Derive PS-compatible names (no spaces, special chars → safe)
    ps_family = family_name.replace(' ', '').replace('+', 'Plus')
    ps_style  = style.replace(' ', '')

    full_name = family_name if style == 'Regular' else f"{family_name} {style}"
    ps_name   = ps_family if style == 'Regular' else f"{ps_family}-{ps_style}"

    set_name(1,  family_name)   # Family name
    set_name(4,  full_name)     # Full name
    set_name(6,  ps_name)       # PostScript name
    set_name(16, family_name)   # Preferred family (for font pickers)

    # Update CFF font name if present
    if 'CFF ' in font:
        cff = font['CFF '].cff
        cff.fontNames = [ps_name]
        top = cff.topDictIndex[0]
        top.FullName   = full_name
        top.FamilyName = family_name
        top.FontName   = ps_name


def ligaturize(target_path, source_path, output_path, family_name):
    print(f"Target : {target_path}")
    print(f"Source : {source_path}")
    print(f"Output : {output_path}")
    print(f"Family : {family_name}")

    dst = TTFont(target_path)
    src = TTFont(source_path)

    is_cff = 'CFF ' in dst

    # Get destination em-advance (width of 'm' = one character width)
    dst_advance = dst['hmtx'].metrics['m'][0]
    print(f"  dst advance (em width) = {dst_advance}")

    # Compute y scale so ligature heights match the target font.
    # Cap height is the most representative metric for operator/ligature glyphs;
    # fall back to UPM ratio if either font doesn't declare a cap height.
    dst_cap = dst['OS/2'].sCapHeight
    src_cap = src['OS/2'].sCapHeight
    if dst_cap and src_cap:
        y_scale = dst_cap / src_cap
        print(f"  y scale = {dst_cap}/{src_cap} (cap height) = {y_scale:.4f}")
    else:
        dst_upm = dst['head'].unitsPerEm
        src_upm = src['head'].unitsPerEm
        y_scale = dst_upm / src_upm
        print(f"  y scale = {dst_upm}/{src_upm} (UPM fallback) = {y_scale:.4f}")

    # Identify which glyphs to copy from source
    src_gsub = src['GSUB'].table
    all_indices = set(range(len(src_gsub.LookupList.Lookup)))
    needed = collect_gsub_glyph_names(src_gsub, all_indices)
    dst_existing = set(dst.getGlyphOrder())
    to_copy = needed - dst_existing
    print(f"  Copying {len(to_copy)} glyphs from source...")

    # Add new glyph names to glyph order
    new_order = list(dst.getGlyphOrder()) + sorted(to_copy)
    dst.setGlyphOrder(new_order)

    # Copy glyphs
    copied = []
    failed = []
    for glyph_name in sorted(to_copy):
        if glyph_name not in src['hmtx'].metrics:
            print(f"    WARNING: {glyph_name} not in source hmtx, skipping")
            continue
        try:
            if is_cff:
                copy_glyph_cff(src, dst, glyph_name, dst_advance, y_scale)
            else:
                copy_glyph_ttf(src, dst, glyph_name, dst_advance, y_scale)
            copied.append(glyph_name)
        except Exception as e:
            failed.append(glyph_name)
            # Add a blank placeholder so hmtx and GSUB refs don't crash on save
            if is_cff:
                _add_blank_glyph_cff(dst, glyph_name, dst_advance)
            copied.append(glyph_name)

    if failed:
        print(f"    ({len(failed)} glyphs replaced with blanks due to copy errors)")

    # For CFF fonts, the compiler uses top.charset (CFF glyph order) to decide
    # which charstrings to write. Update it to include the new glyphs.
    if is_cff:
        top = dst['CFF '].cff.topDictIndex[0]
        top.charset = top.charset + copied

    # Copy full GSUB from source
    n_src = len(src_gsub.LookupList.Lookup)
    print(f"  Copying GSUB ({n_src} lookups)...")
    add_gsub_calt(dst, src_gsub)

    # Update metadata
    update_name_records(dst, family_name)

    # Save
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    dst.save(output_path)
    size = Path(output_path).stat().st_size
    print(f"  Saved: {size:,} bytes")


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    ligaturize(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
