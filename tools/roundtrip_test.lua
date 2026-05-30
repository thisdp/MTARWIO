-- roundtrip_test.lua — DFF 读写一致性测试
-- 每个文件完成后立刻打印并写入文件
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
local LOG = BASE .. "/roundtrip_result.txt"

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

local files = {}
local fh = io.open(BASE .. "/_filelist.txt", "r")
if not fh then print("ERROR: _filelist.txt not found"); os.exit(1) end
for path in fh:lines() do if path ~= "" then files[#files + 1] = path end end
fh:close()

local total = #files
local ok, fail = 0, 0
local tStart = os.clock()
local tmpPath = BASE .. "/_roundtrip_tmp.dff"

local log = io.open(LOG, "w")
local function logWrite(msg)
    log:write(msg .. "\n")
    log:flush()
    io.write(msg .. "\n")
    io.flush()
end

logWrite(string.format("DFF Round-Trip Validator — %d files", total))
logWrite(os.date() .. "\n")

for i, path in ipairs(files) do
    local name = path:match("([^/\\]+)$")

    local status, err = pcall(function()
        local d1 = DFFIO:new(); d1:load(path)
        if #d1.clumps == 0 then error("0 clumps") end
        local g = d1.clumps[1].geometryList.geometries[1].struct
        local a, b, c = #g.vertices, #g.faces, #d1.clumps[1].geometryList.geometries
        d1:save(tmpPath); d1 = nil

        local d2 = DFFIO:new(); d2:load(tmpPath)
        if #d2.clumps == 0 then error("resaved: 0 clumps") end
        local g2 = d2.clumps[1].geometryList.geometries[1].struct
        local x, y, z = #g2.vertices, #g2.faces, #d2.clumps[1].geometryList.geometries
        if a ~= x or b ~= y or c ~= z then
            error(string.format("diverge: v%d→%d f%d→%d g%d→%d", a, x, b, y, c, z))
        end
        d2 = nil
    end)

    if status then
        ok = ok + 1
        logWrite(string.format("OK    %s", name))
    else
        fail = fail + 1
        local msg = tostring(err):match(": (.+)$") or tostring(err)
        logWrite(string.format("FAIL  %s — %s", name, msg))
    end

    if i % 500 == 0 then
        local elapsed = os.clock() - tStart
        io.write(string.format("[%d/%d] ok=%d fail=%d (%.1fs)\n", i, total, ok, fail, elapsed))
        io.flush()
        collectgarbage()
    end
end

os.remove(tmpPath)
local elapsed = os.clock() - tStart
logWrite(string.format("\n=== SUMMARY ==="))
logWrite(string.format("Total: %d  Pass: %d  Fail: %d  Time: %.1f sec", total, ok, fail, elapsed))
log:close()
print(string.format("\nDone: %d files  ok=%d fail=%d", total, ok, fail))
