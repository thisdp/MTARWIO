-- dff/material.lua — 材质系统 (Material, Texture, TextureStruct)

-- ====== TextureStruct ======
TextureStruct = Struct:define({
    { name = "flags", type = uint32, bits = {
        {"hasMipmaps", 19},
        {"VAddressing", 20, 4},
        {"UAddressing", 24, 4},
    }},
})

-- ====== Texture (0x06) ======
Texture = Section:define(0x06, {
    { name = "struct",      type = TextureStruct },
    { name = "textureName", type = String },
    { name = "maskName",    type = String },
    { name = "extension",   type = Extension },
})

-- ====== Texture:create 工厂 ======
function Texture:create(version, config)
    config = config or {}
    version = version or GTASA

    local tex = Texture:new()
    tex.parent = parent
    tex.type = Texture.typeID
    tex.version = version

    tex.struct = TextureStruct:new()
    tex.struct.parent = tex
    tex.struct:init(version)

    local texName = config.textureName or ""
    tex.textureName = String:new()
    tex.textureName.parent = tex
    tex.textureName.string = texName
    tex.textureName.size = #texName

    local maskName = config.maskName or ""
    tex.maskName = String:new()
    tex.maskName.parent = tex
    tex.maskName.string = maskName
    tex.maskName.size = #maskName

    tex.extension = Extension:new()
    tex.extension.parent = tex
    tex.extension:init(version)

    return tex
end

-- ====== MaterialStruct ======
MaterialStruct = Struct:define({
    { name = "flags",        type = uint32 },
    { name = "color",        type = rgba },
    { name = "unused",       type = uint32 },
    { name = "textureCount", type = uint32 },
    { name = "ambient",      type = float32 },
    { name = "specular",     type = float32 },
    { name = "diffuse",      type = float32 },
})

MaterialExtension = Extension:define({
    { name = "plugins", type = ExtensionList("MaterialExtension") },
})

Material = Section:define(0x07, {
    { name = "struct", type = MaterialStruct },
    { name = "texture", type = Texture, optional = true, cond = {{"struct.textureCount", "~=", 0}} },
    { name = "extension", type = MaterialExtension },
})

MaterialListStruct = Struct:define({
    { name = "materialCount",    type = uint32, sync = "materialIndices" },
    { name = "materialIndices",  type = int32, count = "materialCount" },
})

MaterialList = Section:define(0x08, {
    { name = "struct",    type = MaterialListStruct },
    { name = "materials", type = Material, count = "struct.materialCount" },
})

-- 辅助方法
function MaterialList:findMaterialByTexName(texName)
    for i = 1, #(self.materials or {}) do
        local m = self.materials[i]
        if m.texture and m.texture.textureName.string == texName then return i end
    end
    return false
end

function MaterialList:findMaterialByMaskName(maskName)
    for i = 1, #(self.materials or {}) do
        local m = self.materials[i]
        if m.texture and m.texture.maskName.string == maskName then return i end
    end
    return false
end

function MaterialList:findMaterialByColor(r, g, b, a)
    for i = 1, #(self.materials or {}) do
        local c = self.materials[i].struct.color
        if c[1] == r and c[2] == g and c[3] == b and c[4] == a then return i end
    end
    return false
end

-- 判断两个 Material 是否相同 (用于合并去重)
function Material:equals(other)
    if not other then return false end
    local sa, oa = self.struct, other.struct
    if sa.flags ~= oa.flags then return false end
    if sa.color[1] ~= oa.color[1] or sa.color[2] ~= oa.color[2]
        or sa.color[3] ~= oa.color[3] or sa.color[4] ~= oa.color[4] then return false end
    if sa.textureCount ~= oa.textureCount then return false end
    if sa.ambient ~= oa.ambient or sa.specular ~= oa.specular or sa.diffuse ~= oa.diffuse then return false end
    if sa.textureCount then
        local st, ot = self.texture, other.texture
        if not st or not ot then return false end
        local sn, on = st.textureName, ot.textureName
        if (sn and sn.string or "") ~= (on and on.string or "") then return false end
        local sm, om = st.maskName, ot.maskName
        if (sm and sm.string or "") ~= (om and om.string or "") then return false end
    end
    return true
end

-- 构造工厂
function Material:create(version, config)
    config = config or {}
    version = version or GTASA
    local mat = Material:new()
    mat.type = Material.typeID
    mat.version = version
    -- struct
    mat.struct = MaterialStruct:new()
    mat.struct.parent = mat
    mat.struct:init(version)
    mat.struct.flags = config.flags or 0
    mat.struct.color = config.color or {255, 255, 255, 255}
    mat.struct.unused = 0
    mat.struct.textureCount = config.textureCount or 0
    mat.struct.ambient = config.ambient or 1.0
    mat.struct.specular = config.specular or 1.0
    mat.struct.diffuse = config.diffuse or 1.0
    -- extension
    mat.extension = MaterialExtension:new()
    mat.extension.parent = mat
    mat.extension:init(version)
    -- texture (optional)
    if mat.struct.textureCount ~= 0 then
        mat.texture = Texture:create(version, config)
    end
    return mat
end

-- 增删材质
function MaterialList:addMaterial(material)
    if type(material) ~= "table" or material.type ~= Material.typeID then
        material = Material:create(self.version, material)
    end
    material.parent = self
    self.materials = self.materials or {}
    self.struct.materialIndices = self.struct.materialIndices or {}
    local idx = #self.materials + 1
    self.materials[idx] = material
    self.struct.materialIndices[idx] = idx - 1
    self.struct.materialCount = #self.struct.materialIndices
    return material
end

function MaterialList:removeMaterial(index)
    if not self.materials or index < 1 or index > #self.materials then
        return false
    end
    local removed = self.materials[index]
    -- 检查面引用
    if self.parent and self.parent.struct and self.parent.struct.faces then
        for _, face in ipairs(self.parent.struct.faces) do
            local matIdx = face[3]  -- Face.Mat
            if matIdx == index - 1 then
                error(string.format("Cannot remove material %d: still referenced by faces", index), 2)
            elseif matIdx > index - 1 then
                face[3] = matIdx - 1
                face[3] = matIdx - 1
            end
        end
    end
    table.remove(self.materials, index)
    table.remove(self.struct.materialIndices, index)
    self.struct.materialCount = #self.struct.materialIndices
    return removed
end

MaterialList._typeName = "MaterialList"
function MaterialList:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    Section.dump(self, out, lvl, limits)
    if self.materials then
        for i, m in ipairs(self.materials) do
            m._dumpIndex = i
            m:dump(out, lvl + 1, limits)
        end
    end
end

Material._typeName = "Material"
function Material:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    Section.dump(self, out, lvl, limits)
    if self.struct then
        local indent = string.rep("  ", lvl + 1)
        local ms = self.struct
        out[#out+1] = indent .. string.format("flags       = 0x%08X", ms.flags or 0)
        out[#out+1] = indent .. string.format("color       = (R=%d G=%d B=%d A=%d)", ms.color and ms.color[1] or 0, ms.color and ms.color[2] or 0, ms.color and ms.color[3] or 0, ms.color and ms.color[4] or 0)
        out[#out+1] = indent .. string.format("textureCount  = %s", tostring(ms.textureCount))
        out[#out+1] = indent .. string.format("ambient=%.4f specular=%.4f diffuse=%.4f", ms.ambient or 0, ms.specular or 0, ms.diffuse or 0)
    end
    if self.texture then
        local t = self.texture
        local indent = string.rep("  ", lvl + 1)
        out[#out+1] = indent .. "texture:"
        out[#out+1] = indent .. "  name = \"" .. (t.textureName and t.textureName.string or "") .. "\""
        out[#out+1] = indent .. "  mask = \"" .. (t.maskName and t.maskName.string or "") .. "\""
    end
    if self.extension then
        out[#out+1] = string.rep("  ", lvl + 1) .. "--- MaterialExtension ---"
        self.extension:dump(out, lvl + 1, limits)
    end
end
