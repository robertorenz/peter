#!/usr/bin/env python3
"""Convert peterstartup.png into a C64 multicolor-bitmap startup screen.

Output: build/splash.inc  (dasm source, org'd into VIC bank 2)
            $8000  splashCol  1000 bytes  color-RAM nibbles (copied to $d800)
            $8400  splashScr  1000 bytes  screen RAM (%01/%10 colors)
            $a000  splashBmp  8000 bytes  bitmap
            SPLASH_BG equ <n>             shared %00 background color
        build/splash_preview.png          eyeball render

The portrait poster is fit to the full 200-pixel height and pillar-boxed
into the 160x200 fat-pixel field (bars show the background color).
Floyd-Steinberg dither to the fixed 16-color palette, then each 4x8 cell
keeps its 3 most frequent colors + the global background.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
C64 = os.path.join(HERE, "..")
SRC = os.path.join(C64, "..", "peterstartup.png")
OUT = os.path.join(C64, "build")

W, H = 160, 200            # multicolor fat pixels

# Pepto's measured C64 palette
PAL = [
    (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x88, 0x39, 0x32), (0x67, 0xB6, 0xBD),
    (0x8B, 0x3F, 0x96), (0x55, 0xA0, 0x49), (0x40, 0x31, 0x8D), (0xBF, 0xCE, 0x72),
    (0x8B, 0x54, 0x29), (0x57, 0x42, 0x00), (0xB8, 0x69, 0x62), (0x50, 0x50, 0x50),
    (0x78, 0x78, 0x78), (0x94, 0xE0, 0x89), (0x78, 0x69, 0xC4), (0x9F, 0x9F, 0x9F),
]


def dist(a, b):
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return 0.299 * dr * dr + 0.587 * dg * dg + 0.114 * db * db


def nearest(rgb, allowed=range(16)):
    return min(allowed, key=lambda i: dist(rgb, PAL[i]))


def main():
    from PIL import Image
    os.makedirs(OUT, exist_ok=True)

    im = Image.open(SRC).convert("RGB")
    # the palette is bright; lift the dark painting toward it
    from PIL import ImageEnhance
    im = ImageEnhance.Brightness(im).enhance(1.35)
    im = ImageEnhance.Color(im).enhance(1.4)
    im = ImageEnhance.Contrast(im).enhance(1.1)
    # fat pixels are 2 hires px wide: fit height 200, width = aspect * 200 / 2
    fw = min(W, max(1, round(H * im.width / im.height / 2)))
    fitted = im.resize((fw, H), Image.LANCZOS)
    x0 = (W - fw) // 2

    # canvas of float RGB for error-diffusion
    buf = [[(0.0, 0.0, 0.0)] * W for _ in range(H)]
    fpx = fitted.load()
    for y in range(H):
        for x in range(fw):
            buf[y][x0 + x] = tuple(float(c) for c in fpx[x, y])

    # Floyd-Steinberg to the 16-color palette
    idx = [[0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            old = buf[y][x]
            i = nearest(old)
            idx[y][x] = i
            err = tuple(old[c] - PAL[i][c] for c in range(3))

            def spread(xx, yy, f):
                if 0 <= xx < W and 0 <= yy < H:
                    buf[yy][xx] = tuple(buf[yy][xx][c] + err[c] * f for c in range(3))
            spread(x + 1, y, 7 / 16 * 0.7)      # damped diffusion: less noise,
            spread(x - 1, y + 1, 3 / 16 * 0.7)  # cleaner shapes on 4x8 cells
            spread(x, y + 1, 5 / 16 * 0.7)
            spread(x + 1, y + 1, 1 / 16 * 0.7)

    # global background = most frequent color
    counts = [0] * 16
    for row in idx:
        for i in row:
            counts[i] += 1
    bg = counts.index(max(counts))

    # per 4x8 cell: keep the 3 most frequent non-bg colors
    bitmap = bytearray()
    screen = bytearray()
    color = bytearray()
    for cr in range(25):
        for cc in range(40):
            cnt = {}
            for y in range(8):
                for x in range(4):
                    i = idx[cr * 8 + y][cc * 4 + x]
                    if i != bg:
                        cnt[i] = cnt.get(i, 0) + 1
            top = sorted(cnt, key=cnt.get, reverse=True)[:3]
            while len(top) < 3:
                top.append(bg)
            c1, c2, c3 = top
            lut = {bg: 0b00, c1: 0b01, c2: 0b10, c3: 0b11}
            allowed = [bg, c1, c2, c3]
            for y in range(8):
                b = 0
                for x in range(4):
                    i = idx[cr * 8 + y][cc * 4 + x]
                    if i not in lut:
                        i = min(allowed, key=lambda a: dist(PAL[i], PAL[a]))
                    b = (b << 2) | lut[i]
                bitmap.append(b)
            screen.append((c1 << 4) | c2)
            color.append(c3)

    # rewrite idx to what the constraint actually displays (for the preview)
    disp = [[bg] * W for _ in range(H)]
    for cr in range(25):
        for cc in range(40):
            scr, col = screen[cr * 40 + cc], color[cr * 40 + cc]
            cols = [bg, scr >> 4, scr & 15, col]
            for y in range(8):
                b = bitmap[(cr * 40 + cc) * 8 + y]
                for x in range(4):
                    disp[cr * 8 + y][cc * 4 + x] = cols[(b >> (6 - x * 2)) & 3]

    # ---- splash.inc ----
    def block(label, data, per=40):
        lines = [f"{label}"]
        for i in range(0, len(data), per):
            lines.append("\tdc.b " + ",".join(f"${b:02x}" for b in data[i:i + per]))
        return "\n".join(lines)

    src = [
        "; generated by gen_splash.py - do not edit",
        f"SPLASH_BG equ ${bg:x}",
        "\torg $8000",
        block("splashCol", color),
        "\torg $8400",
        block("splashScr", screen),
        "\torg $a000",
        block("splashBmp", bitmap),
        "",
    ]
    with open(os.path.join(OUT, "splash.inc"), "w") as f:
        f.write("\n".join(src))

    # ---- preview (fat px = 2x1 hires, scaled 2x) ----
    prev = Image.new("RGB", (W * 4, H * 2))
    ppx = prev.load()
    for y in range(H):
        for x in range(W):
            c = PAL[disp[y][x]]
            for dy in range(2):
                for dx in range(4):
                    ppx[x * 4 + dx, y * 2 + dy] = c
    prev.save(os.path.join(OUT, "splash_preview.png"))

    print(f"splash.inc: bg={bg}, bitmap 8000 + screen 1000 + color 1000 bytes")


if __name__ == "__main__":
    main()
