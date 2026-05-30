-- Verify DDS mipmap data after header fix
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")
for _, m in ipairs({
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua", "txd/txdio.lua", "texture/dds.lua",
}) do dofile(BASE .. "/" .. m) end
PNG = dofile(BASE .. "/texture/png.lua")

local txd = TXDIO:new()
txd:load(BASE .. "/example/hillrace.txd")
local tex = txd.textureDictionary.textures[1]

local dds = DDSTexture:new()
dds:convertFromTXD(tex)

local mipData = dds.mipmaps[1].data
print(string.format("Mipmap[1] size: %d bytes", #mipData))
print("First 16 bytes of mipmap (should be DXT data, NOT size header):")
for i = 1, math.min(16, #mipData) do
    io.write(string.format(" %02X", string.byte(mipData, i)))
end
print()

-- The first DXT block should start with actual color data
-- Not the size header 00 00 02 00
local r = Reader.new(mipData)
local c0 = r:u16()
local c1 = r:u16()
local indices = r:u32()
print(string.format("Block0: c0=0x%04X c1=0x%04X indices=0x%08X", c0, c1, indices))

-- Export PNG through TXDIO
local ok, pngData = pcall(txd.getTexture, txd, 1, "png")
if ok and pngData:sub(1,8) == "\137PNG\r\n\26\n" then
    local f = fileCreate(BASE .. "/test/output/hill1_final.png")
    fileWrite(f, pngData); fileClose(f)
    print(string.format("PNG: %d bytes (valid)", #pngData))
end

-- Also save clean DDS and raw DXT for Python
local f = fileCreate(BASE .. "/test/output/hill1_fixed.dds")
local w = Writer.new(); dds:write(w); fileWrite(f, w:build()); fileClose(f)
print(string.format("DDS: %d bytes", #(w:build())))

f = fileCreate(BASE .. "/test/output/dxt_fixed.bin")
fileWrite(f, mipData); fileClose(f)
print(string.format("Raw DXT for Python: %d bytes", #mipData))

-- Metadata for Python
f = fileCreate(BASE .. "/test/output/dxt_meta.txt")
fileWrite(f, string.format("%d %d %d\n", tex.struct.width, tex.struct.height, tex.struct.textureFormat))
fileClose(f)
