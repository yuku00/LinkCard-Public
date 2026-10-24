# SPDX-License-Identifier: GPL-3.0-or-later
import unittest
from codec import encode, decode, packets

class CodecTests(unittest.TestCase):
    def test_white(self):
        self.assertEqual(encode([255]*40000), b'\xff'*5000)
    def test_black(self):
        self.assertEqual(encode([0]*40000), bytes(5000))
    def test_upper_left_white_vertical_flip(self):
        pixels = [0]*40000
        pixels[0] = 255
        result = bytearray(5000)
        result[4975] = 0x80
        self.assertEqual(encode(pixels), result)
    def test_upper_left_black_vertical_flip(self):
        pixels = [255]*40000
        pixels[0] = 0
        result = bytearray(b'\xff'*5000)
        result[4975] = 0x7f
        self.assertEqual(encode(pixels), result)
    def test_lower_right(self):
        pixels = [0]*40000
        pixels[-1] = 255
        result = bytearray(5000)
        result[24] = 1
        self.assertEqual(encode(pixels), result)
    def test_bit_order(self):
        pixels = [0]*40000
        pixels[39800:39808] = [255, 0, 255, 0, 0, 255, 0, 255]
        self.assertEqual(encode(pixels)[0], 0xa5)
    def test_packet_payload(self):
        frame = encode([255]*40000)
        parts = packets(frame)
        self.assertEqual(len(parts), 25)
        self.assertTrue(all(len(p) == 201 and p[0] == 0xc7 for p in parts))
        self.assertEqual(b''.join(p[1:] for p in parts), frame)
    def test_roundtrip(self):
        source = [255 if (x*37+y*13)%11 < 5 else 0 for y in range(200) for x in range(200)]
        self.assertEqual(decode(encode(source)), source)
    def test_invalid_lengths(self):
        for n in [0, 39999, 40001]:
            with self.assertRaises(ValueError): encode([0]*n)
        for n in [0, 4999, 5001]:
            with self.assertRaises(ValueError): packets(bytes(n))
    def test_binary_cutoff(self):
        self.assertEqual(encode([100]*40000), bytes(5000))
        self.assertEqual(encode([101]*40000), b'\xff'*5000)

if __name__ == '__main__':
    unittest.main()
