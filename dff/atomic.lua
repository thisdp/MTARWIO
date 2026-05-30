-- dff/atomic.lua — 原子（渲染单元）系统

AtomicStruct = Struct:define({
    { name = "frameIndex",    type = uint32 },
    { name = "geometryIndex", type = uint32 },
    { name = "flags",         type = uint32 },
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
