#!/usr/bin/env bash
#
# Renders art/ascii.txt into every image this repo ships:
#
#   theme/andrei-nita/backgrounds/1-andrei-nita.png   3840x2160 wallpaper
#   theme/andrei-nita/preview.png                     1920x1080 theme picker thumbnail
#   lockscreen/andrei.lock/logo.png                   lock screen logo (art + glow padding)
#   boot/andrei-logo.png                              Plymouth disk-unlock logo
#
# Each block glyph (█ ▀ ▄ ▌) is drawn as a pixel-snapped rectangle rather than
# rendered as text, so neighbouring glyphs never show anti-aliased seams.
#
# Override the gradient with STOPS, e.g.:
#   STOPS="#ff0080 #7928ca" ./art/render.sh
#
# Requires python3 and ImageMagick 7 (`magick`).

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
read -r -a stops <<<"${STOPS:-#7c3aed #9d4edd #c026d3}"

# Cell size of one character at wallpaper scale. 19x42 keeps the terminal-like
# ~1:2.2 aspect and makes the art ~55% of a 3840px-wide screen.
cell_w=19
cell_h=42
glow_pad=200

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

size=$(python3 - "$root/art/ascii.txt" "$work/art.mvg" "$cell_w" "$cell_h" <<'EOF'
import sys

src, out, cw, ch = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
lines = open(src, encoding="utf-8").read().rstrip("\n").split("\n")
half, half_w = ch // 2, cw // 2

rects = []
for row, line in enumerate(lines):
    y = row * ch
    for col, glyph in enumerate(line):
        x = col * cw
        if glyph == "█":
            rects.append((x, y, x + cw - 1, y + ch - 1))
        elif glyph == "▀":
            rects.append((x, y, x + cw - 1, y + half - 1))
        elif glyph == "▄":
            rects.append((x, y + half, x + cw - 1, y + ch - 1))
        elif glyph == "▌":
            rects.append((x, y, x + half_w - 1, y + ch - 1))
        elif glyph != " ":
            sys.exit(f"unsupported glyph {glyph!r} at line {row + 1}, column {col + 1}")

width = max(len(line) for line in lines) * cw
height = len(lines) * ch
with open(out, "w") as f:
    f.write(f"viewbox 0 0 {width} {height}\nfill white\n")
    f.writelines(f"rectangle {a},{b} {c},{d}\n" for a, b, c, d in rects)
print(f"{width}x{height}")
EOF
)

gradient_inputs=()
for stop in "${stops[@]}"; do gradient_inputs+=("xc:$stop"); done

# Art mask -> horizontal gradient clipped to the mask -> soft glow behind it.
magick -size "$size" xc:black -draw @"$work/art.mvg" "$work/mask.png"
magick "${gradient_inputs[@]}" +append -filter triangle -resize "$size!" "$work/gradient.png"
magick "$work/gradient.png" "$work/mask.png" -alpha off -compose CopyOpacity -composite "$work/art.png"
magick "$work/art.png" -bordercolor none -border "$glow_pad" \
  \( +clone -blur 0x40 -channel A -evaluate multiply 0.6 +channel \) \
  +swap -compose over -composite +repage "$work/logo.png"

png=(-depth 8 -define png:compression-level=9)

magick "$work/logo.png" "${png[@]}" "$root/lockscreen/andrei.lock/logo.png"
magick -size 3840x2160 xc:black "$work/logo.png" -gravity center -compose over -composite \
  -alpha off "${png[@]}" "$root/theme/andrei-nita/backgrounds/1-andrei-nita.png"
magick "$root/theme/andrei-nita/backgrounds/1-andrei-nita.png" -resize 1920x1080 \
  "${png[@]}" "$root/theme/andrei-nita/preview.png"
# Plymouth draws the logo at its native size, so shrink it to fit a 1080p screen.
magick "$work/logo.png" -filter box -resize 1048x "${png[@]}" "$root/boot/andrei-logo.png"

echo "Rendered art ($size) with gradient: ${stops[*]}"
