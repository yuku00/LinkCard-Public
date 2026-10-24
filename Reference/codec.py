# SPDX-License-Identifier: GPL-3.0-or-later
"""Protocol reference only; no NFC dependencies, uploads or hardware writes."""
def encode(pixels):
    if len(pixels) != 40000:
        raise ValueError('expected 200x200 row-major pixels')
    out = bytearray(5000)
    for y in range(200):
        for x in range(200):
            if pixels[(199-y)*200+x] > 100:
                out[y*25+x//8] |= 1 << (7-x%8)
    return bytes(out)


def packets(frame):
    if len(frame) != 5000:
        raise ValueError('expected 5000 bytes')
    # CoreNFC parameters, NOT complete ISO15693 RF frames.
    return [b'\xc7'+frame[i:i+200] for i in range(0, 5000, 200)]


def decode(frame):
    if len(frame) != 5000:
        raise ValueError('expected 5000 bytes')
    return [255 if frame[(199-y)*25+x//8] & (1 << (7-x%8)) else 0
            for y in range(200) for x in range(200)]
