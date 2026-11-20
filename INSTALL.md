# Building the original NES disassembly

For the native SG-1000 port, follow the [cartridge build instructions](README.md#build-and-test) instead.

The NES build requires GNU Make, a C compiler, Git, Python 3, and Pillow. On Windows use a Unix-like build environment. From the root of this checkout:

```sh
git submodule update --init
python3 -m venv .venv
. .venv/bin/activate
python -m pip install Pillow
make tetris.nes
make compare
```

This builds Tetris (U) [!].nes (`md5: ec58574d96bee8c8927884ae6e7a2508`).
