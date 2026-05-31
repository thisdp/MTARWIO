-- Export one texture with correct PNG loading
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")

local modules = {
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "dff/material.lua", "dff/uvanim.lua", "dff/framelist.lua",
    "dff/geometry.lua", "dff/atomic.lua", "dff/clump.lua", "dff/dffio.lua",
    "txd/txdio.lua", "texture/dds.lua", "texture/bmp.lua",
}
for _, mod in ipairs(modules) do dofile(BASE .. "/" .. mod) end
PNG = dofile(BASE .. "/texture/png.lua")

print("=== Single PNG Export ===\n")

local txd = TXDIO:new()
txd:load(BASE .. "/example/hillrace.txd")
local tex = txd.textureDictionary.textures[1]
local st = tex.struct
print(string.format("Texture: %s  %dx%d  fmt=0x%08X", st.name, st.width, st.height, st.textureFormat))

local ok, pngData = pcall(txd.getTexture, txd, 1, "png")
if ok and type(pngData) == "string" and #pngData > 100 then
    local isPNG = pngData:sub(1,8) == "\137PNG\r\n\26\n"
    local outPath = BASE .. "/test/output/hill1_fixed.png"
    local f = fileCreate(outPath); fileWrite(f, pngData); fileClose(f)
    print(string.format("OK: %d bytes, valid PNG: %s", #pngData, tostring(isPNG)))
    print("Saved: " .. outPath)

    -- Load back and check first pixels
    local p = PNG:new(); p:load(pngData)
    local r = Reader.new(p.pixels.data)
    print(string.format("Loaded: %dx%d", p.width, p.height))
    print("First 8 pixels (after PNG roundtrip, BGRA):")
    for i = 1, 8 do
        local b, g, r_px, a = r:u8(), r:u8(), r:u8(), r:u8()
        print(string.format("  Pixel %d: R=%3d G=%3d B=%3d A=%3d", i, r_px, g, b, a))
    end
    -- Row 10
    r.pos = 10 * st.width * 4 + 1
    local b, g, r_px, a = r:u8(), r:u8(), r:u8(), r:u8()
    print(string.format("  Row10,Col0: R=%3d G=%3d B=%3d A=%3d", r_px, g, b, a))
else
    print("FAIL: " .. tostring(pngData))
end
