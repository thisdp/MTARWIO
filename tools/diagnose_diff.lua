-- diagnose_diff.lua — 单文件逐字节对比诊断
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"

local _print = print; print = function() end
dofile(BASE .. "/test/mta_mock.lua")
print = _print

local modules = {
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "dff/enums.lua", "dff/primitives.lua", "dff/plugins.lua", "dff/material.lua",
    "dff/uvanim.lua", "dff/framelist.lua", "dff/geometry.lua",
    "dff/atomic.lua", "dff/clump.lua", "dff/dffio.lua",
    "col/colio.lua",
}
for _, mod in ipairs(modules) do dofile(BASE .. "/" .. mod) end

local testFile = arg[1] or BASE .. "/gtaimg/_lod_cn2blok1.dff"
local tmpFile = BASE .. "/_diagnose_tmp.dff"

print("=== Byte-Level Diagnose ===")
print("File: " .. testFile)

-- Read original
local fh = io.open(testFile, "rb")
local origData = fh:read("*all")
fh:close()
print(string.format("Original: %d bytes", #origData))

-- Load → Save
local dff = DFFIO:new()
dff:load(testFile)
print(string.format("Clumps: %d", #dff.clumps))

-- Dump sizes before save
local c = dff.clumps[1]
print(string.format("Clump size: %d (calc: %d)", c.size, c:getSize() - 12))
print(string.format("  struct: %d", c.struct:getSize()))
print(string.format("  frameList: %d", c.frameList:getSize()))
print(string.format("  geometryList: %d", c.geometryList:getSize()))

local gl = c.geometryList
print(string.format("  GeometryList size: %d (calc: %d)", gl.size, gl:getSize() - 12))
print(string.format("    struct: %d", gl.struct:getSize()))
for i, g in ipairs(gl.geometries) do
    print(string.format("    Geometry[%d] size: %d (calc: %d)", i, g.size, g:getSize() - 12))
    print(string.format("      struct: %d", g.struct:getSize()))
    local mats = g.materialList
    if mats then
        print(string.format("      materialList size: %d (calc: %d)", mats.size, mats:getSize() - 12))
        print(string.format("        struct: %d", mats.struct:getSize()))
        for j, m in ipairs(mats.materials) do
            print(string.format("        Material[%d] size: %d (calc: %d)", j, m.size, m:getSize() - 12))
            print(string.format("          struct: %d", m.struct:getSize()))
            if m.texture then
                local tn = m.texture.textureName
                local mn = m.texture.maskName
                print(string.format("          texName size: %d, str='%s' (#%d)", tn.size, tn.string, #tn.string))
                print(string.format("          maskName size: %d, str='%s' (#%d)", mn.size, mn.string, #mn.string))
                print(string.format("          texStruct: %d", m.texture.struct:getSize()))
                print(string.format("          texExt: %d", m.texture.extension:getSize()))
                print(string.format("          texture total: %d (calc: %d)", m.texture.size, m.texture:getSize() - 12))
            end
            if m.extension then
                print(string.format("          ext size: %d (calc: %d)", m.extension.size, m.extension:getSize() - 12))
            end
        end
    end
end

-- Calculate total MaterialList body size
local ml = gl.geometries[1].materialList
local mlSum = ml.struct:getSize()
for j, m in ipairs(ml.materials) do
    mlSum = mlSum + m:getSize()
end
print(string.format("      materialList body sum: %d (header size=%d, diff=%d)", mlSum, ml.size, mlSum - ml.size))

-- Calculate total Geometry body size
for i, g in ipairs(gl.geometries) do
    local gSum = g.struct:getSize()
    if g.materialList then gSum = gSum + g.materialList:getSize() end
    if g.extension then gSum = gSum + g.extension:getSize() end
    if g.morphTargets then
        for _, mt in ipairs(g.morphTargets) do gSum = gSum + mt:getSize() end
    end
    print(string.format("      Geometry[%d] body sum: %d (header size=%d, diff=%d)", i, gSum, g.size, gSum - g.size))
end

dff:save(tmpFile)

-- Read resaved
fh = io.open(tmpFile, "rb")
local resavedData = fh:read("*all")
fh:close()
print(string.format("\nResaved: %d bytes", #resavedData))

-- Compare
local diffCount = 0
local maxShow = 40
local len = math.min(#origData, #resavedData)
for i = 1, len do
    local ob = origData:byte(i)
    local rb = resavedData:byte(i)
    if ob ~= rb then
        diffCount = diffCount + 1
        if diffCount <= maxShow then
            local ctx = math.max(1, i - 4)
            local ctxLen = math.min(16, len - ctx + 1)
            local origHex = {}
            local resvHex = {}
            for j = 0, ctxLen - 1 do
                local op = ctx + j
                local bo = origData:byte(op)
                local br = resavedData:byte(op)
                if bo == br then
                    origHex[#origHex+1] = string.format("%02X", bo)
                    resvHex[#resvHex+1] = string.format("%02X", br)
                else
                    origHex[#origHex+1] = string.format("[%02X]", bo)
                    resvHex[#resvHex+1] = string.format("[%02X]", br)
                end
            end
            print(string.format("  @0x%X: orig=%s  resv=%s", i-1, table.concat(origHex, " "), table.concat(resvHex, " ")))
        end
    end
end
if diffCount > maxShow then
    print(string.format("  ... +%d more diffs", diffCount - maxShow))
end
print(string.format("\nTotal diffs: %d bytes", diffCount))
if #origData ~= #resavedData then
    print(string.format("Size diff: orig=%d resv=%d (delta=%d)", #origData, #resavedData, #resavedData - #origData))
end

os.remove(tmpFile)
