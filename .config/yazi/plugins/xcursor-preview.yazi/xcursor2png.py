#!/usr/bin/env python3
"""Parse an Xcursor file and stream a frame as PNG to stdout.

Usage: xcursor2png.py <input_path> <frame_index>

stdout : raw PNG binary
stderr : one line prefixed with XCMETA: containing space-separated values:
         width height xhot yhot delay frame_shown total_frames sizes...
"""

import sys
import struct
import io
from PIL import Image


def parse_xcursor(path):
    with open(path, "rb") as f:
        data = f.read()

    if data[:4] != b"Xcur":
        raise ValueError("Not an Xcursor file")

    header_size, _version, ntoc = struct.unpack_from("<III", data, 4)

    IMAGE_TYPE = 0xFFFD0002
    images = []

    for i in range(ntoc):
        toc_off = header_size + i * 12
        chunk_type, _subtype, position = struct.unpack_from("<III", data, toc_off)
        if chunk_type != IMAGE_TYPE:
            continue

        (ichunk_header, _type, nom_size, _ver,
         width, height, xhot, yhot, delay) = struct.unpack_from("<IIIIIIIII", data, position)

        px_off = position + ichunk_header
        n = width * height
        raw = struct.unpack_from(f"<{n}I", data, px_off)

        images.append({
            "nom_size": nom_size,
            "width": width, "height": height,
            "xhot": xhot, "yhot": yhot,
            "delay": delay, "raw": raw,
        })

    return images


def to_pil(img_data):
    w, h = img_data["width"], img_data["height"]
    buf = bytearray(w * h * 4)
    for i, val in enumerate(img_data["raw"]):
        base = i * 4
        buf[base]     = (val >> 16) & 0xFF  # R
        buf[base + 1] = (val >>  8) & 0xFF  # G
        buf[base + 2] =  val        & 0xFF  # B
        buf[base + 3] = (val >> 24) & 0xFF  # A
    return Image.frombytes("RGBA", (w, h), bytes(buf))


def main():
    if len(sys.argv) < 3:
        print("Usage: xcursor2png.py <input> <frame_index>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    frame_index = int(sys.argv[2])

    images = parse_xcursor(input_path)
    if not images:
        print("No images found in cursor file", file=sys.stderr)
        sys.exit(1)

    max_size = max(img["nom_size"] for img in images)
    frames = [img for img in images if img["nom_size"] == max_size]
    total_frames = len(frames)
    frame_index = frame_index % total_frames
    frame = frames[frame_index]

    img = to_pil(frame)

    # Scale up with nearest-neighbour so small cursors look crisp
    w, h = img.size
    scale = max(1, 128 // max(w, h))
    if scale > 1:
        img = img.resize((w * scale, h * scale), Image.NEAREST)

    # PNG binary → stdout
    buf = io.BytesIO()
    img.save(buf, "PNG")
    sys.stdout.buffer.write(buf.getvalue())

    # Metadata → stderr (XCMETA: prefix so we can parse it separately)
    sizes = sorted(set(img["nom_size"] for img in images))
    print(
        f"XCMETA: {frame['width']} {frame['height']} "
        f"{frame['xhot']} {frame['yhot']} {frame['delay']} "
        f"{frame_index} {total_frames} {' '.join(str(s) for s in sizes)}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
