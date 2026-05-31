-- batch_validate.lua — validate all DFF files in gtaimg/
-- Each file result is output immediately. PASS and FAIL both shown.

local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
local DIR = BASE .. "/gtaimg"
local LOG = BASE .. "/batch_result.txt"

-- suppress MTA mock startup message
local _print = print
print = function() end
dofile(BASE .. "/test/mta_mock.lua")
print = _print

local modules = {
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "dff/enums.lua", "dff/primitives.lua", "dff/material.lua", "dff/plugins.lua",
    "dff/uvanim.lua", "dff/framelist.lua", "dff/geometry.lua",
    "dff/atomic.lua", "dff/clump.lua", "dff/dffio.lua",
    "col/colio.lua",
}
for _, mod in ipairs(modules) do dofile(BASE .. "/" .. mod) end

-- read pre-generated file list (created by ls ... *.dff | sort > _filelist.txt)
local fileListPath = BASE .. "/_filelist.txt"
local files = {}
local listFile = io.open(fileListPath, "r")
if not listFile then
    print("ERROR: _filelist.txt not found. Run: ls gtaimg/*.dff | sort > _filelist.txt")
    os.exit(1)
end
for path in listFile:lines() do
    if path ~= "" then
        files[#files + 1] = path
    end
end
listFile:close()
print(string.format("Loaded %d DFF files from _filelist.txt", #files))

local total = #files
local ok, fail = 0, 0
local fails = {}

local log = io.open(LOG, "w")
local function logWrite(msg)
    log:write(msg .. "\n")
    log:flush()
    io.write(msg .. "\n")
end

logWrite("Batch DFF Validator — " .. DIR)
logWrite(string.format("Total DFF files: %d", total))
logWrite(os.date())
logWrite("")

local tStart = os.clock()

for i, path in ipairs(files) do
    local name = path:match("([^/\\]+)$")

    local status, err = pcall(function()
        local dff = DFFIO:new()
        dff:load(path)
        if #dff.clumps == 0 then error("0 clumps") end
        local g = dff.clumps[1].geometryList
        if not g or #g.geometries == 0 then error("0 geometries") end
        local v = g.geometries[1].struct
        if not v or #(v.vertices or {}) == 0 then error("0 vertices") end
        dff.clumps = nil
    end)

    if status then
        ok = ok + 1
        io.write(string.format("[%d/%d] PASS  %s\n", i, total, name))
    else
        fail = fail + 1
        local msg = err:match(": (.+)$") or tostring(err)
        fails[#fails + 1] = { name = name, msg = msg }
        logWrite(string.format("[%d/%d] FAIL  %s — %s", i, total, name, msg))
    end

    if i % 500 == 0 then
        local elapsed = os.clock() - tStart
        io.write(string.format("  ... %d/%d  ok=%d fail=%d (%.1f sec)\n", i, total, ok, fail, elapsed))
        collectgarbage()
        collectgarbage()
    end
end

local elapsed = os.clock() - tStart

logWrite("")
logWrite(string.format("=== SUMMARY ==="))
logWrite(string.format("Total: %d  Pass: %d  Fail: %d", total, ok, fail))
logWrite(string.format("Time: %.1f sec", elapsed))
if #fails > 0 then
    logWrite("")
    logWrite("=== FAILURES ===")
    for _, f in ipairs(fails) do
        logWrite(string.format("  %s — %s", f.name, f.msg))
    end
end
log:close()

print(string.format("\nDone: %d files in %.1f sec  ok=%d fail=%d", total, elapsed, ok, fail))
print("Results: " .. LOG)
