-- validate_one.lua — 验证单个 DFF 文件, 输出 PASS|FAIL name
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
local path = arg[1]
if not path then print("FAIL no-arg: missing path"); os.exit(1) end

local name = path:match("([^/\\]+)$")

-- 抑制 mock 启动消息
local _print = print; print = function() end
dofile(BASE .. "/test/mta_mock.lua")
print = _print
local modules = {
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "dff/uvanim.lua", "dff/framelist.lua", "dff/geometry.lua",
    "dff/atomic.lua", "dff/clump.lua", "dff/dffio.lua",
    "col/colio.lua",
}
for _, mod in ipairs(modules) do dofile(BASE .. "/" .. mod) end

local ok, err = pcall(function()
    local dff = DFFIO:new()
    dff:load(path)
    if #dff.clumps == 0 then error("0 clumps") end
    local g = dff.clumps[1].geometryList
    if not g or #g.geometries == 0 then error("0 geometries") end
    local v = g.geometries[1].struct
    if not v or #(v.vertices or {}) == 0 then error("0 vertices") end
end)

if ok then
    print("OK    " .. name)
else
    local msg = tostring(err):match(": (.+)$") or tostring(err)
    print("FAIL  " .. name .. " — " .. msg)
end
