#!/usr/bin/env python3
"""png.py: read PNG and ICO files for tests/ctlhq-icon-sheet/run.sh, standard library only.

Usage:
  png.py size FILE         print WxH from the PNG header, or "not-png"
  png.py pixel FILE X Y    print the pixel at X,Y as r,g,b,a (8-bit RGB or RGBA PNGs), or
                           "outside" when X,Y lies outside the image
  png.py ico FILE          print the size of each image in an ICO file, read from the PNG
                           header inside each entry, for example "16 32 48"
"""
import struct
import sys
import zlib

SIG = b"\x89PNG\r\n\x1a\n"


def size(data):
    if data[:8] != SIG:
        return None
    return struct.unpack(">II", data[16:24])


def pixel(data, x, y):
    pos, idat, head = 8, b"", None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    w, h, depth, ctype, _, _, interlace = head
    if depth != 8 or ctype not in (2, 6) or interlace:
        sys.exit(f"png.py: unsupported PNG (depth {depth}, colour type {ctype}, interlace {interlace})")
    if not (0 <= x < w and 0 <= y < h):
        return ["outside"]
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp
    prev = bytearray(stride)
    for row in range(y + 1):
        f = raw[row * (stride + 1)]
        line = bytearray(raw[row * (stride + 1) + 1:(row + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
    px = list(prev[x * bpp:(x + 1) * bpp])
    return px + [255] if bpp == 3 else px


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    data = open(path, "rb").read()
    if cmd == "size":
        s = size(data)
        print("%dx%d" % s if s else "not-png")
    elif cmd == "pixel":
        print(",".join(str(v) for v in pixel(data, int(sys.argv[3]), int(sys.argv[4]))))
    elif cmd == "ico":
        _, kind, count = struct.unpack("<HHH", data[:6])
        sizes = []
        for i in range(count):
            n, off = struct.unpack("<II", data[6 + 16 * i + 8:6 + 16 * i + 16])
            s = size(data[off:off + n])
            sizes.append(str(s[0]) if s and s[0] == s[1] else "bad")
        print(" ".join(sizes) if kind == 1 else "not-ico")


if __name__ == "__main__":
    main()
