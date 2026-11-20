# NES Tetris on the Sega SG-1000

**[Download the playable cartridge: tetris.sg](tetris.sg)** (16 KiB). Open the `.sg` file in an SG-1000 emulator such as SMS Plus GX, using controller 1. No BIOS, NES ROM, or RAM expansion is needed. Use NTSC / 60 Hz for the original gravity and music timing.

On the menu, use **Up/Down** to choose a setting, **Left/Right** to change it, and **Button 1** to start. **A-Type** is endless; **B-Type** challenges you to clear 25 lines, with a starting garbage height of 0–5. Both support starting levels 0–19.

| During play | Controller 1 |
| --- | --- |
| Move | Left / Right (hold to repeat) |
| Soft drop | Hold Down; press again for each new piece |
| Rotate clockwise / counterclockwise | Button 1 / Button 2 |
| Pause / resume | Up |
| Return to menu after a win or loss | Button 1 |

## About the port

This is a native Z80 implementation, not NES emulation. It uses the SG-1000's 1 KiB of RAM, TMS9918A Graphics I display, and SN76489 sound chip. The build translates the disassembly's 19 piece orientations, rotation and spawn tables, NTSC gravity table, title art, typeface, block graphics, and three gameplay tunes. The game includes NES-style delayed auto-shift, immediate lock on a failed drop, centre-out line clears, next-piece preview, piece counts, and level-dependent scoring and colours.

The menus and HUD are adapted to the smaller display. Best scores last until reset. The NES demo, name entry and animated endings are not included.

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
