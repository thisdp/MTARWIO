-- dff/clump.lua — Clump（模型容器）+ 灯光 + 碰撞系统

-- ====== ClumpStruct (0x01) ======
ClumpStruct = Struct:define({
    { name = "atomicCount", type = int32, sync = function(self) return #(self.parent.atomics) end },
    { name = "lightCount",  type = int32, sync = function(self) return #(self.parent.lights) end },
    { name = "cameraCount", type = int32 },
})

-- ====== LightStruct (0x01) ======
LightStruct = Struct:define({
    { name = "radius",    type = float32 },
    { name = "red",       type = float32 },
    { name = "green",     type = float32 },
    { name = "blue",      type = float32 },
    { name = "direction", type = float32 },
    { name = "flags",     type = uint16 },
    { name = "lightType", type = uint16 },
})

-- ====== Light (0x12) ======
Light = Section:define(0x12, {
    { name = "struct",    type = LightStruct },
    { name = "extension", type = Extension },
})
Light._typeName = "Light"

function Light:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    local idx = self._dumpIndex
    local idxStr = idx and (" [" .. idx .. "]") or ""
    Section.dump(self, out, lvl, limits)
    if self.struct then
        local indent = string.rep("  ", lvl + 1)
        local s = self.struct
        out[#out+1] = indent .. string.format("radius     = %.4f", s.radius or 0)
        out[#out+1] = indent .. string.format("color      = (R=%.4f G=%.4f B=%.4f)", s.red or 0, s.green or 0, s.blue or 0)
        out[#out+1] = indent .. string.format("direction  = %.4f", s.direction or 0)
        out[#out+1] = indent .. string.format("flags      = 0x%04X  lightType = 0x%04X", s.flags or 0, s.lightType or 0)
    end
end

-- ====== IndexStruct — 索引辅助结构 ======
IndexStruct = Struct:define({
    { name = "index", type = uint32 },
})

-- ====== COLSection (0x253F2FA) — 嵌入碰撞数据 ======
COLSection = Section:extend({ typeID = 0x253F2FA, _typeName = "COLSection" })

function COLSection:read(r)
    self.collisionRaw = r:raw(self.size)
    if COLIO then
        local colio = COLIO:new()
        local ok = pcall(colio.load, colio, self.collisionRaw)
        if ok then
            self.collision = colio.collision
        end
    end
end

function COLSection:dump(out, lvl, limits)
    lvl = lvl or 0
    Section.dump(self, out, lvl, limits)
    if self.collision then
        self.collision:dump(out, lvl + 1, limits)
    elseif self.collisionRaw then
        local indent = string.rep("  ", lvl + 1)
        out[#out+1] = indent .. string.format("rawData = %d bytes (unparsed)", #self.collisionRaw)
    end
end

function COLSection:write(w)
    self.size = #(self.collisionRaw or "")
    w:u32(self.type):u32(self.size):u32(self.version)
    w:raw(self.collisionRaw or "")
end

function COLSection:getSize()
    self.size = #(self.collisionRaw or "")
    return self.size + 12
end

SectionRegistry.register(COLSection)

-- ====== ClumpExtension ======
ClumpExtension = Extension:define({
    { name = "plugins", type = ExtensionList("ClumpExtension") },
})

-- ====== Clump (0x10) ======
-- Clump 的读取有特殊逻辑：Struct/FrameList/GeometryList 之后，
-- 交替读取 IndexStruct+Light 直到遇到 ClumpExtension

Clump = Section:extend({ typeID = 0x10, _typeName = "Clump" })

function Clump:read(r)
    local bodyStart = r.pos  -- 记录 body 起始位置

    -- struct (是 Struct 子类，必须显式指定)
    self.struct = ClumpStruct:readFrom(r, self)

    -- frameList (唯一 typeID=0x0E，走注册表) — 先读 header 再 pcall 保护
    local flSave = r.pos
    local flType, flSize, flVer = r:u32(), r:u32(), r:u32()
    r.pos = flSave
    local ok, obj = pcall(SectionRegistry.read, r)
    if ok then
        self.frameList = obj
        self.frameList.parent = self
    else
        r.pos = flSave + 12 + flSize  -- 跳过损坏的 FrameList section
    end

    -- geometryList (唯一 typeID=0x1A，走注册表) — 先读 header 再 pcall 保护
    local glSave = r.pos
    local glType, glSize, glVer = r:u32(), r:u32(), r:u32()
    r.pos = glSave
    ok, obj = pcall(SectionRegistry.read, r)
    if ok then
        self.geometryList = obj
        self.geometryList.parent = self
    else
        r.pos = glSave + 12 + glSize  -- 跳过损坏的 GeometryList section
    end

    -- 后续所有子 Section 统一按 typeID 分发: Atomics, Lights, Extension
    local bodyEnd = bodyStart + self.size
    self.atomics = {}
    self.lights = {}
    self.indexStructs = {}
    while r.pos + 8 <= bodyEnd do  -- 至少需要 typeID + size (8 bytes)
        local typeID = r:u32()
        local size = r:u32()
        local version = r:u32()

        if typeID == ClumpExtension.typeID then
            local ext = ClumpExtension:new()
            ext.type = typeID; ext.size = size; ext.version = version
            ext["@"] = r.pos - 12; ext.parent = self
            ext:read(r)
            self.extension = ext
            break
        elseif typeID == Atomic.typeID then
            local atomic = Atomic:new()
            atomic.type = typeID; atomic.size = size; atomic.version = version
            atomic["@"] = r.pos - 12; atomic.parent = self
            pcall(atomic.read, atomic, r)
            self.atomics[#self.atomics + 1] = atomic
        elseif typeID == Struct.typeID then
            local idx = IndexStruct:new()
            idx.type = typeID; idx.size = size; idx.version = version
            idx["@"] = r.pos - 12; idx.parent = self
            idx:read(r)
            self.indexStructs[#self.indexStructs + 1] = idx

            -- 紧接着是 Light
            local ok2, light = pcall(SectionRegistry.read, r)
            if ok2 then
                light.parent = self
                self.lights[#self.lights + 1] = light
            end
        else
            break  -- 未知 typeID 或 padding，安全退出
        end
    end
end

function Clump:write(w)
    self:getSize()
    w:u32(self.type)
    w:u32(self.size)
    w:u32(self.version)
    self.struct.atomicCount = #self.atomics
    self.struct.lightCount = #self.lights
    self.struct:write(w)
    self.frameList:write(w)
    self.geometryList:write(w)

    for i = 1, #self.atomics do
        self.atomics[i]:write(w)
    end

    for i = 1, #(self.indexStructs or {}) do
        if self.lights[i] then
            self.indexStructs[i]:write(w)
            self.lights[i]:write(w)
        end
    end

    self.extension:write(w)
    if self._trailingData then w:raw(self._trailingData) end
end

function Clump:getSize()
    local total = self.struct:getSize() + self.frameList:getSize()
        + self.geometryList:getSize()
    for i = 1, #self.atomics do
        total = total + self.atomics[i]:getSize()
    end
    for i = 1, #(self.indexStructs or {}) do
        total = total + self.indexStructs[i]:getSize()
        if self.lights[i] then
            total = total + self.lights[i]:getSize()
        end
    end
    local trailingSize = self._trailingData and #self._trailingData or 0
    total = total + self.extension:getSize() + trailingSize
    self.size = total  -- body size (children with headers + trailing)
    return total + 12  -- + Clump header
end

function Clump:convert(targetVersion)
    self.version = targetVersion
    self.struct:convert(targetVersion)
    self.frameList:convert(targetVersion)
    self.geometryList:convert(targetVersion)
    for _, atomic in ipairs(self.atomics) do
        atomic:convert(targetVersion)
    end
    for i = 1, #(self.indexStructs or {}) do
        self.indexStructs[i]:convert(targetVersion)
        if self.lights[i] then self.lights[i]:convert(targetVersion) end
    end
    self.extension:convert(targetVersion)
    self:getSize()
end

-- 添加组件: 同时创建 Atomic + Frame + Geometry
function Clump:addComponent()
    self.atomics[#self.atomics + 1] = SectionRegistry.read -- placeholder
    -- TODO: 完整实现创建逻辑
end

SectionRegistry.register(Clump)

-- ====== Clump:dump ======
function Clump:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    local indent = string.rep("  ", lvl)
    local at = self["@"] and string.format(" @0x%X", self["@"]) or ""
    out[#out+1] = indent .. "--- Clump" .. at .. string.format("  size=%d  version=0x%08X ---", self.size or 0, self.version or 0)
    if self.struct then self.struct:dump(out, lvl + 1, limits) end
    if self.frameList then self.frameList:dump(out, lvl + 1, limits) end
    if self.geometryList then self.geometryList:dump(out, lvl + 1, limits) end
    if self.atomics then
        for i, a in ipairs(self.atomics) do
            a._dumpIndex = i
            a:dump(out, lvl + 1, limits)
        end
    end
    if self.lights then
        for i, l in ipairs(self.lights) do
            l._dumpIndex = i
            l:dump(out, lvl + 1, limits)
        end
    end
    if self.extension then self.extension:dump(out, lvl + 1, limits) end
end
