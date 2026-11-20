"""Translate the NTSC disassembly tables into Z80 data and Graphics I tiles."""
from contextlib import redirect_stdout
from pathlib import Path
import re
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def ntsc(path):
    text = path.read_text()
    return re.sub(r'^\.if PAL = 1\n(?:(?!^\.endif|^\.else).)*(?:^\.else\n(.*?))?^\.endif', r'\1', text,
                  flags=re.M | re.S)


main = ntsc(ROOT / 'main.asm')
constants = {k: int(v, 16) for k, v in re.findall(r'^(\w+)\s*=\s*\$(\w+)',
             (ROOT / 'constants.asm').read_text(), re.M)}


def table(name, source=main, directive='byte'):
    body = ('\n' + source).split('\n' + name + ':', 1)[1]
    rows = []
    for line in body.splitlines():
        line = line.partition(';')[0].strip()
        if not line:
            continue
        if not line.startswith('.' + directive + ' '):
            break
        for token in line.split(None, 1)[1].split(','):
            token = token.strip()
            rows.append(constants[token] if token in constants else int(token.replace('$', '0x'), 0))
    return rows


def emit(name, values):
    data = list(values)
    print(name + ':')
    for i in range(0, len(data), 24):
        print(' db ' + ','.join(str(x & 255) for x in data[i:i+24]))


def make_art():
    image = Image.open(ROOT / 'gfx/game_tileset.png').convert('L')
    tiles = [bytes(8) for _ in range(256)]
    for i, ch in enumerate('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'):
        tiles[ord(ch)] = bytes(sum((image.getpixel((8*(i%16)+x, 8*(i//16)+y)) > 0) << (7-x)
                                   for x in range(8)) for y in range(8))
    # Graphics I assigns one colour per group of eight patterns.
    for n, tile in enumerate((8, 16, 24)):
        tiles[tile] = bytes(sum((image.getpixel(((11+n)*8+x, 7*8+y)) > 85) << (7-x)
                                for x in range(8)) for y in range(8))
    tiles[1] = bytes([126, 66, 66, 126, 126, 66, 66, 126])
    menu, game = bytearray(768), bytearray(768)

    def text(screen, x, y, s):
        screen[y*32+x:y*32+x+len(s)] = s.encode('ascii')

    # Crop the wordmark out of the original row-addressed NES title map.
    title = Image.open(ROOT / 'gfx/title_menu_tileset.png').convert('L')
    source = (ROOT / 'gfx/nametables/title_screen_nametable.asm').read_text()
    raw = bytes(int(s, 16) for s in re.findall(r'\$([0-9A-F]{2})', source))
    logo = {}
    for row in range(8):
        off = (row+6)*35
        assert raw[off:off+3] == (0x20c0+32*row).to_bytes(2, 'big') + bytes([32])
        for x in range(3, 29):
            src = raw[off+3+x]
            if src == 255:
                continue
            if src not in logo:
                dest = logo[src] = 128+len(logo)
                tiles[dest] = bytes(sum((title.getpixel(((src%16)*8+i,(src//16)*8+j)) > 0) << (7-i)
                                        for i in range(8)) for j in range(8))
            menu[(row+1)*32+x] = logo[src]
    tiles[2] = bytes([0, 64, 96, 112, 96, 64, 0, 0])
    text(menu, 11, 9, 'SG  1000')
    for n, label in enumerate(['GAME TYPE','START LEVEL','B TYPE HEIGHT','MUSIC']):
        text(menu, 6, 11+2*n, label)
    text(menu, 4, 20, 'UP DOWN      SELECT')
    text(menu, 4, 21, 'LEFT RIGHT   CHANGE')
    text(menu, 4, 22, 'BUTTON 1     START')
    for y in range(1, 23):
        for x in range(10, 22):
            if x in (10, 21) or y in (1, 22):
                game[y*32+x] = 1
    for x, y, s in [(23,2,'TETRIS'),(23,4,'TYPE'),(23,6,'SCORE'),(23,10,'LINES'),
                    (23,13,'LEVEL'),(23,16,'NEXT'),(23,21,'UP PAUSE'),(1,3,'PIECES'),(2,20,'BEST')]:
        text(game,x,y,s)
    for n, piece in enumerate('TJZOSLI'):
        text(game, 2, 6+2*n, piece)
    emit('patterns', b''.join(tiles))
    emit('menuMap', menu)
    emit('gameMap', game)


def make_music(song, channel, name):
    # Predecode the pulse voice to duration, PSG latch, period high.
    source = ntsc(ROOT / f'audio/music/music{song}.asm')
    voice = ['sq1', 'sq2', 'tri'][channel]
    periods = table('noteToWaveTable', directive='dbyt')
    durations = table('noteDurationTable')
    out = []
    order = {1: [1, 2, 3], 2: [1, 2, 3, 3, 4], 3: [1]}[song]
    if song == 3 and channel < 2:
        order = [1, 2] if channel == 0 else [2]  # pulse 2 falls through to pulse 1 routine 2
    loop = 0
    for n in order:
        if song == 3 and channel == 0 and n == 2:
            loop = len(out)  # pulse 1 has a one-time rest before joining the canon
        track = 'sq1' if song == 3 and n == 2 else voice
        script = table(f'music_music{song}_{track}Routine{n}', source)
        count = 0
        i = 0
        while script[i]:
            op = script[i]
            i += 1
            if op == 0x9f:
                i += 2  # NES instrument and envelope
            elif op == 255:
                if count:
                    count -= 1
                    i = start
            elif op >= 0xc0:
                count, start = op-0xc1, i
            elif op >= 0xb0:
                duration = durations[0x24 + op-0xb0]
            else:
                period = periods[op//2-(2 if song == 2 else 1)] + 1
                if channel == 2:  # NES triangle runs one octave below a pulse
                    period = min(1023, period*2)
                out.extend([duration, (channel << 5) | (0x9f if op == 2 else 0x80 | (period & 15)), period >> 4])
    emit(name, out + [0])
    print(f' dw {name}+{loop}')


if __name__ == '__main__':
    with open(sys.argv[1], 'w') as f, redirect_stdout(f):
        make_art()
        shape = table('orientationTable')[:-12]  # omit hidden sentinel
        assert len(shape) == 19*12
        emit('offsets', [v for i,v in enumerate(shape) if i%3 != 1])
        emit('pieceTiles', [(shape[i]-constants['tile1']+1)*8 for i in range(1,len(shape),12)])
        previews = bytearray(19*8)
        for piece in table('spawnTable'):
            for dy, tile, dx in zip(*[iter(shape[piece*12:piece*12+12])]*3):
                previews[piece*8 + dy*4 + dx+2] = (tile-constants['tile1']+1)*8
        emit('previews', previews)
        emit('rotations', table('rotationTable'))
        emit('spawns', table('spawnTable'))
        emit('gravity', table('framesPerDropTable'))
        for song in range(1, 4):
            for channel in range(3):
                make_music(song, channel, f'song{song}ch{channel}')
