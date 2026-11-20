"""Translate the NTSC disassembly tables into Z80 data and Graphics II tiles."""

import re
import sys
from contextlib import redirect_stdout
from pathlib import Path

import scenes
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def ntsc(path):
    text = path.read_text()
    return re.sub(
        r"^\.if PAL = 1\n(?:(?!^\.endif|^\.else).)*(?:^\.else\n(.*?))?^\.endif",
        r"\1",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )


main = ntsc(ROOT / "main.asm")
constants = {
    k: int(v, 16)
    for k, v in re.findall(
        r"^(\w+)\s*=\s*\$(\w+)", (ROOT / "constants.asm").read_text(), re.MULTILINE
    )
}


def table(name, source=main, directive="byte"):
    body = ("\n" + source).split("\n" + name + ":", 1)[1]
    rows = []
    for line in body.splitlines():
        line = line.partition(";")[0].strip()
        if not line:
            continue
        if not line.startswith("." + directive + " "):
            break
        for token in line.split(None, 1)[1].split(","):
            token = token.strip()
            rows.append(
                constants[token]
                if token in constants
                else int(token.replace("$", "0x"), 0)
            )
    return rows


def emit(name, values):
    data = list(values)
    if name:
        print(name + ":")
    for i in range(0, len(data), 24):
        print(" db " + ",".join(str(x & 255) for x in data[i : i + 24]))


def make_art():
    image = Image.open(ROOT / "gfx/game_tileset.png").convert("L")
    tiles = [bytes(8) for _ in range(91)]
    for i, ch in enumerate("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
        tiles[ord(ch)] = bytes(
            sum(
                (image.getpixel((8 * (i % 16) + x, 8 * (i // 16) + y)) > 0) << (7 - x)
                for x in range(8)
            )
            for y in range(8)
        )
    emit("font", b"".join(tiles[48:91]))
    emit("curtainTile", [254, 130, 186, 170, 186, 130, 254, 0])
    data = []
    palette = table("colorTable", directive="dbyt")
    inks = b"".join(x.to_bytes(2, "big") for x in palette)
    for level in range(10):
        for n in range(3):
            rows = [
                scenes.encode_line(
                    tuple(
                        scenes.NES[
                            inks[
                                level * 4
                                + image.getpixel(((11 + n) * 8 + x, 56 + y)) // 85
                            ]
                        ]
                        for x in range(8)
                    )
                )
                for y in range(8)
            ]
            for plane in zip(*rows):
                data.extend(plane)
    emit("blockArt", data)
    scenes.generate(ROOT, table, emit)
    scenes.actors(ROOT, main, table, emit)


def make_music(song, channel, name):
    # Predecode the pulse voice to duration, PSG latch, period high.
    extra = {
        4: ("titleScreen", 5, [1]),
        5: ("bTypeGoalAchieved", -2, [1]),
        6: ("congratulations", 0, [1]),
        7: ("endings", -8, [1, 2, 1, 3]),
    }
    if song in extra:
        part, transpose, order = extra[song]
        prefix = "music_" + part
        filename = "music_" + ("titlescreen" if song == 4 else part)
    else:
        prefix = "music_music" + str(song)
        filename = "music" + str(song)
        transpose = -2 if song == 2 else -1
        order = {1: [1, 2, 3], 2: [1, 2, 3, 3, 4], 3: [1]}[song]
    source = ntsc(ROOT / f"audio/music/{filename}.asm")
    voice = ["sq1", "sq2", "tri", "noise"][channel]
    periods = table("noteToWaveTable", directive="dbyt")
    out = []
    if song == 5:
        voice = ["sq1", "tri", "sq2", "noise"][channel]
    if song == 3 and channel < 2:
        order = (
            [1, 2] if channel == 0 else [2]
        )  # pulse 2 falls through to pulse 1 routine 2
    if channel == 3:
        noise = table("noises_table")
        order = [1, 1, 1, 2] if song == 7 else [1]
    instrument = 4 if (song, channel) == (3, 1) else 0
    loop = 0
    for n in order:
        if song == 3 and channel == 0 and n == 2:
            loop = len(out)  # pulse 1 has a one-time rest before joining the canon
        track = "sq1" if song == 3 and n == 2 else voice
        script = table(f"{prefix}_{track}Routine{n}", source)
        count = start = 0
        i = 0
        while i < len(script) and script[i]:
            op = script[i]
            i += 1
            if op == 0x9F:
                instrument = script[i] & 31
                i += 2
            elif op == 255:
                if count:
                    count -= 1
                    i = start
            elif op >= 0xC0:
                count, start = op - 0xC1, i
            elif op >= 0xB0:
                duration = op - 0xB0 + 1
            elif channel == 3:
                # The NES table addresses short percussion hits, not pitches.
                ix = op & 63
                pitch = noise[ix + 1] & 15
                out.extend(
                    [duration, 0xE4 + min(2, pitch // 3), 0xFF if op == 1 else 0xF7]
                )
            else:
                period = min(1023, periods[op // 2 + transpose] + 1) if op != 2 else 0
                if channel == 2:  # NES triangle runs one octave below a pulse
                    period = min(1023, period * 2)
                out.extend(
                    [
                        duration,
                        (channel << 5) | (0x9F if op == 2 else 0x80 | (period & 15)),
                        period >> 4,
                    ]
                )
                if channel < 2:
                    out.append(0 if op == 2 else instrument)
    emit(name, out + [0])
    print(f" dw {name}+{loop}" if song not in (4, 5) else " dw 0")


if __name__ == "__main__":
    with open(sys.argv[1], "w") as f, redirect_stdout(f):
        make_art()
        shape = table("orientationTable")[:-12]  # omit hidden sentinel
        assert len(shape) == 19 * 12
        emit("offsets", [v for i, v in enumerate(shape) if i % 3 != 1])
        emit(
            "pieceTiles",
            [(shape[i] - constants["tile1"] + 1) * 8 for i in range(1, len(shape), 12)],
        )
        previews = bytearray(19 * 8)
        for piece in table("spawnTable"):
            for dy, tile, dx in zip(*[iter(shape[piece * 12 : piece * 12 + 12])] * 3):
                previews[piece * 8 + dy * 4 + dx + 2] = (
                    tile - constants["tile1"] + 1
                ) * 8
        emit("previews", previews)
        emit("rotations", table("rotationTable"))
        emit("spawns", table("spawnTable"))
        emit("gravity", table("framesPerDropTable"))
        demo = ntsc(ROOT / "data/demo_data.asm")
        buttons = table("demoButtonsTable", demo)
        buttons[::2] = [
            sum(
                dst
                for src, dst in [(1, 8), (2, 4), (4, 2), (64, 32), (128, 16)]
                if v & src
            )
            for v in buttons[::2]
        ]
        emit("demoInput", buttons)
        print("demoEnd:")
        emit(
            "demoPieces",
            [
                table("spawnTable")[((v >> 4) & 7) % 7]
                for v in table("demoTetriminoTypeTable", demo)
            ],
        )
        pitch = [n for pair in table("noiselo_table") for n in (pair >> 4, pair & 15)]
        emit("curtainNoise", [0xE4 + min(2, pitch[i] // 5) for i in range(0, 60, 3)])
        emit("creatureSteps", table("ending_typeBCathedralVectorTable")[:9])
        emit("creatureLanes", table("ending_typeBCathedralYTable")[:54])
        emit("durations", table("noteDurationTable"))
        # Expand the NES packed-nibble pulse envelopes into PSG attenuation.
        envs = re.search(r"musicChanVolControlTable:(.*?)LEA76:", main, re.DOTALL)[1]
        names = re.findall(r"\.addr\s+(\w+)", envs)
        print("envelopeTable:\n dw " + ",".join(["quietEnv"] + names))
        emit("quietEnv", [15, 255])
        inline = re.sub(r":\s+\.byte", ":\n .byte", main)
        for name in names:
            frames = []
            for pair in table(name, inline):
                if pair in (240, 255):
                    if pair == 240:
                        frames.append(15)
                    break
                frames += [15 - (pair >> 4), 15 - (pair & 15)]
            emit(name, frames + [255])
        for song in (1, 2, 3, 4, 5, 6, 7):
            for channel in range(3 if song == 3 else 4):
                make_music(song, channel, f"song{song}ch{channel}")
