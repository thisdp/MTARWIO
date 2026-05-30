-- types.lua — 字段类型标记
-- 每个类型是一个轻量表，包含 marker 和 byteSize
-- 引擎根据 marker 分发读写逻辑

-- === 标量数值类型 ===
uint8   = { marker = "u8",  byteSize = 1, default = 0 }
uint16  = { marker = "u16", byteSize = 2, default = 0 }
uint32  = { marker = "u32", byteSize = 4, default = 0 }
int8    = { marker = "i8",  byteSize = 1, default = 0 }
int16   = { marker = "i16", byteSize = 2, default = 0 }
int32   = { marker = "i32", byteSize = 4, default = 0 }
float32 = { marker = "f32", byteSize = 4, default = 0.0 }

-- === 语义复合类型 ===
rgba   = { marker = "rgba",   byteSize = 4, default = function() return {0,0,0,0} end }
bool32 = { marker = "bool32", byteSize = 4, default = false }
bool8  = { marker = "bool8",  byteSize = 1, default = false }
vec2    = { marker = "vec2",    byteSize = 8,  default = function() return {0,0} end }
vec3    = { marker = "vec3",    byteSize = 12, default = function() return {0,0,0} end }
vec4    = { marker = "vec4",    byteSize = 16, default = function() return {0,0,0,0} end }
mat3x3  = { marker = "mat3x3",  byteSize = 36, default = function() return {{1,0,0},{0,1,0},{0,0,1}} end }
mat4x4  = { marker = "mat4x4",  byteSize = 64, default = function() return {{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}} end }
str     = { marker = "str",     default = "" }
bytes   = { marker = "bytes",   default = "" }

-- === 常用定长字符串 ===
str8  = { marker = "str", byteSize = 8,  default = "" }
str16 = { marker = "str", byteSize = 16, default = "" }
str24 = { marker = "str", byteSize = 24, default = "" }
str32 = { marker = "str", byteSize = 32, default = "" }

-- === 辅助函数 ===
function arrayOf(elemType, count)
    return { marker = "array", element = elemType, count = count }
end

function when(cond, innerType)
    return { marker = "when", condition = cond, inner = innerType }
end

function Catalogue(t, by, sizeFrom)
    t._catalogue = true
    t._dispatchBy = by
    t._sizeFrom = sizeFrom
    return t
end

function isScalar(t)
    return t and t.marker and t.byteSize and t.byteSize > 0
end

function scalarSize(t)
    return t.byteSize
end
