-- Export raw DXT mipmap data for Python comparison
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/test/mta_mock.lua")
for _, m in ipairs({
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "txd/txdio.lua", "texture/dds.lua", "texture/bmp.lua",
}) do dofile(BASE .. "/" .. m) end
PNG = dofile(BASE .. "/texture/png.lua")

local txd = TXDIO:new()
txd:load(BASE .. "/example/hillrace.txd")

-- Export first texture's raw DXT data (top mipmap only)
local tex = txd.textureDictionary.textures[1]
local st = tex.struct
local dds = DDSTexture:new()
dds:convertFromTXD(tex)

-- Save raw DXT data
local outDir = BASE .. "/test/output"
os.execute('mkdir "' .. outDir .. '" 2>nul')
local f = fileCreate(outDir .. "/dxt_raw.bin")
fileWrite(f, dds.mipmaps[1].data)
fileClose(f)

-- Save metadata
local mf = fileCreate(outDir .. "/dxt_meta.txt")
fileWrite(mf, string.format("%d %d %d\n", st.width, st.height, st.textureFormat))
fileClose(mf)

-- Also export Lua's PNG output
local ok, pngData = pcall(txd.getTexture, txd, 1, "png")
if ok then
    f = fileCreate(outDir .. "/lua_output.png")
    fileWrite(f, pngData)
    fileClose(f)
    print(string.format("Exported: raw DXT=%d bytes, PNG=%d bytes, %dx%d fmt=0x%08X",
        #dds.mipmaps[1].data, #pngData, st.width, st.height, st.textureFormat))
end
