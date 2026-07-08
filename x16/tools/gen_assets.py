#!/usr/bin/env python3
"""Peter and the Wolf, X16 asset pipeline.

Reads   art/tiles.txt    8x8 4bpp tiles (hex-digit palette indices)
        art/sprites.txt  native sprites + imports of the C64 pixel-pair art
Writes  build/PETERART.BIN  VRAM blob: tiles @$04000 (16KB) + sprites @$08000
        build/assets.inc     frame tables, tile ids, solidity, palette data
        build/preview.png    contact sheet for eyeballing

Sprite art: hex digit = index into the sprite's 16-color palette bank,
'.' = 0 = transparent.  Mirroring is left to VERA's hflip bit.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
X16 = os.path.join(HERE, "..")
ART = os.path.join(X16, "art")
OUT = os.path.join(X16, "build")
C64ART = os.path.join(X16, "..", "c64", "art", "sprites.txt")

VRAM_TILES = 0x04000
VRAM_SPRITES = 0x08000

# ------------------------------------------------------------------
#  Palettes (12-bit $RGB).  Bank layout:
#  0 UI (X16 default)   1 terrain (live, lerped)  2..6 terrain moods
#  7 Peter  8 wolf  9 wolf stunned  10 cast  11 humans  12 props
#  13 autumn  14 winter  15 glow/cutscene
# ------------------------------------------------------------------

def rgb(s):
    return int(s, 16)

# terrain semantic slots: 0 unused, 1 grassDk 2 grassMd 3 grassLt 4 petalWht
# 5 petalGld 6 trunkDk 7 trunkLt 8 leafDk 9 leafMd A leafLt B waterDp
# C waterLt D rockGy E rockLt F wood
TERRAIN_DAY    = "000 274 385 4A6 EEE FC4 631 853 153 275 4A6 136 38B 667 99A A74"
TERRAIN_GOLDEN = "000 463 685 8A5 FED FC4 631 853 253 475 7A5 236 49B 767 A98 B84"
TERRAIN_DUSK   = "000 235 346 467 BBD DA4 421 642 134 246 368 125 269 445 778 863"
TERRAIN_NIGHT  = "000 123 134 245 89B 875 211 321 122 133 245 114 136 223 445 432"
TERRAIN_AUTUMN = "000 274 385 4A6 EEE FC4 631 853 730 951 B72 136 38B 667 99A A74"
TERRAIN_WINTER = "000 88A 99B DDE FFF FC4 531 743 032 143 254 125 46A 778 AAB 963"

def scale(bank, f):
    out = []
    for c in bank.split():
        v = int(c, 16)
        r = min(15, int(((v >> 8) & 15) * f))
        g = min(15, int(((v >> 4) & 15) * f))
        b = min(15, int((v & 15) * f + 0.5 + (0.8 if f < 0.5 else 0)))
        out.append(f"{r:X}{g:X}{b:X}")
    return " ".join(out)

BANKS = {
    0:  "000 FFF 800 AFE C4C 0C5 00A EE7 D85 640 F77 333 777 AF6 08F BBB",  # X16 default
    1:  TERRAIN_DAY,      # live terrain (rewritten per level / drift)
    2:  TERRAIN_GOLDEN,
    3:  TERRAIN_DUSK,
    4:  TERRAIN_NIGHT,                    # night, lit
    5:  scale(TERRAIN_NIGHT, 0.55),       # night, dim ring
    6:  scale(TERRAIN_NIGHT, 0.22),       # night, dark
    7:  "000 210 C22 FB8 A22 FFF 249 000 000 000 000 000 000 000 000 000",  # Peter: outline,coat,skin,capDk,white,shorts
    8:  "000 334 778 556 CDD 222 EB4 F54 FFE 000 000 000 000 000 000 000",  # wolf: dark,coat,coatDk,tailTip,paw,eyeGold,eyeRed,fang
    9:  "000 445 99A 677 BBC 333 9AF 9AF DDD 000 000 000 000 000 000 000",  # wolf stunned (web stun grays, moony eye)
    10: "000 111 FFF D95 B63 46C 3BC FC3 F80 852 C22 888 BE5 F9A FED FE6",  # cast (3/4 ginger, 6 teal dragonfly, 9 tabby dark, C cat eye, E cream)
    11: "000 210 EB9 EEE 742 253 667 434 555 C33 FC3 875 132 000 000 000",  # humans
    12: "000 210 D22 F66 274 FC3 C96 E33 811 FFF 445 653 964 F80 888 000",  # props
    13: TERRAIN_AUTUMN,
    14: TERRAIN_WINTER,
    15: "000 FE8 FC4 D93 FFC 555 333 A55 F55 800 EDA 210 000 000 000 000",  # glow / sunset
}

def palette_bytes(banks):
    data = []
    for b in range(16):
        cols = banks[b].split()
        assert len(cols) == 16, f"bank {b}: {len(cols)} colors"
        for c in cols:
            v = int(c, 16)
            data.append(v & 0xFF)          # GB
            data.append((v >> 8) & 0x0F)   # 0R
    return bytes(data)

# ------------------------------------------------------------------
#  tiles
# ------------------------------------------------------------------

def parse_tiles(path):
    tiles, cur = [], None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if line.startswith(";") or not line.strip():
            continue
        w = line.split()
        if w[0] == "tile":
            cur = {"idx": int(w[1]), "name": w[2], "solid": "solid" in w[3:], "rows": []}
            tiles.append(cur)
        else:
            cur["rows"].append(line.strip())
    for t in tiles:
        assert len(t["rows"]) == 8 and all(len(r) == 8 for r in t["rows"]), t["name"]
    assert [t["idx"] for t in tiles] == list(range(len(tiles))), "tile indices must be 0..n"
    return tiles

def px(ch):
    return 0 if ch == "." else int(ch, 16)

def pack4bpp(rows, w):
    out = bytearray()
    for r in rows:
        assert len(r) == w, f"row width {len(r)} != {w}: {r!r}"
        for i in range(0, w, 2):
            out.append((px(r[i]) << 4) | px(r[i + 1]))
    return bytes(out)

# ------------------------------------------------------------------
#  sprites
# ------------------------------------------------------------------

SIZEBITS = {8: 0, 16: 1, 32: 2, 64: 3}

def parse_c64(path):
    """Return {name: rows} of the C64 pixel-pair art (12 or 24 wide, 21 tall)."""
    blocks, cur = {}, None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if line.startswith(";") or not line.strip():
            continue
        w = line.split()
        if w[0] in ("sprite", "wide"):
            cur = []
            blocks[w[1]] = cur
        else:
            cur.append(line)
    return blocks

def c64_to_rows(art, mapping, box_w, box_h):
    """Expand fat pixels 2x wide, centre in a box_w x box_h field of '.'."""
    w = len(art[0]) * 2
    xoff = (box_w - w) // 2
    yoff = max(0, (box_h - len(art)) // 2)
    rows = ["." * box_w for _ in range(box_h)]
    for y, r in enumerate(art):
        line = "".join(mapping[c] * 2 for c in r)
        rows[y + yoff] = "." * xoff + line + "." * (box_w - xoff - w)
    return rows

def parse_sprites(path, c64):
    sprites = []  # dicts: name, w, h, bank, rows
    cur = None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if line.startswith(";") or not line.strip():
            continue
        w = line.split()
        if w[0] == "sprite":
            wh = w[2].split("x")
            cur = {"name": w[1], "w": int(wh[0]), "h": int(wh[1]),
                   "bank": int([t for t in w if t.startswith("bank=")][0][5:]), "rows": []}
            sprites.append(cur)
        elif w[0] == "c64":
            # c64 <name> <w>x<h> bank=<n> from <c64name> map .=0,K=1,C=2,W=3
            wh = w[2].split("x")
            bw, bh = int(wh[0]), int(wh[1])
            bank = int([t for t in w if t.startswith("bank=")][0][5:])
            src = w[w.index("from") + 1]
            mp = {}
            for pair in [t for t in w if "=" in t and "," in t][0].split(","):
                k, v = pair.split("=")
                mp[k] = v
            rows = c64_to_rows(c64[src], mp, bw, bh)
            sprites.append({"name": w[1], "w": bw, "h": bh, "bank": bank, "rows": rows})
            cur = None
        else:
            if cur is None:
                sys.exit(f"art row outside sprite block: {line!r}")
            cur["rows"].append(line.strip())
    for s in sprites:
        assert len(s["rows"]) <= s["h"], f"{s['name']}: {len(s['rows'])} rows, want <={s['h']}"
        assert s["w"] in SIZEBITS and s["h"] in SIZEBITS, s["name"]
        assert all(len(r) <= s["w"] for r in s["rows"]), f"{s['name']}: row too wide"
        s["rows"] = [r + "." * (s["w"] - len(r)) for r in s["rows"]]
        s["rows"] += ["." * s["w"]] * (s["h"] - len(s["rows"]))
    return sprites

# ---- programmatic frames ----

DIGITS = {  # 3x5
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["##.", "..#", ".#.", "#..", "###"],
    "3": ["##.", "..#", ".#.", "..#", "##."],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "5": ["###", "#..", "##.", "..#", "##."],
    "6": [".##", "#..", "###", "#.#", "###"],
    "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"],
    "9": ["###", "#.#", "###", "..#", "##."],
}

APPLE = [  # 16x16, props bank: 2 red 3 hilite 4 leaf 6 stem
    "................",
    ".......6........",
    "......64........",
    "......644.......",
    "....2226222.....",
    "...222222222....",
    "..22322222222...",
    "..23322222222...",
    "..23222222222...",
    "..22222222222...",
    "..22222222222...",
    "...222222222....",
    "....2222222.....",
    ".....22.22......",
    "................",
    "................",
]

def apple_frames():
    frames = []
    for d in "123456789":
        rows = [list(r) for r in APPLE]
        pat = DIGITS[d]
        for y, pr in enumerate(pat):
            for x, c in enumerate(pr):
                if c == "#":
                    rows[6 + y][6 + x] = "9"     # white digit
        frames.append({"name": f"apple{d}", "w": 16, "h": 16, "bank": 12,
                       "rows": ["".join(r) for r in rows]})
    frames.append({"name": "apple", "w": 16, "h": 16, "bank": 12, "rows": APPLE})
    return frames

def dot_frames():
    out = []
    for name, ci in (("dotgold", "5"), ("dotred", "7"), ("dotwhite", "9"),
                     ("dotgreen", "4"), ("dotorange", "D")):
        rows = ["." * 8 for _ in range(8)]
        for y in (2, 3, 4, 5):
            rows[y] = ".." + ci * 4 + ".."
        out.append({"name": name, "w": 8, "h": 8, "bank": 12, "rows": rows})
    return out

# ------------------------------------------------------------------

def main():
    os.makedirs(OUT, exist_ok=True)
    tiles = parse_tiles(os.path.join(ART, "tiles.txt"))
    c64 = parse_c64(C64ART)
    sprites = parse_sprites(os.path.join(ART, "sprites.txt"), c64)
    sprites += apple_frames() + dot_frames()

    # ---- tile block + sprite block, copied to VRAM at boot ----
    tiledata = bytearray()
    for t in tiles:
        tiledata += pack4bpp(t["rows"], 8)
    assert len(tiledata) <= VRAM_SPRITES - VRAM_TILES

    sprdata = bytearray()
    frames = []
    for s in sprites:
        addr = VRAM_SPRITES + len(sprdata)
        data = pack4bpp(s["rows"], s["w"])
        assert addr % 32 == 0
        frames.append((s["name"], addr, s["w"], s["h"], s["bank"]))
        sprdata += data
    assert VRAM_SPRITES + len(sprdata) <= 0x1B000, "sprites overrun KERNAL screen area"

    # ---- assets.inc ----
    L = ["; generated by gen_assets.py - do not edit",
         '.segment "ASSETS"        ; page-aligned: reused as worldMap after boot']
    L.append(f"TILE_DATA_LEN = {len(tiledata)}")
    L.append(f"SPR_DATA_LEN = {len(sprdata)}")
    for label, data in (("tileData", tiledata), ("sprData", sprdata)):
        L.append(f"{label}:")
        for i in range(0, len(data), 32):
            L.append("\t.byte " + ",".join(f"${b:02X}" for b in data[i:i+32]))
    L.append(".rodata")
    L.append(f"TILE_COUNT = {len(tiles)}")
    for t in tiles:
        L.append(f"TI_{t['name'].upper()} = {t['idx']}")
    solid = ["1" if t["solid"] else "0" for t in tiles] + ["0"] * (32 - len(tiles))
    L.append("tileSolid:")
    L.append("\t.byte " + ",".join(solid))
    L.append(f"FRAME_COUNT = {len(frames)}")
    for i, (name, addr, w, h, bank) in enumerate(frames):
        L.append(f"FR_{name.upper()} = {i}")
    for label, fn in (
        ("sprFrameA0", lambda a, w, h, b: (a >> 5) & 0xFF),
        ("sprFrameA1", lambda a, w, h, b: (a >> 13) & 0x0F),
        ("sprFrameSz", lambda a, w, h, b: (SIZEBITS[h] << 6) | (SIZEBITS[w] << 4) | b),
    ):
        vals = [fn(a, w, h, b) for (_, a, w, h, b) in frames]
        L.append(f"{label}:")
        for i in range(0, len(vals), 16):
            L.append("\t.byte " + ",".join(f"${v:02X}" for v in vals[i:i+16]))
    L.append("paletteData:")
    pal = palette_bytes(BANKS)
    for i in range(0, len(pal), 16):
        L.append("\t.byte " + ",".join(f"${b:02X}" for b in pal[i:i+16]))
    # terrain mood tables (32 bytes each) for palette lerping into bank 1
    for name, bank in (("palDay", TERRAIN_DAY), ("palGolden", TERRAIN_GOLDEN),
                       ("palDusk", TERRAIN_DUSK), ("palNight", TERRAIN_NIGHT),
                       ("palAutumn", TERRAIN_AUTUMN), ("palWinter", TERRAIN_WINTER)):
        b = palette_bytes({**{i: BANKS[i] for i in range(16)}, 0: bank})[:32]
        L.append(f"{name}:")
        L.append("\t.byte " + ",".join(f"${v:02X}" for v in b[:16]))
        L.append("\t.byte " + ",".join(f"${v:02X}" for v in b[16:]))
    with open(os.path.join(OUT, "assets.inc"), "w") as f:
        f.write("\n".join(L) + "\n")

    # ---- preview ----
    try:
        from PIL import Image
        def bank_rgb(bank):
            cols = []
            for c in BANKS[bank].split():
                v = int(c, 16)
                cols.append(tuple(((v >> s) & 15) * 17 for s in (8, 4, 0)))
            return cols
        img = Image.new("RGB", (560, 400), (24, 24, 32))
        pxl = img.load()
        for i, t in enumerate(tiles):
            cols = bank_rgb(1)
            ox, oy = 8 + (i % 16) * 20, 8 + (i // 16) * 20
            for y in range(8):
                for x in range(8):
                    v = px(t["rows"][y][x])
                    for dy in range(2):
                        for dx in range(2):
                            pxl[ox + x*2 + dx, oy + y*2 + dy] = cols[v]
        ox, oy, rowh = 8, 66, 0
        for s in sprites:
            cols = bank_rgb(s["bank"])
            if ox + s["w"] + 4 > 552:
                ox, oy = 8, oy + rowh + 6
                rowh = 0
            for y in range(s["h"]):
                for x in range(s["w"]):
                    v = px(s["rows"][y][x])
                    if v:
                        pxl[ox + x, oy + y] = cols[v]
            ox += s["w"] + 6
            rowh = max(rowh, s["h"])
        img.save(os.path.join(OUT, "preview.png"))
    except ImportError:
        pass

    print(f"tiles: {len(tiles)}  sprite frames: {len(frames)}  "
          f"data: {len(tiledata)+len(sprdata)} bytes (sprites end ${VRAM_SPRITES+len(sprdata):05X})")

if __name__ == "__main__":
    main()
