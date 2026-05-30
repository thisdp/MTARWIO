-- Test: decode a known DXT1 block and verify colors
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")
dofile(BASE .. "/core/binary/reader.lua")
dofile(BASE .. "/core/binary/writer.lua")
dofile(BASE .. "/utils/bitops.lua")
dofile(BASE .. "/utils/math3d.lua")
dofile(BASE .. "/utils/tableutil.lua")
dofile(BASE .. "/core/schema/types.lua")
dofile(BASE .. "/core/schema/registry.lua")
dofile(BASE .. "/core/schema/engine.lua")
dofile(BASE .. "/core/base.lua")
dofile(BASE .. "/texture/bmp.lua")
dofile(BASE .. "/txd/txdio.lua")
dofile(BASE .. "/texture/dds.lua")
PNG = dofile(BASE .. "/texture/png.lua")

print("=== DXT Color Verification ===\n")

local txd = TXDIO:new()
txd:load(BASE .. "/example/hillrace.txd")

-- Pick a small texture to check
local tex = txd.textureDictionary.textures[1]  -- hill1 512x512 DXT1
local st = tex.struct
print(string.format("Texture: %s  %dx%d  fmt=DXT1", st.name, st.width, st.height))

-- Step 1: My DXT decoder path
local dds = DDSTexture:new()
dds:convertFromTXD(tex)
local bgra = dds:decodeToBGRA()

-- Check first few pixels
local r = Reader.new(bgra)
print("\nFirst 4 pixels (BGRA from DXT decoder):")
for i = 1, 4 do
    local b, g, r_px, a = r:u8(), r:u8(), r:u8(), r:u8()
    print(string.format("  Pixel %d: R=%3d G=%3d B=%3d A=%3d", i, r_px, g, b, a))
end

-- Check a pixel at row 10
local offset = 10 * st.width * 4
local r2 = Reader.new(bgra)
r2.pos = offset + 1
local b, g, r_px, a = r2:u8(), r2:u8(), r2:u8(), r2:u8()
print(string.format("  Row10,Col0: R=%3d G=%3d B=%3d A=%3d", r_px, g, b, a))

-- Step 2: Go through the PNG pipeline and load back
local px = PixelData:new()
px.width = st.width; px.height = st.height; px.depth = 32
px.rowAlignment = 1; px.dataType = "raw"; px.data = bgra
local png = PNG:new()
png.width = px.width; png.height = px.height; png.pixels = px
local pngData = png:save()

-- Load the PNG back
local png2 = PNG:new()
png2:load(pngData)
print(string.format("\nAfter PNG roundtrip (%dx%d):", png2.width, png2.height))
local r3 = Reader.new(png2.pixels.data)
for i = 1, 4 do
    local b, g, r_px, a = r3:u8(), r3:u8(), r3:u8(), r3:u8()
    print(string.format("  Pixel %d: R=%3d G=%3d B=%3d A=%3d", i, r_px, g, b, a))
end

-- Step 3: Compare with BMP pipeline for an RGB texture (if available)
-- Create a test RGB texture in TXD
print("\n=== Test with synthetic RGB data ===\n")
local testTxd = TXDIO:new()
testTxd:add(nil, "test_rgb")
local testIdx = 1
local st2 = testTxd.textureDictionary.textures[testIdx].struct
st2.width = 2; st2.height = 2
st2.textureFormat = EnumD3DFormat.X8R8G8B8

-- Create known BGRA pixel data: red, green, blue, white
local testPixels = string.char(
    0, 0, 255, 255,  -- red:   B=0,G=0,R=255,A=255
    0, 255, 0, 255,  -- green: B=0,G=255,R=0,A=255
    255, 0, 0, 255,  -- blue:  B=255,G=0,R=0,A=255
    255, 255, 255, 255 -- white: B=255,G=255,R=255,A=255
)
testTxd.textureDictionary.textures[testIdx].rawData = testPixels

-- Export via BMP->PNG (existing path)
local ok1, pngBmp = pcall(testTxd.getTexture, testTxd, testIdx, "png")
if ok1 then
    local p3 = PNG:new(); p3:load(pngBmp)
    local r4 = Reader.new(p3.pixels.data)
    print("BMP->PNG pipeline (control group):")
    for i = 1, 4 do
        local b, g, r_px, a = r4:u8(), r4:u8(), r4:u8(), r4:u8()
        print(string.format("  Pixel %d: R=%3d G=%3d B=%3d A=%3d (expecting test pattern)", i, r_px, g, b, a))
    end
end

-- Now test via my DXT path
print("\nDXT->PNG pipeline:")
local ok2, pngDxt = pcall(txd.getTexture, txd, 1, "png")
if ok2 then
    local p4 = PNG:new(); p4:load(pngDxt)
    local r5 = Reader.new(p4.pixels.data)
    print(string.format("Roundtrip: %dx%d", p4.width, p4.height))
    print("First 4 pixels:")
    for i = 1, 4 do
        local b, g, r_px, a = r5:u8(), r5:u8(), r5:u8(), r5:u8()
        print(string.format("  Pixel %d: R=%3d G=%3d B=%3d A=%3d", i, r_px, g, b, a))
    end
    -- Check row 10
    local rr = Reader.new(p4.pixels.data)
    rr.pos = 10 * st.width * 4 + 1
    local b, g, r_px, a = rr:u8(), rr:u8(), rr:u8(), rr:u8()
    print(string.format("  Row10,Col0: R=%3d G=%3d B=%3d A=%3d", r_px, g, b, a))
end
