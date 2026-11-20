"""Convert the disassembly's PPU writes, attribute quadrants and CHR to Graphics II.

Screen transfers are addressed, so the three TMS pattern banks can have independent
local dictionaries while retaining a common overlay font. No frame buffer in RAM.
"""

import re
from collections import Counter
from functools import lru_cache
from itertools import combinations_with_replacement

from PIL import Image

# NTSC NES colour indices used by this cartridge -> nearest useful TMS colours.
NES = [
    14,
    4,
    4,
    4,
    13,
    13,
    6,
    6,
    10,
    12,
    12,
    12,
    4,
    1,
    1,
    1,
    14,
    4,
    4,
    5,
    13,
    13,
    6,
    9,
    10,
    12,
    2,
    2,
    7,
    1,
    1,
    1,
    15,
    5,
    5,
    13,
    13,
    9,
    9,
    9,
    11,
    3,
    3,
    3,
    7,
    14,
    1,
    1,
    15,
    7,
    7,
    15,
    15,
    9,
    9,
    11,
    11,
    3,
    3,
    7,
    7,
    15,
    1,
    1,
]
RGB = [
    (0, 0, 0),
    (0, 0, 0),
    (33, 200, 66),
    (94, 220, 120),
    (84, 85, 237),
    (125, 118, 252),
    (212, 82, 77),
    (66, 235, 245),
    (252, 85, 84),
    (255, 121, 120),
    (212, 193, 84),
    (230, 206, 128),
    (33, 176, 59),
    (201, 91, 186),
    (204, 204, 204),
    (255, 255, 255),
]
DIST = [[sum((a - b) ** 2 for a, b in zip(i, j)) for j in RGB] for i in RGB]


@lru_cache(None)
def encode_line(pixels):
    counts = Counter(pixels)
    # Minimise error over the colours actually present on this scanline.
    bg, fg = min(
        combinations_with_replacement(sorted(counts), 2),
        key=lambda pair: sum(
            n * min(DIST[p][c] for c in pair) for p, n in counts.items()
        ),
    )
    bits = sum((DIST[p][fg] < DIST[p][bg]) << (7 - i) for i, p in enumerate(pixels))
    return bits, fg * 16 + bg


def unpack(raw):
    ram = bytearray(1024)
    i = 0
    while raw[i] != 255:
        addr, ctl = int.from_bytes(raw[i : i + 2], "big"), raw[i + 2]
        i += 3
        count = ctl & 63 or 64
        for n in range(count):
            if 0x2000 <= addr < 0x2400:
                ram[addr - 0x2000] = raw[i if ctl & 64 else i + n]
            addr += 32 if ctl & 128 else 1
        i += 1 if ctl & 64 else count
    return ram


def pixel(nt, img, pal, x, y):
    tx, ty = x // 8, y // 8
    tile = nt[ty * 32 + tx]
    attr = nt[960 + ty // 4 * 8 + tx // 4] >> ((ty & 2) * 2 + (tx & 2)) & 3
    ink = img.getpixel((tile % 16 * 8 + x % 8, tile // 16 * 8 + y % 8)) // 85
    return pal[4 * attr + ink] if ink else pal[0]


def local_id(tiles, x, y, scaled, nt, img, pal):
    lines = []
    for j in range(8):
        sy = (8 * y + j) * 5 // 4 if scaled else 8 * y + j + 24
        lines.append(
            encode_line(tuple(pixel(nt, img, pal, 8 * x + i, sy) for i in range(8)))
        )
    key = tuple(bytes(plane) for plane in zip(*lines))
    return tiles.setdefault(key, 96 + len(tiles))


def generate(root, table, emit):
    gfx = root / "gfx"
    directory = gfx / "nametables"
    scenes = [
        ("Legal", "legal_screen", "title_menu", "legal_screen"),
        ("Title", "title_screen", "title_menu", "menu"),
        ("Type", "game_type_menu", "title_menu", "menu"),
        ("Level", "level_menu", "title_menu", "menu"),
        ("Name", "enter_high_score", "title_menu", "menu"),
        ("Play", "game", "game", "game"),
        ("Rocket", "type_a_ending", "typeA_ending", "ending"),
        ("Cathedral", "type_b_ending", "typeA_ending", "ending"),
        ("Concert", "type_b_lvl9_ending", "typeB_ending", "ending"),
    ]
    for label, name, sheet, palette in scenes:
        if label == "Title":
            asm = (directory / "title_screen_nametable.asm").read_text()
            asm = re.sub(
                r"\.if NWC = 1.*?\.else(.*?)\.endif", r"\1", asm, flags=re.DOTALL
            )
            raw = bytes(int(x, 16) for x in re.findall(r"\$([\dA-F]{2})", asm))
        else:
            raw = (directory / f"{name}_nametable.bin").read_bytes()
        nt = unpack(raw)
        pal = [NES[i] for i in table(palette + "_palette")[3:19]]
        img = Image.open(gfx / f"{sheet}_tileset.png").convert("L")

        # Alternative NES scenes are small runs of nametable replacements.
        patches = {
            "Play": ["game_typeb_nametable_patch"],
            "Rocket": ["ending_patchToPpu_typeAOver120k"],
            "Concert": [f"ending_patchToPpu_typeBConcertHeight{i}" for i in range(5)],
        }.get(label, [])
        changes = []
        for patch in patches:
            data = iter(table(patch))
            edits = {}
            while True:
                addr = next(data) * 256 + next(data) - 0x2000
                for tile in data:
                    if tile in (253, 254):
                        break
                    edits[addr] = tile
                    addr += 1
                if tile == 253:
                    break
            changes.append(edits)
        scaled = label in ("Title", "Legal")
        blocks = []
        names = []
        for bank in range(3):
            tiles = {}
            for y in range(8 * bank, 8 * bank + 8):
                for x in range(32):
                    names.append(local_id(tiles, x, y, scaled, nt, img, pal))
                    slot = (y + 3) * 32 + x
                    for edits in changes:
                        if slot in edits:
                            old, nt[slot] = nt[slot], edits[slot]
                            edits[slot] = local_id(tiles, x, y, scaled, nt, img, pal)
                            nt[slot] = old
            assert len(tiles) <= 160, (label, bank, len(tiles))
            for plane in range(2):
                blocks.append(
                    (
                        0x2000 * plane + bank * 0x800 + 96 * 8,
                        b"".join(k[plane] for k in tiles),
                    )
                )
        blocks.append((0x1800, bytes(names)))
        print(f"scene{label}:")
        for addr, data in blocks:
            print(f" dw {addr},{len(data)}")
            emit(None, data)
        print(" dw 65535")
        for name, edits in zip(patches, changes):
            print(name + ":")
            # Compact (VRAM addr, tile) triples; all patch entries fit in a byte count.
            edits = [(k, v) for k, v in edits.items() if 96 <= k < 864]
            emit(None, [len(edits)])
            for addr, tile in edits:
                print(f" dw {0x1800 + addr - 96}\n db {tile}")


def actors(root, main, table, emit):
    # Retain NES metasprite offsets/flips. TMS sprites have a single ink colour.
    atlas = {}
    ids = list(range(0x16, 0x1C)) + list(range(0x1D, 0x3C)) + list(range(0x3E, 0x56))
    ids = [i for i in ids if i not in (0x25, 0x26, 0x30, 0x31, 0x53)]
    labels = {
        int(i, 16): name
        for name, i in re.findall(r"^(sprite([0-9A-F]{2})\w+):", main, re.MULTILINE)
    }
    palettes = table("ending_palette")[19:35]
    for sid in ids:
        sheet = (
            "typeB_ending"
            if sid <= 0x2B and sid not in (0x23, 0x24)
            else "typeA_ending"
        )
        if 0x4D <= sid <= 0x52:
            sheet = "typeB_ending"
        if sid in (0x4B, 0x4C, 0x54, 0x55):
            sheet = "game"
        if sid == 0x53 or sid not in labels:
            continue  # menu cursor, not an actor
        img = Image.open(root / f"gfx/{sheet}_tileset.png").convert("L")
        src = table(labels[sid])
        out = []
        for dy, tile, attr, dx in zip(*[iter(src[:-1])] * 4):
            rows = []
            inks = []
            for y in range(8):
                row = []
                for x in range(8):
                    v = (
                        img.getpixel(
                            (
                                tile % 16 * 8 + (7 - x if attr & 64 else x),
                                tile // 16 * 8 + (7 - y if attr & 128 else y),
                            )
                        )
                        // 85
                    )
                    row.append(v)
                    if v:
                        inks.append(NES[palettes[(attr & 3) * 4 + v]])
                rows.append(sum(bool(v) << (7 - i) for i, v in enumerate(row)))
            if inks:
                pattern = bytes(rows)
                # Patterns 0 and 1 belongs to menu cursors.
                out += [
                    dy,
                    dx,
                    atlas.setdefault(pattern, 2 + len(atlas)),
                    Counter([ink for ink in inks if ink != 1] or inks).most_common(1)[
                        0
                    ][0],
                ]
        emit(f"actor{sid}", [len(out) // 4] + out)
    assert len(atlas) <= 254, len(atlas)
    emit("actorArt", b"".join(atlas))
    print("actorArtEnd:")
    print(
        "actorTable:\n dw "
        + ",".join(
            "actor" + str(i) if i in ids and i in labels and i != 0x53 else "0"
            for i in range(0x56)
        )
    )
