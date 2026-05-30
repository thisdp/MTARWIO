-- Profile PNG save: which step is slowest?
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")
for _, m in ipairs({
    "core/binary/reader.lua","core/binary/writer.lua",
    "utils/bitops.lua","utils/math3d.lua","utils/tableutil.lua",
    "core/schema/types.lua","core/schema/registry.lua","core/schema/engine.lua",
    "core/base.lua","texture/bmp.lua",
    "txd/txdio.lua","texture/dds.lua",
}) do dofile(BASE .. "/" .. m) end
PNG = dofile(BASE .. "/texture/png.lua")

local txd = TXDIO:new(); txd:load(BASE .. "/example/hillrace.txd")
local st = txd.textureDictionary.textures[1].struct
print(string.format("Profile: %s %dx%d DXT1", st.name, st.width, st.height))

-- Step 1: DXT decode
local t0 = os.clock()
local dds = DDSTexture:new(); dds:convertFromTXD(txd.textureDictionary.textures[1])
local bgra = dds:decodeToBGRA()
local t1 = os.clock()
print(string.format("DXT decode:   %6.2fs  (%d bytes RGBA)", t1-t0, #bgra))

-- Step 2: BGRA -> RGBA conversion
local t2 = os.clock()
local buf = Buffer.fromString(bgra)
local rgba = bgra_to_rgba(buf)  -- Note: need global access
local t3 = os.clock()
print(string.format("BGRA->RGBA:   %6.2fs", t3-t2))

-- Step 3: Build image data (filter bytes)
local t4 = os.clock()
local w, h = st.width, st.height
local imageDataRowSize = w * 4 + 1
local imageData = Buffer.new(h * imageDataRowSize)
for row = 0, h - 1 do
    local srcOff = row * w * 4
    local dstOff = row * imageDataRowSize
    imageData:writeu8(dstOff, 0)  -- filter: none
    imageData:copy(dstOff + 1, rgba, srcOff, 4 * w)
end
local t5 = os.clock()
print(string.format("Build imgdata:%6.2fs  (%d bytes)", t5-t4, h * imageDataRowSize))

-- Step 4: zlib deflate (the heavy part)
local t6 = os.clock()
local deflated, deflatedLen = zlib_deflate(imageData)
local t7 = os.clock()
print(string.format("zlib deflate: %6.2fs  (%d -> %d bytes, %.1f%%)", t7-t6, imageData:length(), deflatedLen, deflatedLen/imageData:length()*100))

-- Step 5: Build PNG chunks + CRC
local t8 = os.clock()
local outputLength = 8 + 25 + (8 + deflatedLen + 4) + 12
local output = Buffer.new(outputLength)
output:writestring(0, "\137PNG\r\n\26\n")
output:writeu32(8, byteswap32(13))
output:writestring(12, "IHDR")
output:writeu32(16, byteswap32(w))
output:writeu32(20, byteswap32(h))
output:writeu8(24, 8); output:writeu8(25, 6)
output:writeu8(26, 0); output:writeu8(27, 0); output:writeu8(28, 0)
output:writeu32(29, byteswap32(crc32(output, 12, 28)))
output:writeu32(33, byteswap32(deflatedLen))
output:writestring(37, "IDAT")
output:copy(41, deflated, 0, deflatedLen)
local x = 41 + deflatedLen
output:writeu32(x, byteswap32(crc32(output, 37, x-1)))
output:writeu32(x+4, 0)
output:writestring(x+8, "IEND")
output:writeu32(x+12, byteswap32(crc32(output, x+8, x+11)))
local t9 = os.clock()
print(string.format("Build PNG:    %6.2fs", t9-t8))

print(string.format("\nTotal:        %6.2fs", t9-t0))
