"""Execute the assembled ROM, providing controller input and one VBlank per step."""
from pathlib import Path
import re
import unittest

from z80 import Z80Machine

HERE = Path(__file__).resolve().parent
ROM = (HERE.parent / 'tetris.sg').read_bytes()
RAM = {name: int(addr, 16) for name, addr in re.findall(
    r'^(\w+):\s+equ 0x([0-9a-f]+)', (HERE / 'game.asm').read_text(), re.M)}
FRAME = int(re.search(r'^(\w+)=frame$', (HERE / 'game.map').read_text(), re.M)[1], 16)


class Cartridge(unittest.TestCase):
    def setUp(self):
        self.cpu = Z80Machine()
        self.cpu.set_memory_block(0, ROM)
        self.vram = bytearray(0x4000)
        self.regs = bytearray(8)
        self.psg = []
        self.latch = None
        self.buttons = 0
        self.cpu.set_input_callback(self.read_port)
        self.cpu.set_output_callback(self.write_port)
        self.cpu.set_breakpoint(FRAME)
        self.step()  # reset through to the first controller poll

    def read_port(self, port):
        if port & 255 == 0xbf:
            self.latch = None
            return 128
        self.assertEqual(port & 255, 0xdc)
        return 255 ^ self.buttons

    def write_port(self, port, value):
        port &= 255
        if port == 0xbf:
            if self.latch is None:
                self.latch = value
                return
            if value & 128:
                self.regs[value & 7] = self.latch
            else:
                self.address = ((value & 63) << 8) | self.latch
            self.latch = None
        elif port == 0xbe:
            self.vram[self.address] = value
            self.address = (self.address+1) & 0x3fff
        else:
            self.assertEqual(port, 0x7f)
            self.psg.append(value)

    def step(self, buttons=0):
        self.buttons = buttons
        if self.cpu.pc == FRAME:
            self.cpu.step_over_breakpoint()
        for _ in range(8):
            self.cpu.ticks_to_stop = 60000
            if self.cpu.run() & 1:
                self.assertEqual(self.cpu.pc, FRAME)
                self.assertTrue(0xc200 < self.cpu.sp < 0xc400)
                return
        self.fail('Game did not return to the frame loop')

    def value(self, name):
        return self.cpu.memory[RAM[name]]

    def put(self, name, data):
        self.cpu.set_memory_block(RAM[name], bytes(data))

    def text(self, row, col, width):
        start = 0x1800 + row*32 + col
        return self.vram[start:start+width]

    def test_boot_controls_and_gravity(self):
        self.assertEqual(len(ROM), 16384)
        self.assertEqual(self.regs[1], 0xc0)
        self.assertEqual(self.text(11, 6, 9), b'GAME TYPE')
        self.step(16)
        self.step(4)
        self.assertEqual(self.value('posX'), 4)
        for _ in range(15):
            self.step(4)
        self.assertEqual(self.value('posX'), 4)
        self.step(4)
        self.assertEqual(self.value('posX'), 3)
        for _ in range(31):
            self.step()
        self.assertEqual(self.value('posY'), 3)
        self.step(1)
        self.assertEqual(self.text(11, 11, 10), b'  PAUSED  ')
        for _ in range(49):
            self.step()
        self.assertEqual(self.value('posY'), 3)
        self.step(1)
        self.assertNotEqual(self.text(11, 11, 10), b'  PAUSED  ')
        self.assertIn(0x96, self.psg)

    def test_rotation_collision(self):
        self.step(16)
        self.put('piece', [17, 0, 7])  # vertical I against the left wall
        self.step(16)  # still held from Start; not a fresh rotation
        self.step()
        self.step(32)
        self.assertEqual(self.value('piece'), 17)
        self.step(8)
        self.step()
        self.step(8)
        self.step(16)
        self.assertEqual(self.value('piece'), 18)
        self.step(32)
        self.assertEqual(self.value('piece'), 17)

    def setup_clear(self, n):
        # At the floor, one vertical I fills a column in n adjacent rows.
        board = bytearray(220)
        board[170] = 8  # marker above the four possible clear rows
        for row in range(22-n, 22):
            board[row*10:(row+1)*10] = bytes([8]*5+[0]+[8]*4)
        self.put('board', board)
        self.put('piece', [17, 5, 20])
        self.put('fall', [47])
        self.step()
        for _ in range(20):  # centre-out animation
            self.step()

    def test_clear_scores_and_compaction(self):
        for n, points in enumerate((40, 100, 300, 1200), 1):
            with self.subTest(n=n):
                self.setUp()
                self.step(16)
                self.setup_clear(n)
                self.assertEqual(self.value('lines'), n)
                self.assertEqual(self.text(7, 23, 6), f'{points:06}'.encode())
                self.assertEqual(self.cpu.memory[RAM['board']+170+n*10], 8)

    def test_level_transition(self):
        self.step(16)
        self.put('lines', [9, 0])
        self.put('toLevel', [1])
        self.setup_clear(1)
        self.assertEqual(self.value('level'), 1)
        self.assertEqual(self.value('toLevel'), 10)
        self.assertEqual(self.text(7, 23, 6), b'000080')

    def test_b_goal_and_restart(self):
        for buttons in (8, 2, 0, 2, 8, 16):  # type B, height 1, start
            self.step(buttons)
        self.assertEqual(self.value('lines'), 25)
        self.assertTrue(any(self.cpu.memory[RAM['board']+190:RAM['board']+220]))
        self.put('lines', [1, 0])
        self.setup_clear(1)
        self.assertEqual(self.text(11, 11, 10), b' COMPLETE ')
        self.assertEqual(self.text(7, 23, 6), b'001040')
        self.step(16)
        self.assertEqual(self.text(11, 6, 9), b'GAME TYPE')

    def test_music_choices(self):
        for choice in range(4):
            with self.subTest(music=choice):
                self.setUp()
                self.step(1)  # wrap from TYPE to MUSIC
                for _ in range(choice):
                    self.step(8)
                    self.step()
                self.assertEqual(self.value('music'), choice)
                self.step(16)
                self.psg.clear()
                for _ in range(320):
                    self.step()
                if choice == 3:
                    self.assertEqual(self.psg, [])
                else:
                    for volume in (0x96, 0xb9, 0xd9):
                        self.assertIn(volume, self.psg)

    def test_high_start(self):
        for buttons in (2, 4, 16):  # select level, wrap from 0 to 19, start
            self.step(buttons)
        self.assertEqual(self.value('level'), 19)
        self.assertEqual(self.value('toLevel'), 140)
        self.step()
        self.step()
        self.assertEqual(self.value('posY'), 3)

    def test_top_out(self):
        self.step(16)
        for frame in range(1400):
            self.step(0 if frame % 30 == 0 else 2)
            if self.text(11, 11, 10) == b'GAME  OVER':
                break
        else:
            self.fail('Unsteered soft drop never topped out')
        self.step(16)
        self.assertEqual(self.text(11, 6, 9), b'GAME TYPE')
