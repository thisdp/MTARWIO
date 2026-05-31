-- Debug: step-by-step DXT decode
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
    dofile(BASE .. "/" .. mod)
end

print("=== Debug DXT Decode ===\n")

local txd = TXDIO:new()
txd:load(BASE .. "/example/hillrace.txd")
local tex = txd.textureDictionary.textures[1]
local st = tex.struct
print(string.format("Texture: %s  %dx%d  fmt=0x%08X", st.name, st.width, st.height, st.textureFormat))

-- Step 1: Convert TXD to DDS
local dds = DDSTexture:new()
local ok = dds:convertFromTXD(tex)
print(string.format("Step 1 - convertFromTXD: %s", tostring(ok)))
print(string.format("  DDS header: %dx%d, fmt=0x%08X, mips=%d",
    dds.ddsHeader.width, dds.ddsHeader.height,
    dds.ddsHeader.pixelFormat.d3dFormat, dds.ddsHeader.mipmapLevels))
print(string.format("  mipmap[1] size: %d bytes", #dds.mipmaps[1].data))

-- Step 2: Decode to BGRA
local bgra = dds:decodeToBGRA()
print(string.format("Step 2 - decodeToBGRA: type=%s, len=%d", type(bgra), bgra and #bgra or 0))
if bgra then
    local expected = st.width * st.height * 4
    print(string.format("  Expected BGRA size: %d, actual: %d", expected, #bgra))
    -- Check first few bytes
    local header = bgra:sub(1, 8):byte(1, 8)
    print(string.format("  First bytes: %d %d %d %d %d %d %d %d", header[1], header[2], header[3], header[4], header[5], header[6], header[7], header[8]))
end

-- Step 3: Create PixelData and PNG
if bgra and #bgra > 0 then
    local px = PixelData:new()
    px.width = st.width
    px.height = st.height
    px.depth = 32
    px.rowAlignment = 1
    px.dataType = "raw"
    px.data = bgra

    local png = PNG:new()
    png.width = px.width
    png.height = px.height
    png.pixels = px

    local pngData = png:save()
    print(string.format("Step 3 - PNG save: len=%d", #pngData))
    print(string.format("  PNG signature match: %s", tostring(pngData:sub(1, 8) == "\137PNG\r\n\26\n")))
end

-- Step 4: Try through TXDIO.getTexture
print("\nStep 4 - TXDIO:getTexture(1, 'png')")
local ok2, result = pcall(txd.getTexture, txd, 1, "png")
print(string.format("  pcall ok=%s, result_type=%s, result_len=%d",
    tostring(ok2), type(result), type(result) == "string" and #result or 0))
