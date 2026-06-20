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
function Texture:create(config)
    config = config or {}
    local version = GTASA

    local tex = Texture:new()
    tex.type = Texture.typeID
    tex.version = version

    tex.struct = TextureStruct:new()
    tex.struct.parent = tex
    tex.struct:init(version)

    local texName = config.textureName or ""
    tex.textureName = String:new()
    tex.textureName.parent = tex
    tex.textureName.version = version
    tex.textureName.string = texName
    tex.textureName.size = #texName

    local maskName = config.maskName or ""
    tex.maskName = String:new()
    tex.maskName.parent = tex
    tex.maskName.version = version
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

-- ====== Material 简化工厂 ======

-- 快速创建材质，只需指定颜色和纹理名
-- config.color:    {r,g,b,a} 默认白色
-- config.texture:  纹理名字符串 (如 "vehiclegeneric256")
-- config.ambient:  环境光 (默认 0.3)
-- config.specular: 高光 (默认 1.0)
-- config.diffuse:  漫反射 (默认 1.0)
function Material:createSimple(config)
    config = config or {}
    local texName = config.texture or ""
    local mat = Material:create({
        color = config.color or {255, 255, 255, 255},
        textureCount = (texName ~= "") and 1 or 0,
        textureName = texName,
        ambient = config.ambient or 0.3,
        specular = config.specular or 1.0,
        diffuse = config.diffuse or 1.0,
    })

    -- MaterialExtension 留空 (匹配 emptyNewDff.dff 模板格式)

    return mat
end

-- 添加反射插件 (ReflectionMaterial)
-- coefficient: 反射强度 (0.0-1.0, 默认 1.0)
function Material:addReflection(coefficient)
    local version = self.version or GTASA
    local ext = self.extension
    if not ext then return nil end

    -- 移除旧反射
    local newPlugins = {}
    local plugins = ext.plugins or {}
    for i = 1, #plugins do
        local p = plugins[i]
        if p.type ~= ReflectionMaterial.typeID then
            newPlugins[#newPlugins + 1] = p
        end
    end

    local refl = ReflectionMaterial:new()
    refl.type = ReflectionMaterial.typeID
    refl.version = version
    refl.envMapScaleX = 1.0
    refl.envMapScaleY = 1.0
    refl.envMapOffsetX = 0
    refl.envMapOffsetY = 0
    refl.reflectionIntensity = coefficient or 1.0
    refl.envTexturePtr = 0
    refl.parent = ext
    refl:getSize()
    newPlugins[#newPlugins + 1] = refl
    ext.plugins = newPlugins
    return refl
end

-- 添加高光插件 (SpecularMaterial)
-- level:   高光强度 (0.0-1.0)
-- texName: 高光贴图名 (默认空字符串)
function Material:addSpecular(level, texName)
    local version = self.version or GTASA
    local ext = self.extension
    if not ext then return nil end

    -- 移除旧高光
    local newPlugins = {}
    local plugins = ext.plugins or {}
    for i = 1, #plugins do
        local p = plugins[i]
        if p.type ~= SpecularMaterial.typeID then
            newPlugins[#newPlugins + 1] = p
        end
    end

    local spec = SpecularMaterial:new()
    spec.type = SpecularMaterial.typeID
    spec.version = version
    spec.specularLevel = level or 1.0
    spec.textureName = texName or ""  -- str24 类型
    spec.parent = ext
    spec:getSize()
    newPlugins[#newPlugins + 1] = spec
    ext.plugins = newPlugins
    return spec
end

-- 设置材质颜色 (便捷方法)
function Material:setColor(r, g, b, a)
    self.struct.color = {r, g, b, a or 255}
    return self
end

-- 移除纹理
function Material:removeTexture()
    self.struct.textureCount = 0
    self.texture = nil
    return self
end

-- ====== 构造工厂 ======
function Material:create(config)
    config = config or {}
    local version = GTASA
    local mat = Material:new()
    mat.type = Material.typeID
    mat.version = version
    -- struct
    mat.struct = MaterialStruct:new()
    mat.struct.parent = mat
    mat.struct:init(version)
    mat.struct.flags = config.flags or 0
    mat.struct.color = config.color or {255, 255, 255, 255}
    mat.struct.unused = version >= GTASA and 16688092 or 1629820
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
        mat.texture = Texture:create(config)
        mat.texture.parent = mat
    end
    return mat
end

-- 增删材质
function MaterialList:addMaterial(material)
    if type(material) ~= "table" or material.type ~= Material.typeID then
        material = Material:create(material)
    end
    material.parent = self
    self.materials = self.materials or {}
    self.struct.materialIndices = self.struct.materialIndices or {}
    local idx = #self.materials + 1
    self.materials[idx] = material
    self.struct.materialIndices[idx] = -1  -- SA 标准: 始终 -1
    self.struct.materialCount = #self.materials
    return material
end

function MaterialList:removeMaterial(index)
    if not self.materials or index < 1 or index > #self.materials then
        return false
    end
    local removed = self.materials[index]
    -- 检查面引用
    if self.parent and self.parent.struct and self.parent.struct.faces then
        local faces = self.parent.struct.faces
        for i = 1, #faces do
            local face = faces[i]
            local matIdx = face[3]  -- Face.Mat
            if matIdx == index - 1 then
                error(string.format("Cannot remove material %d: still referenced by faces", index), 2)
            elseif matIdx > index - 1 then
                face[3] = matIdx - 1
            end
        end
    end
    table.remove(self.materials, index)
    table.remove(self.struct.materialIndices, index)
    self.struct.materialCount = #self.materials
    return removed
end

MaterialList._typeName = "MaterialList"
function MaterialList:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    Section.dump(self, out, lvl, limits)
    if self.materials then
        for i = 1, #self.materials do
            local m = self.materials[i]
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
