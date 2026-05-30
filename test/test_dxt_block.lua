-- Test DXT1 block decoder with known input
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")
for _, m in ipairs({"core/binary/reader.lua","core/binary/writer.lua",
    "utils/bitops.lua","utils/math3d.lua","utils/tableutil.lua",
    "core/schema/types.lua","core/schema/registry.lua","core/schema/engine.lua",
    "core/base.lua","txd/txdio.lua","texture/dds.lua","texture/bmp.lua"}) do
    dofile(BASE .. "/" .. m)
end
PNG = dofile(BASE .. "/texture/png.lua")

print("=== Synthetic DXT1 Block Test ===\n")

-- Create a DXT1 block manually:
-- c0 = 0xF800 (RGB565: R=31, G=0, B=0 → bright red #FF0000)
-- c1 = 0x07E0 (RGB565: R=0, G=63, B=0 → bright green #00FF00)
-- All indices = 0 (all pixels use c0 = red)
-- LE bytes: c0 lo=0x00, c0 hi=0xF8, c1 lo=0xE0, c1 hi=0x07, indices=0x00000000
local block = string.char(0x00, 0xF8, 0xE0, 0x07, 0x00, 0x00, 0x00, 0x00)

-- Create a minimal DDS with this block as the only mipmap
local dds = DDSTexture:new()
dds.ddsHeader = makeDDSHeader(4, 4, EnumD3DFormat.DXT1, 1)
dds.mipmaps = {{ data = block }}

-- Decode to BGRA
local bgra = dds:decodeToBGRA()
print(string.format("BGRA size: %d bytes (expected %d)", #bgra, 4*4*4))

-- Check all 16 pixels
local r = Reader.new(bgra)
print("\nDecoded pixels (should all be red R=255 G=0 B=0):")
local allCorrect = true
for i = 1, 16 do
    local b, g, r_px, a = r:u8(), r:u8(), r:u8(), r:u8()
    local correct = (r_px == 255 and g == 0 and b == 0 and a == 255)
    if not correct then
        print(string.format("  Pixel %2d: R=%3d G=%3d B=%3d A=%3d *** WRONG ***", i, r_px, g, b, a))
        allCorrect = false
    end
end
if allCorrect then print("  All 16 pixels: R=255 G=0 B=0 A=255 ✓") end

-- Test 2: mixed indices
-- c0 = 0x001F (R=0, G=0, B=31 → blue)
-- c1 = 0xFFE0 (R=31, G=63, B=0 → yellow)
-- indices: alternating 0,1,2,3,0,1,2,3,0,1,2,3,0,1,2,3
-- 0=00, 1=01, 2=10, 3=11 → 11100100 11100100 11100100 11100100 = 0xE4E4E4E4
print("\nTest 2: Alternating indices")
local block2 = string.char(0x1F, 0x00, 0xE0, 0xFF, 0xE4, 0xE4, 0xE4, 0xE4)

dds.mipmaps = {{ data = block2 }}
local bgra2 = dds:decodeToBGRA()
local r2 = Reader.new(bgra2)

-- c0 = blue (0,0,255), c1 = yellow (255,255,0)
-- c0>c1 is false (0x001F < 0xFFE0), so only 3 colors interpolated:
-- color2 = (0+255)/2=127, (0+255)/2=127, (255+0)/2=127 → gray
-- color3 = transparent black (0,0,0,0)
print("Expected: pixel0=blue(R=0,G=0,B=255), pixel1=yellow(R=255,G=255,B=0), pixel2=gray(R=127,G=127,B=127), pixel3=transparent(R=0,G=0,B=0,A=0)")
for i = 1, 4 do
    local b, g, r_px, a = r2:u8(), r2:u8(), r2:u8(), r2:u8()
    print(string.format("  Pixel %d: R=%3d G=%3d B=%3d A=%3d", i, r_px, g, b, a))
end

-- Test 3: c0 > c1 case
-- c0 = 0xF800 (red), c1 = 0x001F (blue)
-- c0 > c1 → 4-color mode, color2 = (2*red+blue)/3, color3 = (red+2*blue)/3
-- indices: 3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 → pixel0 uses color3
-- 3 = 11, rest = 0 → 0x00000003
print("\nTest 3: c0 > c1 (4-color mode), pixel0 uses color3")
local block3 = string.char(0x00, 0xF8, 0x1F, 0x00, 0x03, 0x00, 0x00, 0x00)

dds.mipmaps = {{ data = block3 }}
local bgra3 = dds:decodeToBGRA()
local r3 = Reader.new(bgra3)

-- color2 = (2*255+0)/3=170, (2*0+0)/3=0, (2*0+255)/3=85 → orange-ish
-- color3 = (255+2*0)/3=85, (0+2*0)/3=0, (0+2*255)/3=170 → purplish
print("Expected pixel0: color3 → R=85, G=0, B=170, A=255")
for i = 1, 2 do
    local b, g, r_px, a = r3:u8(), r3:u8(), r3:u8(), r3:u8()
    print(string.format("  Pixel %d: R=%3d G=%3d B=%3d A=%3d", i, r_px, g, b, a))
end

-- Test 4: Through complete TXD->PNG pipeline
print("\nTest 4: TXD->PNG pipeline with known DXT1 block")
local t4 = TXDIO:new()
t4.textureDictionary = TextureDictionary:new()
t4.textureDictionary.struct = TextureDictionaryStruct:new()
t4.textureDictionary.struct.textureCount = 1
t4.textureDictionary.struct.deviceID = EnumDeviceID.D3D9

local tn = TextureNative:new()
tn.struct = TextureNativeStruct:new()
tn.struct.width = 4; tn.struct.height = 4
tn.struct.textureFormat = EnumD3DFormat.DXT1
tn.struct.mipMapCount = 1; tn.struct.depth = 32
tn.struct.name = "test_dxt1"
tn.struct.platform = EnumDeviceID.D3D9
tn.rawData = block  -- all red block
tn.extension = TextureNativeExtension:new()
t4.textureDictionary.textures = {tn}

local ok, pngData = pcall(t4.getTexture, t4, 1, "png")
if ok and pngData then
    local p = PNG:new(); p:load(pngData)
    local r4 = Reader.new(p.pixels.data)
    print("Roundtrip pixels:")
    for i = 1, 4 do
        local b, g, r_px, a = r4:u8(), r4:u8(), r4:u8(), r4:u8()
        print(string.format("  Pixel %d: R=%3d G=%3d B=%3d A=%3d", i, r_px, g, b, a))
    end
end
