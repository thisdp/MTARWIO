-- Export hill1 as DDS file
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")
for _, m in ipairs({
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "txd/txdio.lua", "texture/dds.lua", "texture/bmp.lua",
}) do dofile(BASE .. "/" .. m) end

local txd = TXDIO:new()
txd:load(BASE .. "/example/hillrace.txd")

-- Method 1: Save via getTexture (no format arg → DDS)
local ddsData = txd:getTexture(1)
local outDir = BASE .. "/test/output"
os.execute('mkdir "' .. outDir .. '" 2>nul')

local f = fileCreate(outDir .. "/hill1_method1.dds")
fileWrite(f, ddsData)
fileClose(f)
print(string.format("Method1 DDS: %d bytes", #ddsData))

-- Method 2: Manually construct DDS from convertFromTXD
local tex = txd.textureDictionary.textures[1]
local dds = DDSTexture:new()
dds:convertFromTXD(tex)
local w2 = Writer.new()
dds:write(w2)
local ddsData2 = w2:build()
f = fileCreate(outDir .. "/hill1_method2.dds")
fileWrite(f, ddsData2)
fileClose(f)
print(string.format("Method2 DDS: %d bytes", #ddsData2))

-- Also dump metadata
local st = tex.struct
print(string.format("\nTexture: %s  %dx%d  fmt=0x%08X  mips=%d  platform=%d",
    st.name, st.width, st.height, st.textureFormat, st.mipMapCount, st.platform))
print(string.format("rawData size: %d", #(tex.rawData or "")))

-- Show rawData first 16 bytes
local raw = tex.rawData or ""
print("rawData first 16 bytes (hex):")
for i = 1, math.min(16, #raw) do
    io.write(string.format(" %02X", string.byte(raw, i)))
end
print()

-- Check for palette header
if #raw >= 1024 + 4 then
    local r = Reader.new(raw)
    local palette = r:raw(1024)
    local firstSize = r:u32()
    local expected = 512 * 512  -- DXT1 512x512 = 131072 bytes (but for BGRA32: 512*512*4 = 1048576)
    print(string.format("After 1024-byte skip, first u32=%d (expected DXT1 mip=131072, RGBA would be 1048576)", firstSize))
end

-- Check DDS header values
print(string.format("\nDDS header: %dx%d, fmt=0x%08X, mips=%d",
    dds.ddsHeader.width, dds.ddsHeader.height,
    dds.ddsHeader.pixelFormat.d3dFormat,
    dds.ddsHeader.mipmapLevels))
print(string.format("DDS mipmap[1] size: %d", #dds.mipmaps[1].data))
