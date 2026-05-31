-- dff/atomic.lua — 原子（渲染单元）系统

AtomicStruct = Struct:define({
    { name = "frameIndex",    type = uint32 },
    { name = "geometryIndex", type = uint32 },
    { name = "flags",         type = uint32, bits = {
        {"bCollisionTest", 0},
        {"bRender",        2},
    }},
    { name = "unused",        type = uint32 },
})

AtomicExtension = Extension:define({
    { name = "plugins", type = ExtensionList("AtomicExtension") },
})

Atomic = Section:define(0x14, {
    { name = "struct",    type = AtomicStruct },
    { name = "extension", type = AtomicExtension },
})
Atomic._typeName = "Atomic"

-- ====== Atomic:create 工厂 ======
-- 仅创建 Atomic 结构, 不添加到 Clump (由 Clump:addAtomic 负责)
function Atomic:create(version, config)
    config = config or {}
    version = version or GTASA

    local atomic = Atomic:new()
    atomic.type = Atomic.typeID
    atomic.version = version

    atomic.struct = AtomicStruct:new()
    atomic.struct.parent = atomic
    atomic.struct:init(version)
    atomic.struct.frameIndex = 0
    atomic.struct.geometryIndex = 0

    if config.flags ~= nil then
        atomic.struct.flags = config.flags
    else
        atomic.struct.bCollisionTest = (config.bCollisionTest ~= false)
        atomic.struct.bRender = (config.bRender ~= false)
    end
    atomic.struct.unused = 0

    atomic.extension = AtomicExtension:new()
    atomic.extension.parent = atomic
    atomic.extension:init(version)

    return atomic
end

-- ====== 便捷导航 ======
function Atomic:getGeometry()
    local clump = self.parent
    if not clump or not clump.geometryList then return nil end
    local idx = self.struct.geometryIndex
    return clump.geometryList.geometries[idx + 1]
end

function Atomic:getFrame()
    local clump = self.parent
    if not clump then return nil end
    local idx = self.struct.frameIndex
    local fi = clump.frameList.struct.frameInfo[idx + 1]
    local fr = clump.frameList.frames[idx + 1]
    return fi, fr
end

function Atomic:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    local idx = self._dumpIndex
    local idxStr = idx and (" [" .. idx .. "]") or ""
    Section.dump(self, out, lvl, limits)
    if self.struct then
        local indent = string.rep("  ", lvl + 1)
        out[#out+1] = indent .. string.format("frameIndex     = %d", self.struct.frameIndex or 0)
        out[#out+1] = indent .. string.format("geometryIndex  = %d", self.struct.geometryIndex or 0)
        out[#out+1] = indent .. string.format("flags          = 0x%08X", self.struct.flags or 0)
    end
    if self.extension then
        out[#out+1] = string.rep("  ", lvl + 1) .. "--- AtomicExtension ---"
        self.extension:dump(out, lvl + 1, limits)
    end
end
