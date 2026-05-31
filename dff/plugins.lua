-- dff/plugins.lua — DFF 所有插件 Section 定义

-- BinMesh 材质分割子结构 (必须在 BinMeshPLG 之前定义)
BinMeshSplit = RawStruct:define({
    { name = "faceCount",     type = uint32, sync = "faceList" },
    { name = "materialIndex", type = uint32 },
    { name = "faceList",      type = uint32, count = "faceCount" },
})

-- ====== BinMeshPLG (0x50E) ======
BinMeshPLG = Section:define(0x50E, {
    { name = "faceType",          type = uint32 },
    { name = "materialSplitCount",type = uint32, sync = "materialSplits" },
    { name = "vertexCount",       type = uint32, sync = function(self)
        local total = 0
        for _, split in ipairs(self.materialSplits or {}) do
            total = total + (split.faceCount or 0)
        end
        return total
    end },
    { name = "materialSplits",    type = BinMeshSplit, count = "materialSplitCount" },
})

BinMeshPLG._typeName = "BinMeshPLG"
SectionRegistry.registerPlugin("GeometryExtension", BinMeshPLG)

-- ====== BoneMatrix (4x4 骨骼变换, 无 Section 头) ======
BoneMatrix = RawStruct:define({
    { name = "_vcUnused", type = uint32, cond = {{"parent.parent.version", "~=", GTASA}} },
    { name = "m", type = mat4x4 },
})

-- 骨骼索引 (4 u8 per vertex, 无 Section 头)
BoneIndices = RawStruct:define({
    { name = 1, type = uint8 },
    { name = 2, type = uint8 },
    { name = 3, type = uint8 },
    { name = 4, type = uint8 },
})

-- 骨骼权重 (4 f32 per vertex, 无 Section 头)
BoneWeight = RawStruct:define({
    { name = 1, type = float32 },
    { name = 2, type = float32 },
    { name = 3, type = float32 },
    { name = 4, type = float32 },
})

-- ====== SkinPLG (0x116) ======
SkinPLG = Section:define(0x116, {
    { name = "boneCount",        type = uint8 },
    { name = "usedBoneCount",    type = uint8 },
    { name = "maxVertexWeights", type = uint8 },
    { name = "_padding",         type = uint8 },
    { name = "usedBoneIndices",  type = uint8, count = "usedBoneCount" },
    { name = "boneVertices",     type = BoneIndices, count = "parent.parent.struct.vertexCount" },
    { name = "boneVertexWeights",type = BoneWeight,  count = "parent.parent.struct.vertexCount" },
    { name = "bones",            type = BoneMatrix, count = "boneCount" },
    { name = "_saUnused",        type = uint32, count = 3, cond = {{"version", "==", GTASA}} },
})

SkinPLG._typeName = "SkinPLG"
SectionRegistry.registerPlugin("GeometryExtension", SkinPLG)

-- ====== MorphPLG (0x105) ======
MorphPLG = Section:define(0x105, {
    { name = "unused", type = uint32 },
})

MorphPLG._typeName = "MorphPLG"
SectionRegistry.registerPlugin("GeometryExtension", MorphPLG)

-- 可破坏物体面 (3 u16, 数组形式)
BreakableFace = RawStruct:define({
    { name = 1, type = uint16 },
    { name = 2, type = uint16 },
    { name = 3, type = uint16 },
})

-- ====== Breakable (0x0253F2FD) ======
Breakable = Section:define(0x0253F2FD, {
    { name = "flags", type = uint32 },
    { name = "positionRule", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "vertexCount",  type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "offsetVertices", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "offsetCoords", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "offsetVertexLight", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "faceCount", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "offsetVertexIndices", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "offsetMaterialIndices", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "materialCount", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "offsetTextures", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "offsetTextureNames", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "offsetTextureMasks", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "offsetAmbientColors", type = uint32, cond = {{"flags", "~=", 0}} },
    { name = "vertices", type = vec3, count = "vertexCount", cond = {{"flags", "~=", 0}} },
    { name = "texCoords", type = vec2, count = "vertexCount", cond = {{"flags", "~=", 0}} },
    { name = "vertexColors", type = rgba, count = "vertexCount", cond = {{"flags", "~=", 0}} },
    { name = "faces", type = BreakableFace, count = "faceCount", cond = {{"flags", "~=", 0}} },
    { name = "triangleMaterials", type = uint16, count = "faceCount", cond = {{"flags", "~=", 0}} },
    { name = "materialTextureNames", type = str32, count = "materialCount", cond = {{"flags", "~=", 0}} },
    { name = "materialTextureMasks", type = str32, count = "materialCount", cond = {{"flags", "~=", 0}} },
    { name = "ambientColor", type = vec3, count = "materialCount", cond = {{"flags", "~=", 0}} },
})

Breakable._typeName = "Breakable"
SectionRegistry.registerPlugin("GeometryExtension", Breakable)

-- ====== NightVertexColor (0x253F2F9) ======
NightVertexColor = Section:define(0x253F2F9, {
    { name = "hasColor", type = uint32 },
    { name = "colors", type = rgba, count = function(self) return (self.size - 4) / 4 end },
})

NightVertexColor._typeName = "NightVertexColor"
SectionRegistry.registerPlugin("GeometryExtension", NightVertexColor)

-- ====== ReflectionMaterial (0x0253F2FC) ======
ReflectionMaterial = Section:define(0x0253F2FC, {
    { name = "envMapScaleX", type = float32 },
    { name = "envMapScaleY", type = float32 },
    { name = "envMapOffsetX", type = float32 },
    { name = "envMapOffsetY", type = float32 },
    { name = "reflectionIntensity", type = float32 },
    { name = "envTexturePtr", type = uint32 },
})

ReflectionMaterial._typeName = "ReflectionMaterial"
SectionRegistry.registerPlugin("MaterialExtension", ReflectionMaterial)

-- ====== SpecularMaterial (0x0253F2F6) ======
SpecularMaterial = Section:define(0x0253F2F6, {
    { name = "specularLevel", type = float32 },
    { name = "textureName",   type = str24 },
})

SpecularMaterial._typeName = "SpecularMaterial"
SectionRegistry.registerPlugin("MaterialExtension", SpecularMaterial)

-- ====== MaterialEffectPLG (0x120) — effectType 分发 body ======
MaterialEffectPLG = {}
MaterialEffectPLG.Effects = Catalogue({}, "effectType")
MaterialEffectPLG.registerEffect = function(entryType, cls)
    MaterialEffectPLG.Effects[entryType] = cls
    cls.entryType = entryType
end

-- effectType == 0x00: None — 无额外数据
EffectNone = RawStruct:define({})
MaterialEffectPLG.registerEffect(0x00, EffectNone)

-- effectType == 0x01: BumpMap — 无额外数据 (仅 effectType)
EffectBumpMap = RawStruct:define({})
MaterialEffectPLG.registerEffect(0x01, EffectBumpMap)

-- effectType == 0x02: EnvMap / Reflection
EffectReflection = RawStruct:define({
    { name = "unused",                     type = uint32 },
    { name = "reflectionCoefficient",      type = float32 },
    { name = "useFrameBufferAlphaChannel", type = bool32 },
    { name = "useEnvMap",                  type = bool32 },
    { name = "texture",                    type = Texture, cond = {{"useEnvMap", "==", true}} },
    { name = "endPadding",                 type = uint32 },
})
MaterialEffectPLG.registerEffect(0x02, EffectReflection)

-- effectType == 0x03: BumpEnvMap — 与 EnvMap 同结构
EffectBumpEnvMap = RawStruct:define({
    { name = "unused",                     type = uint32 },
    { name = "reflectionCoefficient",      type = float32 },
    { name = "useFrameBufferAlphaChannel", type = bool32 },
    { name = "useEnvMap",                  type = bool32 },
    { name = "texture",                    type = Texture, cond = {{"useEnvMap", "==", true}} },
    { name = "endPadding",                 type = uint32 },
})
MaterialEffectPLG.registerEffect(0x03, EffectBumpEnvMap)

-- effectType == 0x04: Dual — 无额外数据 (双 pass 渲染)
EffectDual = RawStruct:define({})
MaterialEffectPLG.registerEffect(0x04, EffectDual)

-- effectType == 0x05: UVTransform
EffectUVTransform = RawStruct:define({
    { name = "unused",     type = uint32 },
    { name = "endPadding", type = uint32 },
})
MaterialEffectPLG.registerEffect(0x05, EffectUVTransform)

-- effectType == 0x06: DualUVTransform — 与 UVTransform 同结构
EffectDualUVTransform = RawStruct:define({
    { name = "unused",     type = uint32 },
    { name = "endPadding", type = uint32 },
})
MaterialEffectPLG.registerEffect(0x06, EffectDualUVTransform)

local _Effects = MaterialEffectPLG.Effects
local _register = MaterialEffectPLG.registerEffect
MaterialEffectPLG = Section:define(0x120, {
    { name = "effectType", type = uint32 },
    { name = "body",       type = MaterialEffectPLG.Effects },
})

MaterialEffectPLG._typeName = "MaterialEffectPLG"
MaterialEffectPLG.Effects = _Effects
MaterialEffectPLG.registerEffect = _register

SectionRegistry.registerPlugin("MaterialExtension", MaterialEffectPLG)
SectionRegistry.registerPlugin("AtomicExtension", MaterialEffectPLG)

-- ====== UVAnimPLG (0x135) ======
UVAnimPLGStruct = Struct:define({
    { name = "unused", type = uint32 },
    { name = "name",   type = str32 },
})
UVAnimPLG = Section:define(0x135, {
    { name = "struct", type = UVAnimPLGStruct },
})

UVAnimPLG._typeName = "UVAnimPLG"
SectionRegistry.registerPlugin("MaterialExtension", UVAnimPLG)

-- ====== Pipline / RightToRender (0x1F) ======
Pipline = Section:define(0x1F, {
    { name = "pluginIdentifier", type = uint32 },
    { name = "extraData", type = uint32 },
})

Pipline._typeName = "Pipline"
SectionRegistry.registerPlugin("AtomicExtension", Pipline)

-- ====== ParticlesPLG (0x118) — 粒子效果 ======
ParticlesPLG = Section:define(0x118, {
    { name = "particleValue", type = uint32 },
})

ParticlesPLG._typeName = "ParticlesPLG"
SectionRegistry.registerPlugin("AtomicExtension", ParticlesPLG)

-- ====== PipelineSet (0x0253F2F3) — 管线集配置 ======
PipelineSet = Section:define(0x0253F2F3, {
    { name = "pipelineValue", type = uint32 },
})

PipelineSet._typeName = "PipelineSet"
SectionRegistry.registerPlugin("AtomicExtension", PipelineSet)

-- ====== Effect2D (0x0253F2F8) + 子效果类型 ======
-- 前向声明: Effect2DEntry 需要引用 Effect2D.Effects 分发表
Effect2D = {}
Effect2D.Effects = Catalogue({}, "entryType", "entrySize")

Effect2DEntry = RawStruct:define({
    { name = "position",  type = vec3 },
    { name = "entryType", type = uint32 },
    { name = "entrySize", type = uint32, sync = "effect" },
    { name = "effect",    type = Effect2D.Effects },
})

local _Effects = Effect2D.Effects
Effect2D = Section:define(0x0253F2F8, {
    { name = "count",   type = uint32, sync = "effects" },
    { name = "effects", type = Effect2DEntry, count = "count" },
})

Effect2D._typeName = "Effect2D"
Effect2D.Effects = _Effects
SectionRegistry.registerPlugin("GeometryExtension", Effect2D)

function Effect2D.registerEffect(entryType, cls)
    Effect2D.Effects[entryType] = cls
    cls.entryType = entryType
end

-- 2DFX 灯光效果 (entryType = 0x00)
Effect2DLight = RawStruct:define({
    { name = "color",                 type = rgba,    default = {255,255,255,255} },
    { name = "coronaFarClip",         type = float32 },
    { name = "coronaNearClip",        type = float32 },
    { name = "pointlightRange",       type = float32 },
    { name = "coronaSize",            type = float32 },
    { name = "shadowSize",            type = float32 },
    { name = "coronaShowMode",        type = uint32 },
    { name = "coronaEnableReflection",type = uint32 },
    { name = "flareType",             type = uint32 },
    { name = "shadowZDistance",       type = float32 },
    { name = "flags",                 type = uint32 },
    { name = "coronaTexName",         type = str24 },
    { name = "shadowTexName",         type = str24 },
    { name = "lookDir",               type = vec3 },
})
Effect2D.registerEffect(0x00, Effect2DLight)

-- 2DFX 粒子效果 (entryType = 0x01)
-- byteSize="size" 仅 read 时使用(Effect2D 预设 entrySize)；write/getSize 自动取字符串实际长度
Effect2DParticle = RawStruct:define({
    { name = "particleName", type = str, byteSize = "size" },
})
Effect2D.registerEffect(0x01, Effect2DParticle)

-- 2DFX Ped 吸引器 (entryType = 0x03)
Effect2DPedAttractor = RawStruct:define({
    { name = "attractorType",  type = uint32 },
    { name = "rotationMatrix", type = mat3x3 },
    { name = "scriptName",     type = str8 },
    { name = "probability",    type = float32 },
})
Effect2D.registerEffect(0x03, Effect2DPedAttractor)

-- 2DFX 进入/退出 (entryType = 0x06)
Effect2DEnterExit = RawStruct:define({
    { name = "enterAngle",   type = float32 },
    { name = "enterRadius",  type = vec2 },
    { name = "exitPosition", type = vec3 },
    { name = "exitAngle",    type = float32 },
    { name = "interiorId",   type = int32 },
    { name = "flags",        type = uint32 },
    { name = "interiorName", type = str8 },
    { name = "skyColor",     type = rgba },
})
Effect2D.registerEffect(0x06, Effect2DEnterExit)

-- 2DFX 路牌 (entryType = 0x07)
Effect2DStreetSign = RawStruct:define({
    { name = "size",      type = vec2 },
    { name = "rotation",  type = vec3 },
    { name = "flags",     type = uint32 },
    { name = "lines",     type = str16, count = 4, default = {"","","",""} },
})
Effect2D.registerEffect(0x07, Effect2DStreetSign)

-- 2DFX SunGlare (entryType = 0x04)
Effect2DSunGlare = RawStruct:define({})
Effect2D.registerEffect(0x04, Effect2DSunGlare)

-- 2DFX TriggerPoint (entryType = 0x08)
Effect2DTriggerPoint = RawStruct:define({
    { name = "index",    type = uint32 },
    { name = "position", type = vec3 },
})
Effect2D.registerEffect(0x08, Effect2DTriggerPoint)

-- 2DFX CoverPoint (entryType = 0x09)
Effect2DCoverPoint = RawStruct:define({
    { name = "coverType", type = uint32 },
    { name = "direction", type = vec2 },
})
Effect2D.registerEffect(0x09, Effect2DCoverPoint)

-- 2DFX Escalator (entryType = 0x0A)
Effect2DEscalator = RawStruct:define({
    { name = "positionBottom", type = vec3 },
    { name = "positionTop",    type = vec3 },
    { name = "positionEnd",    type = vec3 },
    { name = "direction",      type = uint32 },
})
Effect2D.registerEffect(0x0A, Effect2DEscalator)
