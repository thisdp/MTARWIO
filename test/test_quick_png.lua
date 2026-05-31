-- Quick test: export just the first texture from hillrace.txd to PNG
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
    "col/colio.lua", "img/imgloader.lua",
}
for _, mod in ipairs(modules) do
    local ok, err = pcall(dofile, BASE .. "/" .. mod)
    if not ok then print("[FAIL] " .. mod .. ": " .. tostring(err)); return end
end

print("=== Quick PNG Export Test ===\n")

local txd = TXDIO:new()
txd:load(BASE .. "/example/hillrace.txd")
local tex = txd.textureDictionary.textures[1]
local st = tex.struct
print(string.format("Texture: %s  %dx%d  fmt=0x%08X  mips=%d", st.name, st.width, st.height, st.textureFormat, st.mipMapCount))

local start = os.clock()
local ok, pngData = pcall(txd.getTexture, txd, 1, "png")
local elapsed = os.clock() - start

if ok and type(pngData) == "string" and #pngData > 0 then
    local outPath = BASE .. "/test/output/test_hill1.png"
    local f = fileCreate(outPath)
    fileWrite(f, pngData)
    fileClose(f)
    local isPNG = pngData:sub(1, 8) == "\137PNG\r\n\26\n"
    print(string.format("OK: %d bytes, valid PNG: %s, time: %.2fs", #pngData, tostring(isPNG), elapsed))
    print("Saved: " .. outPath)
else
    print("FAIL: " .. tostring(pngData))
end
