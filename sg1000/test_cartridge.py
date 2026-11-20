"""Execute the assembled ROM, providing controller input and one VBlank per step."""

import re
import unittest
from pathlib import Path

from z80 import Z80Machine

HERE = Path(__file__).resolve().parent
ROM = (HERE.parent / "tetris.sg").read_bytes()
RAM = {
    name: int(addr, 16)
    for name, addr in re.findall(
        r"^(\w+):\s+equ 0x([0-9a-f]+)", (HERE / "game.asm").read_text(), re.MULTILINE
    )
}
FRAME = int(
    re.search(r"^(\w+)=frame$", (HERE / "game.map").read_text(), re.MULTILINE)[1], 16
)


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
        if port & 255 == 0xBF:
            self.latch = None
            return 128
        self.assertEqual(port & 255, 0xDC)
        return 255 ^ self.buttons

    def write_port(self, port, value):
        port &= 255
        if port == 0xBF:
            if self.latch is None:
                self.latch = value
                return
            if value & 128:
                self.regs[value & 7] = self.latch
            else:
                self.address = ((value & 63) << 8) | self.latch
            self.latch = None
        elif port == 0xBE:
            self.vram[self.address] = value
            self.address = (self.address + 1) & 0x3FFF
        else:
            self.assertEqual(port, 0x7F)
            self.psg.append(value)

    def step(self, buttons=0):
        self.buttons = buttons
        if self.cpu.pc == FRAME:
            self.cpu.step_over_breakpoint()
        for _ in range(24):
            self.cpu.ticks_to_stop = 60000
            if self.cpu.run() & 1:
                self.assertEqual(self.cpu.pc, FRAME)
                self.assertTrue(0xC200 < self.cpu.sp < 0xC400)
                return
        self.fail("Game did not return to the frame loop")

    def tap(self, button):
        self.step()
        self.step(button)

    def types(self):
        self.tap(16)  # skip legal notice
        self.tap(16)  # title -> type and music selection

    def start(self):
        self.types()
        self.tap(16)  # level selection
        self.tap(16)

    def value(self, name):
        return self.cpu.memory[RAM[name]]

    def put(self, name, data):
        self.cpu.set_memory_block(RAM[name], bytes(data))

    def text(self, row, col, width):
        start = 0x1800 + row * 32 + col
        return self.vram[start : start + width]

    def test_boot_notice(self):
        self.assertIn(b"THIS IS AN UNOFFICIAL PORT", self.text(20, 0, 32))
        self.assertIn(b"NOT AN OFFICIAL TETRIS PRODUCT", self.text(22, 0, 32))

    def test_boot_controls_and_gravity(self):
        self.assertEqual(len(ROM), 49152)
        self.assertEqual(self.regs[1], 0xC0)
        self.assertEqual(self.regs[0], 2)
        self.start()
        self.step(4)
        self.assertEqual(self.value("posX"), 4)
        for _ in range(15):
            self.step(4)
        self.assertEqual(self.value("posX"), 4)
        self.step(4)
        self.assertEqual(self.value("posX"), 3)
        for _ in range(31):
            self.step()
        self.assertEqual(self.value("posY"), 3)
        for _ in range(48):
            self.step(1)  # Up no longer interrupts play or gravity
        self.assertEqual(self.value("posY"), 4)
        self.assertEqual(self.text(1, 19, 3), b"000")
        self.assertEqual(self.text(3, 24, 6), b"010000")
        self.assertIn(0xDA, self.psg)

    def test_rotation_collision(self):
        self.start()
        self.put("piece", [17, 0, 7])  # vertical I against the left wall
        self.step(16)  # still held from Start; not a fresh rotation
        self.step()
        self.step(32)
        self.assertEqual(self.value("piece"), 17)
        self.step(8)
        self.step()
        self.step(8)
        self.step(16)
        self.assertEqual(self.value("piece"), 18)
        self.step(32)
        self.assertEqual(self.value("piece"), 17)

    def setup_clear(self, n):
        # At the floor, one vertical I fills a column in n adjacent rows.
        board = bytearray(220)
        board[170] = 8  # marker above the four possible clear rows
        for row in range(22 - n, 22):
            board[row * 10 : (row + 1) * 10] = bytes([8] * 5 + [0] + [8] * 4)
        self.put("board", board)
        self.put("piece", [17, 5, 20])
        self.put("fall", [47])
        self.step()
        for _ in range(20):  # centre-out animation
            self.step()

    def test_clear_scores_and_compaction(self):
        for n, points in enumerate((40, 100, 300, 1200), 1):
            with self.subTest(n=n):
                self.setUp()
                self.start()
                self.setup_clear(n)
                self.assertEqual(self.value("lines"), n)
                self.assertEqual(self.text(5, 24, 6), f"{points:06}".encode())
                self.assertEqual(self.cpu.memory[RAM["board"] + 170 + n * 10], 8)

    def test_wipe_targets_only_completed_visible_rows(self):
        # Lock at the floor with a gap filled by the I. Also exercise a
        # nonadjacent full row, the first visible row, and a hidden row.
        self.start()
        board = bytearray(220)
        for row in (1, 2, 12, 21):
            board[row * 10 : row * 10 + 10] = bytes([8] * 10)
        board[215] = 0
        self.put("board", board)
        self.put("piece", [17, 5, 20])
        self.put("fall", [47])
        self.step()  # locked tiles on screen; wipe is waiting for VBlank
        expected = self.text(0, 0, 768)
        self.put("clock", [3])
        for phase in range(4):  # final phase reveals the compacted board
            for row in (3, 13, 22):
                for col in (16 - phase, 17 + phase):
                    index = 32 * row + col
                    self.assertNotEqual(expected[index], 0)
                    expected[index] = 0
            for _ in range(1 if phase == 0 else 4):
                self.step()
            self.assertEqual(self.text(0, 0, 768), expected)

    def test_level_transition(self):
        self.start()
        self.put("lines", [9, 0])
        self.put("toLevel", [1])
        self.setup_clear(1)
        self.assertEqual(self.value("level"), 1)
        self.assertEqual(self.value("toLevel"), 10)
        self.assertEqual(self.text(5, 24, 6), b"000080")

    def test_b_goal_and_restart(self):
        self.types()
        for button in (8, 16, 32, 8, 16):  # B, level menu, height, 1, start
            self.tap(button)
        self.assertEqual(self.value("lines"), 25)
        self.assertTrue(any(self.cpu.memory[RAM["board"] + 190 : RAM["board"] + 220]))
        self.put("lines", [1, 0])
        self.setup_clear(1)
        self.assertEqual(self.text(11, 12, 10), b" COMPLETE ")
        for _ in range(165):
            self.step()
        self.assertEqual(self.text(7, 14, 6), b"001040")
        self.assertEqual(self.value("trackId"), 7)
        self.tap(16)
        self.assertEqual(self.value("trackId"), 6)  # name entry; second place
        self.tap(1)
        self.tap(32)
        self.assertEqual(self.text(19, 9, 6), b"A     ")
        self.assertEqual(self.text(19, 16, 6), b"001040")
        self.assertEqual(self.text(21, 9, 6), b"TONY  ")

    def test_music_choices(self):
        for choice in range(4):
            with self.subTest(music=choice):
                self.setUp()
                self.types()
                for _ in range(choice):
                    self.tap(2)
                self.assertEqual(self.value("music"), choice)
                self.tap(16)
                self.tap(16)
                self.psg.clear()
                for _ in range(320):
                    self.step()
                if choice == 3:
                    self.assertEqual(self.psg, [])
                else:
                    self.assertIn(0xDA, self.psg)
                    self.assertTrue(any(0x90 <= x < 0x9F for x in self.psg))
                    self.assertTrue(any(0xB0 <= x < 0xBF for x in self.psg))

    def test_drum_hits_decay_between_beats(self):
        self.start()
        volume = 15
        run = hits = 0
        for _ in range(600):
            self.psg.clear()
            self.step()
            for cmd in self.psg:
                if cmd >= 0xF0:
                    volume = cmd & 15
            if volume == 15:
                run = 0
            else:
                hits += run == 0
                run += 1
                self.assertGreaterEqual(volume, 11)
                self.assertLessEqual(run, 2)
        self.assertGreater(hits, 5)

    def test_high_start(self):
        self.types()
        for button in (16, 2, 8, 8, 8, 8, 48):  # level 9, hold 2 while starting
            self.tap(button)
        self.assertEqual(self.value("level"), 19)
        self.assertEqual(self.value("toLevel"), 140)
        self.step()
        self.step()
        self.assertEqual(self.value("posY"), 3)

    def test_top_out(self):
        self.start()
        for frame in range(1400):
            self.step(0 if frame % 30 == 0 else 2)
            if self.text(11, 12, 10) == b"GAME  OVER":
                break
        else:
            self.fail("Unsteered soft drop never topped out")
        self.step(16)
        self.assertEqual(self.text(17, 9, 6), b"HOWARD")

    def test_all_three_rom_windows(self):
        labels = {
            n: int(a, 16)
            for a, n in (
                line.split("=") for line in (HERE / "game.map").read_text().splitlines()
            )
        }
        self.assertLess(labels["sceneTitle"], 0x4000)
        self.assertTrue(0x4000 <= labels["scenePlay"] < 0x8000)
        self.assertTrue(0x8000 <= labels["song7ch2"] < labels["romUsed"] <= 0xC000)
        self.assertGreater(labels["romUsed"], len(ROM) * 0.95)

    def test_attract_recording(self):
        self.tap(16)
        self.put("modeB", [1, 9, 5])
        for _ in range(1280):
            self.step()
        self.assertEqual(self.value("demo"), 1)
        for _ in range(4784):
            self.step()
        self.assertGreater(self.value("lines"), 0)
        self.assertEqual(self.value("demo"), 1)
        self.step()
        self.assertEqual(self.value("demo"), 0)
        self.assertEqual(self.value("trackId"), 4)
        self.assertEqual(self.value("modeB"), 1)
        self.assertEqual(self.value("startLevel"), 9)
        self.assertEqual(self.value("heightB"), 5)
        self.assertEqual(
            self.cpu.memory[RAM["ranks"] + 4 : RAM["ranks"] + 10], b"HOWARD"
        )

    def test_preview_toggle_and_danger_tempo(self):
        self.start()
        self.tap(48)
        self.assertEqual(self.text(11, 24, 4), bytes(4))
        self.tap(48)
        self.assertTrue(any(self.text(11, 24, 4)))
        self.cpu.memory[RAM["board"] + 70] = 8
        self.put("piece", [17, 5, 20])
        self.put("fall", [47])
        self.step()
        self.assertEqual(self.value("allegro"), 1)
        self.assertEqual(self.value("tempoBase"), 0)

    def test_concert_and_rocket(self):
        self.types()
        self.tap(8)
        self.tap(16)
        self.put("startLevel", [9, 5])
        self.tap(16)
        self.put("lines", [1, 0])
        self.setup_clear(1)
        for _ in range(700):
            self.step()
        self.assertEqual(self.value("trackId"), 7)
        self.assertEqual(self.value("castSize"), 8)
        self.assertGreater(self.value("actorCount"), 0)
        self.assertEqual(self.text(7, 14, 6), b"014400")
        self.setUp()
        self.start()
        self.put("score", [0, 0, 0x12])
        self.put("piece", [17, 5, 20])
        self.put("fall", [47])
        self.cpu.memory[RAM["board"] + 25] = 8  # force a spawn collision
        for _ in range(130):
            self.step()
        self.assertEqual(self.value("trackId"), 7)
        self.assertEqual(self.value("actorId"), 4)
        self.assertTrue(self.value("actorCount"))
        self.tap(16)
        self.assertEqual(self.value("trackId"), 6)
        self.assertEqual(self.text(19, 9, 6), b"HOWARD")
