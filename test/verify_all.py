"""Test all DXT byte order and channel order variants."""
import struct, zlib, os

BASE = r"e:\MTA-Server-DGS\mods\deathmatch\resources\rw\MTARW"
OUT = os.path.join(BASE, "test", "output")

with open(os.path.join(OUT, "dxt_raw.bin"), "rb") as f:
    dxt_raw = f.read()
with open(os.path.join(OUT, "dxt_meta.txt"), "r") as f:
    w, h, fmt = map(int, f.read().strip().split())

def decode_rgb565_le(v):
    """Standard RGB565 little-endian."""
    r = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    b = v & 0x1F
    return ((r * 255 + 15) // 31, (g * 255 + 31) // 63, (b * 255 + 15) // 31)

def decode_bgr565_le(v):
    """BGR565 (R/B swapped channels)."""
    b = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    r = v & 0x1F
    return ((r * 255 + 15) // 31, (g * 255 + 31) // 63, (b * 255 + 15) // 31)

def byteswap16(v):
    return ((v & 0xFF) << 8) | ((v >> 8) & 0xFF)

def byteswap32(v):
    return ((v & 0xFF) << 24) | ((v & 0xFF00) << 8) | ((v >> 8) & 0xFF00) | ((v >> 24) & 0xFF)

def decode_dxt1(data, width, height, decode_func, swap_colors=False, swap_indices=False):
    """Decode DXT1 with optional byte-swapping."""
    result = bytearray(width * height * 4)
    blocks_x = (width + 3) // 4
    blocks_y = (height + 3) // 4
    for by in range(blocks_y):
        for bx in range(blocks_x):
            offset = (by * blocks_x + bx) * 8
            c0, c1, indices = struct.unpack_from("<HHI", data, offset)
            if swap_colors:
                c0 = byteswap16(c0)
                c1 = byteswap16(c1)
            if swap_indices:
                indices = byteswap32(indices)
            r0, g0, b0 = decode_func(c0)
            r1, g1, b1 = decode_func(c1)
            colors = [(r0, g0, b0, 255), (r1, g1, b1, 255)]
            if c0 > c1:  # compare ORIGINAL values before any interpretation
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

# All 4 variants
variants = [
    ("v1_rgb565_le",   decode_rgb565_le, False, False, "RGB565 LE (standard)"),
    ("v2_bgr565_le",   decode_bgr565_le, False, False, "BGR565 LE (R/B swapped)"),
    ("v3_rgb565_be",   decode_rgb565_le, True,  True,  "RGB565 BE (byteswapped)"),
    ("v4_bgr565_be",   decode_bgr565_le, True,  True,  "BGR565 BE (both swapped)"),
    ("v5_rgb565_beswap", decode_rgb565_le, True, False, "RGB565 color-swap only, indices LE"),
    ("v6_rgb565_idxswap", decode_rgb565_le, False, True, "RGB565 indices-swap only, colors LE"),
]

print("=== Generating all DXT decode variants ===\n")
for name, func, swap_c, swap_i, desc in variants:
    rgba = decode_dxt1(dxt_raw, w, h, func, swap_c, swap_i)
    png = make_png(rgba, w, h)
    path = os.path.join(OUT, f"{name}.png")
    with open(path, "wb") as f:
        f.write(png)
    # Sample pixels from different regions
    top_left = rgba[0:16]      # (0,0)-(3,0)
    mid = rgba[(128*512+256)*4:(128*512+260)*4]  # row 128, col 256
    bot = rgba[(500*512+200)*4:(500*512+216)*4]  # row 500, col 200
    def fmt_px(data, off):
        r, g, b = data[off], data[off+1], data[off+2]
        return f"R={r:3d} G={g:3d} B={b:3d}"
    print(f"{desc}:")
    print(f"  Top-left:  {fmt_px(top_left, 0)}  {fmt_px(top_left, 4)}")
    print(f"  Mid:       {fmt_px(mid, 0)}  {fmt_px(mid, 4)}")
    print(f"  Bottom:    {fmt_px(bot, 0)}  {fmt_px(bot, 4)}")
    print(f"  Saved: {name}.png\n")

os.system(f'start "" "{OUT}"')
