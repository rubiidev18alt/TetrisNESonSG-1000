# NES Tetris on the Sega SG-1000

**[Download the playable 48 KiB cartridge](tetris.sg)**. Open `tetris.sg` in an SG-1000 emulator such as SMS Plus GX with controller 1 and NTSC / 60 Hz timing. No BIOS, NES ROM, mapper, or RAM expansion is required.

### Start a game

Press **1** to advance from the title. On the game-type screen, **Left/Right** selects A-Type (endless) or B-Type (clear 25 lines); **Up/Down** previews the three music tracks or selects silence. Press **1** for the level screen, then move around the 0–9 grid with the directions. In B-Type, **2** switches between level and garbage height. Press **1** to play, or press it **while holding 2** to start ten levels higher. To return from the B-Type grid, hold **Up** and press **2**. Leave the title idle to watch the NES attract recording play through the game engine.

| During play | Controller 1 |
| --- | --- |
| Move | Left / Right (hold to repeat) |
| Soft drop | Hold Down; press again for each new piece |
| Rotate clockwise / counterclockwise | 1 / 2 |
| Hide or show next piece | 1 + 2 together |
| Continue after a game or ending | 1 (after any bonus tally) |

Up is ignored during play. Each game type has a three-place high-score table, retained until reset. For a qualifying score, **Up/Down** cycles characters, **Left/Right** moves through the six-letter name, **1** advances, and **2** finishes.

### What's in the cartridge

The Z80 reads all three 16 KiB ROM windows directly (`$0000–$BFFF`); work RAM starts at `$C000`. The assembler's `romUsed` label marks the end of the program and assets before final cartridge-size padding. The build uses about 98% of the image before that padding.

* **Graphics:** Nine scenes converted from the NES nametables, tile sheets, attribute quadrants and palettes into TMS9918A Graphics II. They cover the legal notice, title, both selection screens, playfield, name entry, and three ending backgrounds. The game uses the NES level skins, statistics panel and next box; the headers fit above the full 20-row well, line clears wipe outward on the four-frame clock, and top-out lowers the curtain.
* **Play:** The disassembly supplies all 19 orientations, rotation and spawn tables, NTSC gravity curve, and the attract-mode piece and input streams. The game implements NES-style delayed auto-shift, failed-drop lock, soft-drop points, level transitions, and B-Type garbage and bonus scoring.
* **Music:** Seven NES arrangements use the PSG's three tones and noise channel, with pulse envelopes mapped to PSG volume steps, octave-adjusted bass, short percussion hits, and the faster tempo when the stack reaches the danger row. Move, rotate, lock, line-clear and level-up cues temporarily use the lead channel.
* **Endings:** A-Type scores of 30,000 and up launch different rockets at the NES score thresholds. B-Type pays out the level and height bonuses in hundreds; level and height determine the procession, or the concert at level 9/19. The actors use animation frames converted from the NES metasprites.

This is a native adaptation, not a cycle-exact emulator. The SG-1000 has 192 visible scanlines, two colours per eight-pixel pattern row, single-colour sprites, and no NES APU. Screen framing, colours, sprite priority, sound timbres and some animation and input timing consequently differ from the NES.

## Build and test

From the repository root, with Python 3 and GNU Make:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r sg1000/requirements.txt
make sg1000          # builds tetris.sg (also the default target)
```

The SG-1000 build does not use the `cc65` submodule. `make clean-sg1000` removes its generated files. To run the cartridge regression tests on a Z80 CPU emulator:

```sh
python -m pip install z80==1.2.0
make test-sg1000
```

The original 6502 disassembly is still buildable separately with `make tetris.nes`; `make compare` verifies the original ROM hash. See [INSTALL.md](INSTALL.md) for its prerequisites.

Thanks to [ejona86/taus](https://github.com/ejona86/taus) for disassembly information and [qalle2/nes-util](https://github.com/qalle2/nes-util) for the original NES CHR conversion tools.
