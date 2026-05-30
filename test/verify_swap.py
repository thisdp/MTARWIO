"""Test if RenderWare DXT uses BGR565 instead of RGB565."""
import struct
import zlib
import os

BASE = r"e:\MTA-Server-DGS\mods\deathmatch\resources\rw\MTARW"
OUT = os.path.join(BASE, "test", "output")

with open(os.path.join(OUT, "dxt_raw.bin"), "rb") as f:
    dxt_raw = f.read()
with open(os.path.join(OUT, "dxt_meta.txt"), "r") as f:
    w, h, fmt = map(int, f.read().strip().split())

def decode_bgr565(v):
    """BGR565: bits 0-4=R, 5-10=G, 11-15=B (swapped from RGB565)"""
    b = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    r = v & 0x1F
    return ((r * 255 + 15) // 31, (g * 255 + 31) // 63, (b * 255 + 15) // 31)

def decode_rgb565(v):
    r = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    b = v & 0x1F
    return ((r * 255 + 15) // 31, (g * 255 + 31) // 63, (b * 255 + 15) // 31)

def decode_dxt1(data, width, height, decode_func):
    result = bytearray(width * height * 4)
    blocks_x = (width + 3) // 4
    blocks_y = (height + 3) // 4
    for by in range(blocks_y):
        for bx in range(blocks_x):
            offset = (by * blocks_x + bx) * 8
            c0, c1, indices = struct.unpack_from("<HHI", data, offset)
            r0, g0, b0 = decode_func(c0)
            r1, g1, b1 = decode_func(c1)
            colors = [(r0, g0, b0, 255), (r1, g1, b1, 255)]
            if c0 > c1:
                colors.append(((2*r0+r1)//3, (2*g0+g1)//3, (2*b0+b1)//3, 255))
                colors.append(((r0+2*r1)//3, (g0+2*g1)//3, (b0+2*b1)//3, 255))
            else:
                colors.append(((r0+r1)//2, (g0+g1)//2, (b0+b1)//2, 255))
                colors.append((0, 0, 0, 0))
            for row in range(4):
                py = by * 4 + row
                if py >= height: break
                for col in range(4):
                    px = bx * 4 + col
                    if px >= width: break
                    idx = (indices >> (2 * (row * 4 + col))) & 3
                    r, g, b, a = colors[idx]
                    i = (py * width + px) * 4
                    result[i:i+4] = bytes([r, g, b, a])
    return bytes(result)

def make_png(rgba, width, height):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * width * 4:(y + 1) * width * 4])
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b"")

# Generate both versions
rgba_std = decode_dxt1(dxt_raw, w, h, decode_rgb565)
rgba_swap = decode_dxt1(dxt_raw, w, h, decode_bgr565)

# Compare first few pixels
print("=== First 8 pixels comparison ===")
print(f"{'#':>4s}  {'RGB565 (standard)':>24s}  {'BGR565 (swapped)':>24s}")
for i in range(8):
    so = i * 4
    sr, sg, sb = rgba_std[so], rgba_std[so+1], rgba_std[so+2]
    wo = i * 4
    wr, wg, wb = rgba_swap[wo], rgba_swap[wo+1], rgba_swap[wo+2]
    print(f"{i+1:4d}  R={sr:3d} G={sg:3d} B={sb:3d}        R={wr:3d} G={wg:3d} B={wb:3d}")

# Save both PNGs
with open(os.path.join(OUT, "python_rgb565.png"), "wb") as f:
    f.write(make_png(rgba_std, w, h))
with open(os.path.join(OUT, "python_bgr565.png"), "wb") as f:
    f.write(make_png(rgba_swap, w, h))
print("\nSaved: python_rgb565.png (standard) and python_bgr565.png (swapped)")
print(f"Python RGB565 PNG = {len(make_png(rgba_std, w, h))} bytes")
print(f"Python BGR565 PNG = {len(make_png(rgba_swap, w, h))} bytes")

# Also check the first DXT block raw values
print("\n=== First DXT block analysis ===")
c0, c1, indices = struct.unpack_from("<HHI", dxt_raw, 0)
print(f"c0=0x{c0:04X} ({c0}), c1=0x{c1:04X} ({c1}), indices=0x{indices:08X}")
print(f"c0 binary: {c0:016b}")
print(f"  RGB565: R={((c0>>11)&0x1F):2d} G={((c0>>5)&0x3F):2d} B={(c0&0x1F):2d}")
print(f"  BGR565: B={((c0>>11)&0x1F):2d} G={((c0>>5)&0x3F):2d} R={(c0&0x1F):2d}")
print(f"c1 binary: {c1:016b}")
print(f"  RGB565: R={((c1>>11)&0x1F):2d} G={((c1>>5)&0x3F):2d} B={(c1&0x1F):2d}")
print(f"  BGR565: B={((c1>>11)&0x1F):2d} G={((c1>>5)&0x3F):2d} R={(c1&0x1F):2d}")
