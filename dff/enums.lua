-- dff/enums.lua — DFF 格式所有枚举常量

-- RW 版本
EnumRWVersion = {
    GTAVC = 0x0C02FFFF,
    GTASA = 0x1803FFFF,
}
GTASA = EnumRWVersion.GTASA
GTAVC = EnumRWVersion.GTAVC

-- 渲染混合模式
EnumBlendMode = {
    NOBLEND = 0, ZERO = 1, ONE = 2,
    SRCCOLOR = 3, INVSRCCOLOR = 4, SRCALPHA = 5, INVSRCALPHA = 6,
    DESTALPHA = 7, INVDESTALPHA = 8, DESTCOLOR = 9, INVDESTCOLOR = 10,
    SRCALPHASAT = 11,
}

-- 纹理过滤模式
EnumFilterMode = {
    None = 0, Nearest = 1, Linear = 2,
    MipNearest = 3, MipLinear = 4,
    LinearMipNearest = 5, LinearMipLinear = 6,
}

-- 纹理寻址模式
EnumAddressing = {
    WRAP = 1, MIRROR = 2, CLAMP = 3, BORDER = 4,
}

-- 材质效果类型
EnumMaterialEffect = {
    None = 0, BumpMap = 1, EnvMap = 2, BumpEnvMap = 3,
    Dual = 4, UVTransform = 5, DualUVTransform = 6,
}

-- 灯光类型
EnumLightType = {
    Directional = 0x01, Ambient = 0x02,
    Point = 0x80, Spot = 0x81, SpotSoft = 0x82,
}

-- 灯光标志
EnumLightFlag = {
    Scene = 0x01, World = 0x02,
}

-- 2DFX 效果类型
Enum2DFX = {
    Light = 0x00, ParticleEffect = 0x01,
    PedAttractor = 0x03, SunGlare = 0x04,
    EnterExit = 0x06, StreetSign = 0x07,
    TriggerPoint = 0x08, CovePoint = 0x09, Escalator = 0x0A,
}

-- ====== RW Section TypeID — 所有块的类型标识 ======

EnumSectionTypeID = {
    -- 核心类型
    STRUCT         = 0x00000001,
    STRING         = 0x00000002,
    EXTENSION      = 0x00000003,
    CAMERA         = 0x00000005,
    TEXTURE        = 0x00000006,
    MATERIAL       = 0x00000007,
    MATLIST        = 0x00000008,
    WORLD          = 0x0000000B,
    MATRIX         = 0x0000000D,
    FRAMELIST      = 0x0000000E,
    GEOMETRY       = 0x0000000F,
    CLUMP          = 0x00000010,
    LIGHT          = 0x00000012,
    ATOMIC         = 0x00000014,
    TEXTURENATIVE  = 0x00000015,
    TEXDICTIONARY  = 0x00000016,
    IMAGE          = 0x00000018,
    GEOMETRYLIST   = 0x0000001A,
    ANIMANIMATION  = 0x0000001B,
    RIGHTTORENDER  = 0x0000001F,  -- Pipline
    UVANIMDICT     = 0x0000002B,

    -- 插件/自定义类型
    BINMESHPLG     = 0x0000050E,
    MORPHPLG       = 0x00000105,
    SKINPLG        = 0x00000116,
    HANIMPLG       = 0x0000011E,
    MATFX          = 0x00000120,  -- MaterialEffectPLG
    UVANIMPLG      = 0x00000135,
    FRAME          = 0x0253F2FE,
    COLSECTION     = 0x0253F2FA,
    NIGHTCOLOR     = 0x0253F2F9,
    EFFECT2D       = 0x0253F2F8,
    REFLECTION     = 0x0253F2FC,
    SPECULAR       = 0x0253F2F6,
    BREAKABLE      = 0x0253F2FD,
}
