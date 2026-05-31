-- tools/dff_dump.lua — Parse DFF/COL and dump all data as readable text
-- 用法: lua5.1.exe tools/dff_dump.lua [path]  → 生成 .parttable + .fulltable

local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"

local LIM_PART = {
    maxVerts = 10, maxFaces = 10, maxVColors = 5, maxItems = 10,
}
local LIM_FULL = {
    maxVerts = math.huge, maxFaces = math.huge, maxVColors = math.huge, maxItems = math.huge,
}

-- Load all modules
dofile(BASE .. "/test/mta_mock.lua")
local modules = {
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "dff/uvanim.lua", "dff/framelist.lua", "dff/geometry.lua",
    "dff/atomic.lua", "dff/clump.lua", "dff/dffio.lua",
    "col/colio.lua",
}
for _, mod in ipairs(modules) do
    local ok, err = pcall(dofile, BASE .. "/" .. mod)
    if not ok then print("[FAIL] " .. mod .. ": " .. tostring(err)); return end
end

local function writeFile(path, content)
    local f = fileCreate(path); fileWrite(f, content); fileClose(f)
    print(string.format("  %s (%d bytes)", path, #content))
end

-- Main
local path = arg[1] or "example/launch.dff"
local fullPath = BASE .. "/" .. path
local ext = path:match("%.([^.]+)$"):lower()

print("Generating dumps for: " .. path)
local result, resultName
if ext == "dff" then
    local dff = DFFIO:new()
    dff:load(fullPath)
    writeFile(fullPath:gsub("%.dff$", ".dff.parttable"), dff:dump(LIM_PART))
    writeFile(fullPath:gsub("%.dff$", ".dff.fulltable"), dff:dump(LIM_FULL))
elseif ext == "col" then
    local colio = COLIO:new()
    colio:load(fullPath)
    writeFile(fullPath:gsub("%.col$", ".col.parttable"), colio:dump(LIM_PART))
    writeFile(fullPath:gsub("%.col$", ".col.fulltable"), colio:dump(LIM_FULL))
else
    print("Unknown extension: ." .. ext)
end
print("Done.")
