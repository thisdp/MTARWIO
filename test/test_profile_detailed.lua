-- Detailed profile: where does PNG time go?
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
print(string.format("Profile: %s %dx%d DXT1", st.name, st.width, st.height))

-- DXT decode
local t0 = os.clock()
local dds = DDSTexture:new(); dds:convertFromTXD(tex)
local bgra = dds:decodeToBGRA()
print(string.format("[DXT decode] %.2fs  (%d bytes BGRA)", os.clock()-t0, #bgra))

-- PNG save with profile (pass "profile" as fast param to trigger prints)
local px = PixelData:new()
px.width=st.width; px.height=st.height; px.depth=32; px.rowAlignment=1; px.dataType="raw"; px.data=bgra
local png = PNG:new(); png.width=st.width; png.height=st.height; png.pixels=px
local pngData = png:save(nil, "profile")

print(string.format("\nFinal PNG: %d bytes", #pngData))
