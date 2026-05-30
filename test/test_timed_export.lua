-- Timed TXD->PNG export with breakdown
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
local OUTDIR = BASE .. "/test/output"
dofile(BASE .. "/test/mta_mock.lua")

for _, m in ipairs({
    "core/binary/reader.lua","core/binary/writer.lua",
    "utils/bitops.lua","utils/math3d.lua","utils/tableutil.lua",
    "core/schema/types.lua","core/schema/registry.lua","core/schema/engine.lua",
    "core/base.lua",
    "dff/enums.lua","dff/primitives.lua","dff/plugins.lua",
    "dff/material.lua","dff/uvanim.lua","dff/framelist.lua",
    "dff/geometry.lua","dff/atomic.lua","dff/clump.lua","dff/dffio.lua",
    "txd/txdio.lua","texture/dds.lua","texture/bmp.lua",
}) do dofile(BASE .. "/" .. m) end
PNG = dofile(BASE .. "/texture/png.lua")

os.execute('mkdir "' .. OUTDIR .. '" 2>nul')

local txd = TXDIO:new(); txd:load(BASE .. "/example/hillrace.txd")
local texCount = #txd.textureDictionary.textures

local tDXT, tPNG, tOther = 0, 0, 0
local exported, failed = 0, 0
local tTotal = os.clock()

for i = 1, texCount do
    local st = txd.textureDictionary.textures[i].struct
    local fmtName = "?"
    for k,v in pairs(EnumD3DFormat) do if v==st.textureFormat then fmtName=k; break end end

    -- Phase 1: DXT decode
    local t0 = os.clock()
    local tex = txd.textureDictionary.textures[i]
    local dds = DDSTexture:new(); dds:convertFromTXD(tex)
    local bgra = dds:decodeToBGRA()
    local t1 = os.clock()
    tDXT = tDXT + (t1 - t0)

    if not bgra then failed=failed+1; print(string.format("[%d/%d] %s DECODE FAIL", i, texCount, st.name))
    else
        -- Phase 2: Build PixelData + PNG encode
        local px = PixelData:new()
        px.width=st.width; px.height=st.height; px.depth=32; px.rowAlignment=1; px.dataType="raw"; px.data=bgra
        local png = PNG:new(); png.width=px.width; png.height=px.height; png.pixels=px
        local pngData = png:save()
        local t2 = os.clock()
        tPNG = tPNG + (t2 - t1)

        -- Phase 3: Write file
        local safeName = st.name:gsub("[<>:\"/\\|?*]","_")
        local f = fileCreate(OUTDIR .. "/" .. safeName .. ".png")
        if f then fileWrite(f, pngData); fileClose(f) end
        tOther = tOther + (os.clock() - t2)

        print(string.format("[%d/%d] %-12s %4dx%-4d %6s DXT=%.1fs PNG=%.1fs",
            i, texCount, st.name, st.width, st.height, fmtName, t1-t0, t2-t1))
        exported = exported + 1
    end
end

local total = os.clock() - tTotal
print(string.format("\n=== %d exported, %d failed, %.1fs total ===", exported, failed, total))
print(string.format("DXT decode: %.1fs (%.0f%%), PNG encode: %.1fs (%.0f%%), Other: %.1fs",
    tDXT, tDXT/total*100, tPNG, tPNG/total*100, tOther))
