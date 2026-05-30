-- dff/primitives.lua — DFF 基础结构 (Face, Texture, TextureStruct)

Face = RawStruct:define({
    { name = 1, type = uint16 },
    { name = 2, type = uint16 },
    { name = 3, type = uint16 },
    { name = 4, type = uint16 },
})

Face.V1  = 2
Face.V2  = 1
Face.V3  = 4
Face.Mat = 3

function Face:getVertices()
    return { self[Face.V1], self[Face.V2], self[Face.V3] }
end

function Face:getMaterial()
    return self[Face.Mat]
end

TextureStruct = Struct:define({
    { name = "flags", type = uint32, bits = {
        {"hasMipmaps", 19},
        {"VAddressing", 20, 4},
        {"UAddressing", 24, 4},
    }},
})

Texture = Section:define(0x06, {
    { name = "struct",      type = TextureStruct },
    { name = "textureName", type = String },
    { name = "maskName",    type = String },
    { name = "extension",   type = Extension },
})
