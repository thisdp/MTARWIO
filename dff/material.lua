-- dff/material.lua — 材质系统

MaterialStruct = Struct:define({
    { name = "flags",      type = uint32 },
    { name = "color",      type = rgba },
    { name = "unused",     type = uint32 },
    { name = "isTextured", type = bool32 },
    { name = "ambient",    type = float32 },
    { name = "specular",   type = float32 },
    { name = "diffuse",    type = float32 },
})

MaterialExtension = Extension:define({
    { name = "plugins", type = ExtensionList("MaterialExtension") },
})

Material = Section:define(0x07, {
    { name = "struct", type = MaterialStruct },
    { name = "texture", type = Texture, count = 1,
      cond = {{"struct.isTextured", "==", true}} },
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
        out[#out+1] = indent .. string.format("isTextured  = %s", tostring(ms.isTextured))
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
