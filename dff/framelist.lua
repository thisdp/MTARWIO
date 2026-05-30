-- dff/framelist.lua — 框架层次系统

FrameInfo = RawStruct:define({
    { name = "rotationMatrix", type = mat3x3 },
    { name = "positionVector", type = vec3 },
    { name = "parentFrame",    type = int32 },
    { name = "matrixFlags",    type = uint32 },
})

FrameListStruct = Struct:define({
    { name = "frameCount", type = uint32, sync = "frameInfo" },
    { name = "frameInfo",  type = FrameInfo, count = "frameCount" },
})

Frame = Section:define(0x253F2FE, {
    { name = "name", type = str },
})

function Frame:setName(name)
    self.name = name
    return self
end

HAnimNode = RawStruct:define({
    { name = "nodeID",    type = uint32 },
    { name = "nodeIndex", type = uint32 },
    { name = "flags",     type = uint32 },
})

HAnimPLG = Section:define(0x11E, {
    { name = "animVersion",  type = uint32 },
    { name = "nodeID",       type = uint32 },
    { name = "nodeCount",    type = uint32, sync = "nodes" },
    { name = "flags",        type = uint32, cond = {{"nodeCount", "~=", 0}} },
    { name = "keyFrameSize", type = uint32, cond = {{"nodeCount", "~=", 0}} },
    { name = "nodes",        type = HAnimNode, count = "nodeCount",
      cond = {{"nodeCount", "~=", 0}} },
})

FrameListExtension = Extension:define({
    { name = "HAnimPLG", type = HAnimPLG, optional = true },
    { name = "frame",    type = Frame, cond = {{"size", "~=", 0}} },
})

FrameList = Section:define(0x0E, {
    { name = "struct", type = FrameListStruct },
    { name = "frames", type = FrameListExtension, count = "struct.frameCount" },
})
FrameList._typeName = "FrameList"

function FrameList:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    Section.dump(self, out, lvl, limits)
    if self.struct then
        local indent = string.rep("  ", lvl + 1)
        out[#out+1] = indent .. string.format("frameCount = %d", self.struct.frameCount or 0)
        if self.struct.frameInfo then
            for i, fi in ipairs(self.struct.frameInfo) do
                out[#out+1] = indent .. string.format("--- FrameInfo [%d] ---", i)
                out[#out+1] = indent .. "  rotationMatrix:"
                for row = 1, 3 do
                    local r = fi.rotationMatrix and fi.rotationMatrix[row] or {}
                    out[#out+1] = indent .. string.format("    row%d: (%.6f, %.6f, %.6f)", row, r[1] or 0, r[2] or 0, r[3] or 0)
                end
                out[#out+1] = indent .. string.format("  position = %s", Section.fmtVec(fi.positionVector))
                out[#out+1] = indent .. string.format("  parentFrame = %d", fi.parentFrame or 0)
                out[#out+1] = indent .. string.format("  matrixFlags = 0x%08X", fi.matrixFlags or 0)
            end
        end
    end
    if self.frames then
        for i, fr in ipairs(self.frames) do
            if fr and fr.frame then
                local indent = string.rep("  ", lvl + 1)
                out[#out+1] = indent .. string.format("Frame[%d] name = \"%s\"", i, fr.frame.name or "")
            end
        end
    end
end
