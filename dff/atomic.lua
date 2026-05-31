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
-- parent: 所属 Clump 实例
-- config 可选字段:
--   frameIndex    - Frame 索引        (默认 0)
--   geometryIndex - Geometry 索引     (默认 0)
--   flags         - 标志位 raw 值     (默认 nil → 使用 bit 字段)
--   bCollisionTest / bRender         - 命名 bit 字段
function Atomic:create(parent, config)
    config = config or {}
    local version = (parent and parent.version) or GTASA

    local atomic = Atomic:new()
    atomic.parent = parent
    atomic.type = Atomic.typeID
    atomic.version = version

    atomic.struct = AtomicStruct:new()
    atomic.struct.parent = atomic
    atomic.struct:init(version)
    atomic.struct.frameIndex = config.frameIndex or 0
    atomic.struct.geometryIndex = config.geometryIndex or 0

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
