-- diagnose2.lua — 遍历 DFF 结构树，标注每个 section 的文件偏移
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
local tmpFile = BASE .. "/_diagnose2_tmp.dff"

local fh = io.open(testFile, "rb")
local origData = fh:read("*all")
fh:close()
print(string.format("Original: %d bytes", #origData))

-- Load
local dff = DFFIO:new()
dff:load(testFile)
print(string.format("Clumps: %d, Others: %d, UVAnim: %s", #dff.clumps, #dff.others, dff.uvAnimDict and "yes" or "no"))

-- Function to walk the section tree
local function walkSection(obj, name, depth, prefix)
    prefix = prefix or ""
    depth = depth or 0
    local indent = string.rep("  ", depth)
    local typeName = obj._typeName or string.format("0x%08X", obj.type or 0)
    local at = obj["@"] and string.format(" @0x%X", obj["@"]) or ""
    local tsz = obj:getSize()
    print(string.format("%s%s%s type=0x%08X bodySize=%d total=%d @=%s",
        prefix, indent, name, obj.type or 0, obj.size or 0, tsz, at))

    -- Check specific fields for sub-sections
    local subFields = {"struct", "extension", "texture", "materialList", "frameList", "geometryList"}
    for _, fname in ipairs(subFields) do
        local sub = obj[fname]
        if sub and type(sub) == "table" and sub.type then
            walkSection(sub, fname, depth + 1, prefix)
        end
    end

    -- Arrays
    local arrayFields = {"atomics", "geometries", "materials", "plugins", "frames", "materialSplits", "lights"}
    for _, fname in ipairs(arrayFields) do
        local arr = obj[fname]
        if arr and type(arr) == "table" then
            for i, item in ipairs(arr) do
                if type(item) == "table" and item.type then
                    walkSection(item, fname .. "[" .. i .. "]", depth + 1, prefix)
                end
            end
        end
    end

    -- Texture sub-sections
    if obj.textureName and type(obj.textureName) == "table" and obj.textureName.type then
        walkSection(obj.textureName, "textureName", depth + 1, prefix)
    end
    if obj.maskName and type(obj.maskName) == "table" and obj.maskName.type then
        walkSection(obj.maskName, "maskName", depth + 1, prefix)
    end

    -- HAnimPLG
    if obj.HAnimPLG and type(obj.HAnimPLG) == "table" and obj.HAnimPLG.type then
        walkSection(obj.HAnimPLG, "HAnimPLG", depth + 1, prefix)
    end
end

print("\n=== Section Tree ===")
for i, other in ipairs(dff.others) do
    walkSection(other, "other[" .. i .. "]", 0, "OTH: ")
end
for i, clump in ipairs(dff.clumps) do
    walkSection(clump, "clump[" .. i .. "]", 0, "CLP: ")
end

-- Now compare byte-by-byte
print("\n=== Save & Compare ===")
dff:save(tmpFile)
local fh2 = io.open(tmpFile, "rb")
local resavedData = fh2:read("*all")
fh2:close()
print(string.format("Resaved: %d bytes (diff: %+d)", #resavedData, #resavedData - #origData))

-- Find first diff block
local diffBlocks = {}
local blockStart = nil
local len = math.min(#origData, #resavedData)
for i = 1, len do
    local ob = origData:byte(i)
    local rb = resavedData:byte(i)
    if ob ~= rb then
        if blockStart == nil then
            blockStart = i
        end
    else
        if blockStart ~= nil then
            diffBlocks[#diffBlocks + 1] = {start = blockStart, len = i - blockStart}
            blockStart = nil
        end
    end
end
if blockStart ~= nil then
    diffBlocks[#diffBlocks + 1] = {start = blockStart, len = len - blockStart + 1}
end

print(string.format("\nDiff blocks: %d", #diffBlocks))
for _, blk in ipairs(diffBlocks) do
    local off = blk.start - 1  -- 0-based offset
    print(string.format("  @0x%X (%d): %d bytes differ", off, off, blk.len))
    -- hex dump the area in original
    local ctxStart = blk.start
    local ctxLen = math.min(32, blk.len, #origData - ctxStart + 1)
    local origHex = {}
    local resvHex = {}
    for j = 0, ctxLen - 1 do
        origHex[#origHex+1] = string.format("%02X", origData:byte(ctxStart + j))
        resvHex[#resvHex+1] = string.format("%02X", resavedData:byte(ctxStart + j))
    end
    print(string.format("    orig: %s", table.concat(origHex, " ")))
    print(string.format("    resv: %s", table.concat(resvHex, " ")))
end

-- If different sizes, show extra/missing bytes
if #origData > #resavedData then
    local extraStart = #resavedData + 1
    local extraLen = math.min(32, #origData - #resavedData)
    local hex = {}
    for j = 0, extraLen - 1 do
        hex[#hex+1] = string.format("%02X", origData:byte(extraStart + j))
    end
    print(string.format("\nMissing from resaved (first %d bytes @0x%X):", extraLen, extraStart - 1))
    print(string.format("  %s", table.concat(hex, " ")))
elseif #resavedData > #origData then
    local extraStart = #origData + 1
    local extraLen = math.min(32, #resavedData - #origData)
    local hex = {}
    for j = 0, extraLen - 1 do
        hex[#hex+1] = string.format("%02X", resavedData:byte(extraStart + j))
    end
    print(string.format("\nExtra in resaved (first %d bytes @0x%X):", extraLen, extraStart - 1))
    print(string.format("  %s", table.concat(hex, " ")))
end

os.remove(tmpFile)
