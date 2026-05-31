-- test_runner.lua — MTARW 模块测试

local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
local EXAMPLE = BASE .. "/example"

-- Step 1: Mock MTA functions
dofile(BASE .. "/test/mta_mock.lua")

-- Step 2: Load all modules (same order as meta.xml)
local modules = {
    "core/binary/reader.lua",
    "core/binary/writer.lua",
    "utils/bitops.lua",
    "utils/math3d.lua",
    "utils/tableutil.lua",
    "core/schema/types.lua",
    "core/schema/registry.lua",
    "core/schema/engine.lua",
    "core/base.lua",
    "dff/enums.lua",
    "dff/primitives.lua",
    "dff/material.lua",
    "dff/plugins.lua",
    "dff/uvanim.lua",
    "dff/framelist.lua",
    "dff/geometry.lua",
    "dff/atomic.lua",
    "dff/clump.lua",
    "dff/dffio.lua",
    "txd/txdio.lua",
    "txd/platform/mta.lua",
    "texture/dds.lua",
    "texture/bmp.lua",
    "texture/png.lua",
    "col/colio.lua",
    "img/imgloader.lua",
}

local errors = 0
for _, mod in ipairs(modules) do
    local ok, err = pcall(dofile, BASE .. "/" .. mod)
    if not ok then
        print("[FAIL] " .. mod)
        print("  " .. tostring(err))
        errors = errors + 1
    else
        print("[OK]   " .. mod)
    end
end

if errors > 0 then
    print("\n*** " .. errors .. " module(s) failed to load. Aborting tests. ***")
    return
end
    
if not PNG then
    local ok, mod = pcall(dofile, BASE .. "/texture/png.lua")
    if ok then PNG = mod end
end

print("\n========== Module Loading Complete ==========\n")

-- Test 1: DFF
print("--- Test 1: Load launch.dff ---")
do
    local dff = DFFIO:new()
    local ok, err = pcall(dff.load, dff, EXAMPLE .. "/launch.dff")
    if ok then
        local clumpCount = #dff.clumps
        print(string.format("[OK] Loaded DFF with %d clump(s)", clumpCount))
        for ci, clump in ipairs(dff.clumps) do
            local atoms = #clump.atomics or 0
            local frames = #clump.frameList.struct.frameInfo or 0
            local geos = #clump.geometryList.geometries or 0
            print(string.format("  Clump %d: %d atomics, %d frames, %d geometries",
                ci, atoms, frames, geos))
            for gi, geo in ipairs(clump.geometryList.geometries) do
                local verts = #(geo.struct.vertices or {})
                local faces = #(geo.struct.faces or {})
                local mats = #geo.materialList.materials or 0
                print(string.format("    Geometry %d: %d vertices, %d faces, %d materials",
                    gi, verts, faces, mats))
                -- Check plugins
                local ext = geo.extension
                if ext.binMeshPLG then print("      [plugin] BinMeshPLG") end
                if ext.skinPLG then print("      [plugin] SkinPLG") end
                if ext.effect2D then
                    print(string.format("      [plugin] Effect2D (%d effects)", #ext.effect2D.effects))
                end
                if ext.nightVertexColor then print("      [plugin] NightVertexColor") end
                if ext.breakable then print("      [plugin] Breakable") end
            end
        end
        -- Test save roundtrip
        local saved = dff:save()
        if saved then
            print(string.format("[OK] DFF save roundtrip: %d bytes", #saved))
        end
    else
        print("[FAIL] DFF load: " .. tostring(err))
    end
end

-- Test 2: TXD
print("\n--- Test 2: Load hillrace.txd ---")
do
    local txd = TXDIO:new()
    local ok, err = pcall(txd.load, txd, EXAMPLE .. "/hillrace.txd")
    if ok and txd.textureDictionary then
        local texCount = #txd.textureDictionary.textures or 0
        print(string.format("[OK] Loaded TXD with %d texture(s)", texCount))
        for i = 1, math.min(texCount, 5) do
            local tex = txd.textureDictionary.textures[i]
            local st = tex.struct
            print(string.format("  [%d] %s  %dx%d  fmt=0x%04X  mips=%d",
                i, st.name, st.width, st.height, st.textureFormat, st.mipMapCount))
        end
        if texCount > 5 then print(string.format("  ... and %d more", texCount - 5)) end
        -- Roundtrip
        local saved = txd:save()
        if saved then
            print(string.format("[OK] TXD save roundtrip: %d bytes", #saved))
        end
    else
        print("[FAIL] TXD load: " .. tostring(err))
    end
end

-- Test 3: COL
print("\n--- Test 3: Load launch.col ---")
do
    local col = COLIO:new()
    local ok, err = pcall(col.load, col, EXAMPLE .. "/launch.col")
    if ok and col.collision then
        local c = col.collision
        print(string.format("[OK] Loaded COL v'%s'  model: %s  (%d vertices, %d faces, %d spheres, %d boxes)",
            c.version, c.modelName,
            c.vertexCount or 0, c.faceCount or 0,
            c.sphereCount or 0, c.boxCount or 0))
    else
        print("[FAIL] COL load: " .. tostring(err))
    end
end

-- Test 4: PNG roundtrip
print("\n--- Test 4: PNG roundtrip ---")
do
    local png = PNG:new()
    local px = PixelData:new()
    px.width = 2
    px.height = 2
    px.depth = 32
    px.rowAlignment = 1
    px.dataType = "raw"
    px.data = string.char(
        0, 0, 255, 255,  -- red (BGRA)
        0, 255, 0, 255,  -- green
        255, 0, 0, 255,  -- blue
        255, 255, 255, 255  -- white
    )

    png.width = px.width
    png.height = px.height
    png.pixels = px

    local tmp = BASE .. "/test/_tmp.png"
    local okSave, errSave = pcall(png.save, png, tmp)
    if not okSave then
        print("[FAIL] PNG save: " .. tostring(errSave))
    else
        local png2 = PNG:new()
        local okLoad, errLoad = pcall(png2.load, png2, tmp)
        if not okLoad then
            print("[FAIL] PNG load: " .. tostring(errLoad))
        else
            local sameSize = png2.width == px.width and png2.height == px.height
            local sameData = png2.pixels and png2.pixels.data == px.data
            if sameSize and sameData then
                print("[OK] PNG roundtrip: pixels match")
            else
                print("[FAIL] PNG roundtrip: pixel mismatch")
            end
        end
    end
    if fileExists(tmp) then fileDelete(tmp) end
end

print("\n========== Tests Complete ==========")
