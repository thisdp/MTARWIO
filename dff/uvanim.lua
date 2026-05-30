-- dff/uvanim.lua — UV 动画系统

UVAnimDictStruct = Struct:define({
    { name = "animationCount", type = uint32, sync = "animations" },
    { name = "animations",     type = UVAnim, count = "animationCount" },
})

UVAnimDict = Section:define(0x2B, {
    { name = "struct", type = UVAnimDictStruct },
})

UVAnimFrame = RawStruct:define({
    { name = "time",          type = float32 },
    { name = "scale",         type = vec3 },
    { name = "position",      type = vec3 },
    { name = "previousFrame", type = int32 },
})

UVAnim = Section:define(0x1B, {
    { name = "header",          type = uint32 },
    { name = "animType",        type = uint32 },
    { name = "frameCount",      type = uint32, sync = "data" },
    { name = "flags",           type = uint32 },
    { name = "duration",        type = float32 },
    { name = "unused",          type = uint32 },
    { name = "name",            type = str32 },
    { name = "nodeToUVChannel", type = float32, count = 8 },
    { name = "data",            type = UVAnimFrame, count = "frameCount" },
})
