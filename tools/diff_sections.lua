-- tools/diff_sections.lua — 逐 Section 对比原始和重保存文件的差异
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
local _print = print; print = function() end; dofile(BASE .. "/test/mta_mock.lua"); print = _print
for _, mod in ipairs({
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "dff/enums.lua", "dff/primitives.lua", "dff/material.lua", "dff/plugins.lua",
    "dff/uvanim.lua", "dff/framelist.lua", "dff/geometry.lua",
    "dff/atomic.lua", "dff/clump.lua", "dff/dffio.lua",
    "col/colio.lua",
}) do dofile(BASE .. "/" .. mod) end

local function readAll(fn)
    local f = fileOpen(fn); local sz = fileGetSize(f); local d = fileRead(f, sz); fileClose(f); return d, sz
end

local function hexdump(data, offset, len)
    local lines = {}
    local maxLen = math.min(#data, (offset or 1) + (len or 64) - 1)
    for i = offset or 1, maxLen, 16 do
        local hex, ascii = {}, {}
        for j = 0, 15 do
            local b = data:byte(i + j)
            if b then hex[#hex+1] = string.format("%02X", b)
            else hex[#hex+1] = "  " end
            ascii[#ascii+1] = (b and b >= 0x20 and b < 0x7F) and string.char(b) or "."
        end
        lines[#lines+1] = string.format("  0x%06X: %s  %s", i, table.concat(hex, " "), table.concat(ascii))
    end
    return table.concat(lines, "\n")
end

local function walkSections(r, depth, origFile)
    local sections = {}
    while r.pos + 12 <= r.len do
        local start = r.pos
        local t, s, v = r:u32(), r:u32(), r:u32()
        if t == 0 and s == 0 then break end  -- EOF padding
        local bodyStart = r.pos
        local bodyBytes = r:raw(s)
        sections[#sections + 1] = {
            type = t, size = s, version = v,
            offset = start,
            body = bodyBytes,
        }
    end
    return sections
end

-- Test file
local testFile = arg[1] or "gtaimg/_lod_cn2blok1.dff"

-- 1. Parse original and find all sections
local origData, origSz = readAll(testFile)
local origReader = Reader.new(origData)
local origSections = walkSections(origReader, 0, testFile)

-- 2. Parse + save + read resaved
local dff = DFFIO:new(); dff:load(testFile); dff:save(BASE .. "/_diff_tmp.dff")
local resData, resSz = readAll(BASE .. "/_diff_tmp.dff")
local resReader = Reader.new(resData)
local resSections = walkSections(resReader, 0)

local name = testFile:match("([^/\\]+)$")
print(string.format("=== %s: orig=%d res=%d ===", name, origSz, resSz))

if origSz ~= resSz then
    print(string.format("Size differs by %d bytes", resSz - origSz))
end

-- Compare section by section
local maxI = math.max(#origSections, #resSections)
for i = 1, maxI do
    local os, rs = origSections[i], resSections[i]
    if not os then
        print(string.format("  [%d] EXTRA in res: type=0x%08X size=%d", i, rs.type, rs.size))
    elseif not rs then
        print(string.format("  [%d] MISSING from res: type=0x%08X size=%d", i, os.type, os.size))
    else
        local typeName = os.type == 0x10 and "Clump" or
                         os.type == 0x01 and "Struct" or
                         os.type == 0x03 and "Extension" or
                         string.format("0x%08X", os.type)
        local match = (os.body == rs.body)
        local sizeMatch = (os.size == rs.size)
        if not match or not sizeMatch then
            print(string.format("  [%d] %s: size %d->%d bodyMatch=%s",
                i, typeName, os.size, rs.size, tostring(match)))
            if not match then
                -- Find first diff byte
                for j = 1, math.min(#os.body, #rs.body) do
                    if os.body:byte(j) ~= rs.body:byte(j) then
                        print(string.format("      first diff at body+%d (file+%d): orig=0x%02X res=0x%02X",
                            j, os.offset + 12 + j, os.body:byte(j), rs.body:byte(j)))
                        print(string.format("      ORIG bytes at body+%d:", j))
                        print(hexdump(os.body, math.max(1, j-4), 48))
                        print(string.format("      RES bytes at body+%d:", j))
                        print(hexdump(rs.body, math.max(1, j-4), 48))
                        break
                    end
                end
                if #os.body ~= #rs.body then
                    print(string.format("      body size diff: %d vs %d", #os.body, #rs.body))
                end
            end
        end
    end
end

-- Now deep-compare: find which subsection within Clump differs
if #origSections >= 1 and origSections[1].type == 0x10 then
    print("\n--- Clump body deep compare ---")
    local origClumpBody = origSections[1].body
    local resClumpBody = resSections[1] and resSections[1].body or ""

    -- Walk sub-sections within Clump body
    local function walkSubs(data, label)
        local r2 = Reader.new(data)
        local subs = {}
        local idx = 0
        while r2.pos + 12 <= r2.len do
            local t, s, v = r2:u32(), r2:u32(), r2:u32()
            if t == 0 and s == 0 then table.insert(subs, {type=0, size=0, offset=r2.pos-12, body="", label="EOF padding"}); break end
            local b = r2:raw(s)
            idx = idx + 1
            local tn = t == 0x01 and "Struct" or t == 0x0E and "FrameList" or t == 0x1A and "GeometryList" or
                       t == 0x0F and "Geometry" or t == 0x14 and "Atomic" or t == 0x12 and "Light" or
                       t == 0x03 and "Extension" or t == 0x07 and "Material" or
                       t == 0x0116 and "SkinPLG" or t == 0x050E and "BinMeshPLG" or
                       t == 0x0253F2F8 and "Effect2D" or t == 0x0253F2F9 and "NightColor" or
                       t == 0x0253F2FA and "COLSection" or t == 0x0253F2FC and "ReflMat" or
                       t == 0x0253F2F6 and "SpecMat" or t == 0x0253F2FD and "Breakable" or
                       t == 0x0253F2FE and "Frame" or t == 0x1F and "Pipline" or
                       t == 0x11E and "HAnimPLG" or t == 0x120 and "MatEffect" or
                       t == 0x135 and "UVAnimPLG" or t == 0x105 and "MorphPLG" or
                       string.format("0x%04X", t)
            subs[#subs+1] = {type=t, size=s, offset=r2.pos-12-s, body=b, label=tn, idx=idx}
        end
        return subs
    end

    local oSub = walkSubs(origClumpBody, "orig")
    local rSub = walkSubs(resClumpBody, "res")

    print(string.format("Orig subs: %d, Res subs: %d", #oSub, #rSub))

    local function findByOffset(subs, off)
        for _, s in ipairs(subs) do if s.offset == off then return s end end
        return nil
    end

    -- Compare by offset (original order)
    for _, os in ipairs(oSub) do
        local rs = findByOffset(rSub, os.offset)
        if not rs then
            print(string.format("  [%d] %s @0x%X: MISSING from res", os.idx, os.label, os.offset))
        elseif os.body ~= rs.body then
            local bodyMatch = (os.body == rs.body)
            print(string.format("  [%d] %s @0x%X: sz %d->%d body=%s",
                os.idx, os.label, os.offset, os.size, rs.size, tostring(bodyMatch)))
            if not bodyMatch then
                for j = 1, math.min(#os.body, #rs.body) do
                    if os.body:byte(j) ~= rs.body:byte(j) then
                        print(string.format("      diff at body+%d: %02X->%02X", j, os.body:byte(j), rs.body:byte(j)))
                        print(string.format("      orig:"))
                        print(hexdump(os.body, math.max(1,j-4), 32))
                        print(string.format("      res:"))
                        print(hexdump(rs.body, math.max(1,j-4), 32))
                        break
                    end
                end
            end
        end
    end
    -- Check extras in res
    for _, rs in ipairs(rSub) do
        if not findByOffset(oSub, rs.offset) then
            local tn = rs.label
            print(string.format("  [?] %s @0x%X: EXTRA in res size=%d", tn, rs.offset, rs.size))
        end
    end
end

os.remove(BASE .. "/_diff_tmp.dff")
