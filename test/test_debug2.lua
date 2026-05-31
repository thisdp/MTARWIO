-- Debug step 3+: PNG encoding
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")

local modules = {
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "dff/material.lua", "dff/uvanim.lua", "dff/framelist.lua",
    "dff/geometry.lua", "dff/atomic.lua", "dff/clump.lua", "dff/dffio.lua",
    "txd/txdio.lua", "texture/dds.lua", "texture/bmp.lua", "texture/png.lua",
}
for _, mod in ipairs(modules) do
    local ret = dofile(BASE .. "/" .. mod)
    if mod == "texture/png.lua" then PNG = ret end
end

print("=== Debug DXT->PNG Pipeline ===\n")

local txd = TXDIO:new()
txd:load(BASE .. "/example/hillrace.txd")
local tex = txd.textureDictionary.textures[1]
local st = tex.struct

-- Decode to BGRA via DDS
local dds = DDSTexture:new()
dds:convertFromTXD(tex)
local bgra = dds:decodeToBGRA()
print(string.format("BGRA decoded: %d bytes (expected %d)", #bgra, st.width * st.height * 4))

-- Check a few pixel values (not all zeros)
local r = Reader.new(bgra)
local b1, g1, r1, a1 = r:u8(), r:u8(), r:u8(), r:u8()
print(string.format("Pixel[0]: R=%d G=%d B=%d A=%d", r1, g1, b1, a1))

-- Create PixelData
local px = PixelData:new()
px.width = st.width
px.height = st.height
px.depth = 32
px.rowAlignment = 1
px.dataType = "raw"
px.data = bgra

-- PNG save
local png = PNG:new()
png.width = px.width
png.height = px.height
png.pixels = px
local pngData = png:save()
print(string.format("PNG data: %d bytes", #pngData))
local sig = string.byte(pngData, 1)
local sig8 = {string.byte(pngData, 1, 8)}
print(string.format("PNG sig: %d %d %d %d %d %d %d %d", sig8[1], sig8[2], sig8[3], sig8[4], sig8[5], sig8[6], sig8[7], sig8[8]))
print(string.format("Valid PNG: %s", tostring(pngData:sub(1,8) == "\137PNG\r\n\26\n")))

-- Save to file
local outPath = BASE .. "/test/output/test_hill1_debug.png"
os.execute('mkdir "' .. BASE .. '/test/output" 2>nul')
local f = fileCreate(outPath)
fileWrite(f, pngData)
fileClose(f)
print("Saved: " .. outPath)
