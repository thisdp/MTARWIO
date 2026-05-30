-- Full profile: time each step of PNG encoding
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")
for _,m in ipairs({
    "core/binary/reader.lua","core/binary/writer.lua",
    "utils/bitops.lua","utils/math3d.lua","utils/tableutil.lua",
    "core/schema/types.lua","core/schema/registry.lua","core/schema/engine.lua",
    "core/base.lua","texture/bmp.lua",
    "txd/txdio.lua","texture/dds.lua",
}) do dofile(BASE .. "/" .. m) end
local PNG = dofile(BASE .. "/texture/png.lua")

local txd = TXDIO:new(); txd:load(BASE .. "/example/hillrace.txd")
local st = txd.textureDictionary.textures[1].struct
print(string.format("Profile: %s %dx%d DXT1\n", st.name, st.width, st.height))

-- DXT decode
local t0 = os.clock()
local dds = DDSTexture:new(); dds:convertFromTXD(txd.textureDictionary.textures[1])
local bgra = dds:decodeToBGRA()
print(string.format("1. DXT decode:    %6.2fs  (%d bytes BGRA)", os.clock()-t0, #bgra))

-- Build PixelData
local t1 = os.clock()
local px = PixelData:new()
px.width=st.width; px.height=st.height; px.depth=32; px.rowAlignment=1; px.dataType="raw"; px.data=bgra
local png = PNG:new(); png.width=st.width; png.height=st.height; png.pixels=px
print(string.format("2. PixelData set: %6.2fs", os.clock()-t1))

-- Call PNG:save and let the built-in profile prints show the breakdown
print("\n--- PNG:save breakdown ---")
local t2 = os.clock()
_PNG_PROFILE = true
local pngData = png:save(nil, false)
print(string.format("--- total: %.2fs, %d bytes ---", os.clock()-t2, #pngData))
