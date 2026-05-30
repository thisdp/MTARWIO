-- Compare fast vs slow PNG on real texture
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")
for _,m in ipairs({
    "core/binary/reader.lua","core/binary/writer.lua",
    "utils/bitops.lua","utils/math3d.lua","utils/tableutil.lua",
    "core/schema/types.lua","core/schema/registry.lua","core/schema/engine.lua",
    "core/base.lua","texture/bmp.lua",
    "txd/txdio.lua","texture/dds.lua",
}) do dofile(BASE .. "/" .. m) end
PNG = dofile(BASE .. "/texture/png.lua")

local txd = TXDIO:new(); txd:load(BASE .. "/example/hillrace.txd")
local tex = txd.textureDictionary.textures[1]; local st = tex.struct
print(string.format("Texture: %s %dx%d DXT1", st.name, st.width, st.height))

-- Decode DXT
local dds = DDSTexture:new(); dds:convertFromTXD(tex)
local bgra = dds:decodeToBGRA()
print(string.format("BGRA: %d bytes", #bgra))

-- Build PixelData once
local px = PixelData:new()
px.width=st.width; px.height=st.height; px.depth=32; px.rowAlignment=1; px.dataType="raw"; px.data=bgra

-- Test slow mode
local pSlow = PNG:new(); pSlow.width=st.width; pSlow.height=st.height; pSlow.pixels=px
local t0 = os.clock(); local dSlow = pSlow:save(nil, false); local t1 = os.clock()

-- Test fast mode
local pFast = PNG:new(); pFast.width=st.width; pFast.height=st.height; pFast.pixels=px
local t2 = os.clock(); local dFast = pFast:save(nil, true); local t3 = os.clock()

print(string.format("slow: %.2fs  %d bytes", t1-t0, #dSlow))
print(string.format("fast: %.2fs  %d bytes  (%.1fx speedup, +%d bytes)", t3-t2, #dFast, (t1-t0)/(t3-t2), #dFast-#dSlow))
