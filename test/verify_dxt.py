"""Verify DXT decode by comparing Lua output with reference Python decoder."""
import struct
import zlib
import os

BASE = r"e:\MTA-Server-DGS\mods\deathmatch\resources\rw\MTARW"
OUT = os.path.join(BASE, "test", "output")

# Read raw DXT data + metadata
with open(os.path.join(OUT, "dxt_raw.bin"), "rb") as f:
    dxt_raw = f.read()
with open(os.path.join(OUT, "dxt_meta.txt"), "r") as f:
    w, h, fmt = map(int, f.read().strip().split())
print(f"Texture: {w}x{h}  fmt=0x{fmt:08X}  DXT raw={len(dxt_raw)} bytes")

# Read Lua's PNG output
with open(os.path.join(OUT, "lua_output.png"), "rb") as f:
    lua_png = f.read()
print(f"Lua PNG: {len(lua_png)} bytes")


# ---- DXT1 Block Decoder ----
def decode_rgb565(v):
    r = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    b = v & 0x1F
    return (
        (r * 255 + 15) // 31,
        (g * 255 + 31) // 63,
        (b * 255 + 15) // 31,
    )

def decode_dxt1_block(data, offset, width, height, dst, bx, by):
    """Decode one DXT1 block. bx,by = block position in block-grid."""
    c0, c1, indices = struct.unpack_from("<HHI", data, offset)
    r0, g0, b0 = decode_rgb565(c0)
    r1, g1, b1 = decode_rgb565(c1)

    colors = [
        (r0, g0, b0, 255),
        (r1, g1, b1, 255),
    ]
    if c0 > c1:
        colors.append(((2*r0+r1)//3, (2*g0+g1)//3, (2*b0+b1)//3, 255))
        colors.append(((r0+2*r1)//3, (g0+2*g1)//3, (b0+2*b1)//3, 255))
    else:
        colors.append(((r0+r1)//2, (g0+g1)//2, (b0+b1)//2, 255))
        colors.append((0, 0, 0, 0))

    for row in range(4):
        py = by * 4 + row
        if py >= height:
            return
        for col in range(4):
            px = bx * 4 + col
            if px >= width:
                return
            idx = (indices >> (2 * (row * 4 + col))) & 3
            r, g, b, a = colors[idx]
            i = (py * width + px) * 4
            dst[i:i+4] = bytes([r, g, b, a])


def decode_dxt1_full(data, width, height):
    """Decode complete DXT1 texture to RGBA bytes."""
    result = bytearray(width * height * 4)
    blocks_x = (width + 3) // 4
    blocks_y = (height + 3) // 4
    for by in range(blocks_y):
        for bx in range(blocks_x):
            offset = (by * blocks_x + bx) * 8
            decode_dxt1_block(data, offset, width, height, result, bx, by)
    return bytes(result)


# ---- Decode to RGBA ----
py_rgba = decode_dxt1_full(dxt_raw, w, h)
print(f"Python decoded RGBA: {len(py_rgba)} bytes")

# Check first few pixels
print("First 8 pixels (Python, RGBA):")
for i in range(8):
    off = i * 4
    r, g, b, a = py_rgba[off], py_rgba[off+1], py_rgba[off+2], py_rgba[off+3]
    print(f"  Pixel {i+1}: R={r:3d} G={g:3d} B={b:3d} A={a:3d}")


# ---- PNG Encoder (pure Python) ----
def make_png(rgba, width, height):
    """Create a minimal PNG from RGBA byte data."""
    # Filter bytes: row filter 0 + scanline
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: None
        raw.extend(rgba[y * width * 4:(y + 1) * width * 4])

    def chunk(ctype, data):
        c = ctype + data
        crc = zlib.crc32(c) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + c + struct.pack(">I", crc)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw))

    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


py_png = make_png(py_rgba, w, h)
py_path = os.path.join(OUT, "python_output.png")
with open(py_path, "wb") as f:
    f.write(py_png)
print(f"\nPython PNG: {len(py_png)} bytes -> {py_path}")


# ---- Load Lua's PNG and extract RGBA ----
def load_png(data):
    """Minimal PNG loader for RGBA 8-bit."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "Not a PNG"
    pos = 8
    width = height = None
    idat_chunks = []

    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos+4])[0]
        ctype = data[pos+4:pos+8]
        chunk_data = data[pos+8:pos+8+length]
        pos += 12 + length

        if ctype == b"IHDR":
            width, height = struct.unpack(">II", chunk_data[:8])
            bitd, colort = chunk_data[8], chunk_data[9]
            assert colort == 6, f"Expected RGBA (6), got {colort}"
        elif ctype == b"IDAT":
            idat_chunks.append(chunk_data)
        elif ctype == b"IEND":
            break

    compressed = b"".join(idat_chunks)
    raw = zlib.decompress(compressed)

    # Unfilter
    bpp = 4
    stride = width * bpp + 1
    rgba = bytearray(width * height * 4)
    for y in range(height):
        filt = raw[y * stride]
        assert filt == 0, f"Unexpected filter {filt} at row {y}"
        src = y * stride + 1
        dst = y * width * 4
        rgba[dst:dst+width*4] = raw[src:src+width*4]

    return bytes(rgba), width, height


lua_rgba, lw, lh = load_png(lua_png)
print(f"\nLua PNG decoded: {lw}x{lh}, RGBA={len(lua_rgba)} bytes")

# ---- Compare ----
print("\n=== Pixel Comparison (first 16 pixels) ===")
print(f"{'#':>4s}  {'Python':>20s}  {'Lua':>20s}  {'Match':>6s}")
all_match = True
mismatches = 0
for i in range(min(16, w * h)):
    po = i * 4
    lo = i * 4
    pr, pg, pb, pa = py_rgba[po], py_rgba[po+1], py_rgba[po+2], py_rgba[po+3]
    lr, lg, lb, la = lua_rgba[lo], lua_rgba[lo+1], lua_rgba[lo+2], lua_rgba[lo+3]
    match = (pr == lr and pg == lg and pb == lb and pa == la)
    if not match:
        all_match = False
        mismatches += 1
    print(f"{i+1:4d}  R={pr:3d} G={pg:3d} B={pb:3d} A={pa:3d}  R={lr:3d} G={lg:3d} B={lb:3d} A={la:3d}  {'OK' if match else 'DIFF'}")

# Full pixel-by-pixel comparison
total_pixels = w * h
mismatches = 0
for i in range(total_pixels):
    po = i * 4
    lo = i * 4
    if py_rgba[po:po+4] != lua_rgba[lo:lo+4]:
        mismatches += 1

print(f"\n=== Total: {mismatches}/{total_pixels} mismatched pixels ({100*mismatches/total_pixels:.2f}%) ===")
if mismatches == 0:
    print("ALL PIXELS MATCH - DXT decoder is correct!")
