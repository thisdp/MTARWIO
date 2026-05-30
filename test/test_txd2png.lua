-- test_txd2png.lua — Export all TXD textures to PNG
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
local OUTDIR = BASE .. "/test/output"

dofile(BASE .. "/test/mta_mock.lua")

local modules = {
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "dff/enums.lua", "dff/primitives.lua", "dff/plugins.lua",
    "dff/material.lua", "dff/uvanim.lua", "dff/framelist.lua",
    "dff/geometry.lua", "dff/atomic.lua", "dff/clump.lua", "dff/dffio.lua",
    "txd/txdio.lua", "texture/dds.lua", "texture/bmp.lua",
    "col/colio.lua", "img/imgloader.lua",
}
for _, mod in ipairs(modules) do
    local ok = pcall(dofile, BASE .. "/" .. mod)
    if ok then print("[OK]   " .. mod) else print("[FAIL] " .. mod) end
end
PNG = dofile(BASE .. "/texture/png.lua")

print("\n========== TXD -> PNG ==========\n")
os.execute('mkdir "' .. OUTDIR .. '" 2>nul')

local txd = TXDIO:new()
txd:load(BASE .. "/example/hillrace.txd")
local texCount = #txd.textureDictionary.textures
local exported, failed = 0, 0
local tStart = os.clock()

for i = 1, texCount do
    local st = txd.textureDictionary.textures[i].struct
    local fmtName = "?"
    for k, v in pairs(EnumD3DFormat) do if v == st.textureFormat then fmtName = k; break end end

    io.write(string.format("[%d/%d] %s  %dx%d  %s ... ", i, texCount, st.name, st.width, st.height, fmtName))
    io.flush()

    local bStart = os.clock()
    local okExport, pngData = pcall(txd.getTexture, txd, i, "png")
    local elapsed = os.clock() - bStart

    if okExport and type(pngData) == "string" and pngData:sub(1,8) == "\137PNG\r\n\26\n" then
        local safeName = st.name:gsub("[<>:\"/\\|?*]", "_")
        local f = fileCreate(OUTDIR .. "/" .. safeName .. ".png")
        if f then fileWrite(f, pngData); fileClose(f) end
        print(string.format("OK (%d bytes, %.1fs)", #pngData, elapsed))
        exported = exported + 1
    else
        print("FAIL: " .. tostring(pngData))
        failed = failed + 1
    end
end

print(string.format("\n========== %d PNG, %d failed, %.1fs total ==========", exported, failed, os.clock() - tStart))
print("Output: " .. OUTDIR)
