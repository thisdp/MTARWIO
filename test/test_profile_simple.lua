-- Simple profile: DXT decode vs PNG encode
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
local tex = txd.textureDictionary.textures[1]
local st = tex.struct
print(string.format("Profile: %s %dx%d DXT1\n", st.name, st.width, st.height))

-- Time DXT decode (our code)
local t0 = os.clock()
local dds = DDSTexture:new(); dds:convertFromTXD(tex)
local bgra = dds:decodeToBGRA()
local t1 = os.clock()
print(string.format("DXT decode:    %6.2fs  (%d bytes BGRA)", t1-t0, #bgra))

-- Time PixelData build + PNG encode
local t2 = os.clock()
local px = PixelData:new()
px.width=st.width; px.height=st.height; px.depth=32; px.rowAlignment=1; px.dataType="raw"; px.data=bgra
local png = PNG:new(); png.width=st.width; png.height=st.height; png.pixels=px
local pngData = png:save()
local t3 = os.clock()
print(string.format("PNG encode:    %6.2fs  (%d bytes PNG)", t3-t2, #pngData))

-- Estimate: PNG deflate takes most of PNG encode time
-- For 512x512 RGBA: input ~1MB, output ~470KB
-- deflate ratio: 470K/1M = 47%
print(string.format("\nTotal:         %6.2fs", t3-t0))
print(string.format("DXT 占比:      %5.1f%%", (t1-t0)/(t3-t0)*100))
print(string.format("PNG 占比:      %5.1f%%", (t3-t2)/(t3-t0)*100))
