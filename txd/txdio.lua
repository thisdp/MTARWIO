-- txd/txdio.lua — TXD 纹理字典 I/O

-- ====== 平台/设备枚举 ======
EnumDeviceID = {
    UNKNOWN = 0, D3D8 = 1, D3D9 = 2, GCN = 3,
    NULL = 4, OPENGL = 5, PS2 = 6, SOFTRAS = 7, XBOX = 8, PSP = 9,
}

EnumFilterMode = {
    NEAREST = 1, LINEAR = 2, MIPNEAREST = 3,
    MIPLINEAR = 4, LINEARMIPNEAREST = 5, LINEARMIPLINEAR = 6,
}

EnumAddressing = {
    WRAP = 1, MIRROR = 2, CLAMP = 3, BORDER = 4,
}

EnumD3DFormat = {
    L8 = 50, A8L8 = 51, A1R5G5B5 = 25, A8B8G8R8 = 32,
    R5G6B5 = 23, A4R4G4B4 = 26, X8R8G8B8 = 22, X1R5G5B5 = 24,
    A8R8G8B8 = 21,
    DXT1 = 0x31545844, DXT3 = 0x33545844, DXT5 = 0x35545844,
}

-- ====== TextureNativeStruct (0x01) ======
TextureNativeStruct = Struct:define({
    { name = "platform",     type = uint32 },
    { name = "filterFlags",  type = uint32 },
    { name = "name",         type = str32 },
    { name = "mask",         type = str32 },
    { name = "maskFlags",    type = uint32 },
    { name = "textureFormat",type = uint32 },
    { name = "width",        type = uint16 },
    { name = "height",       type = uint16 },
    { name = "depth",        type = uint8 },
    { name = "mipMapCount",  type = uint8 },
    { name = "texCodeType",  type = uint8 },
    { name = "flags",        type = uint8 },
})

-- ====== TextureNativeExtension (0x03) ======
TextureNativeExtension = Extension:extend({})

function TextureNativeExtension:read(r) end  -- 通常为空 (body_size=0)
function TextureNativeExtension:write(w)
    self.size = 0
    w:u32(self.type):u32(0):u32(self.version)
end
function TextureNativeExtension:getSize()
    self.size = 0
    return 12
end

-- ====== TextureNative (0x15) ======
-- 特殊处理: struct 之后是 palette + mipmaps 原始数据
TextureNative = Section:extend({ typeID = 0x15 })

function TextureNative:read(r)
    self.struct = TextureNativeStruct:readFrom(r, self)
    -- TextureNativeStruct header body_size 包含 palette + mipmaps
    -- Schema 只读了 88 字节固定字段, 剩余的是变长数据
    local fixedBodySize = 88
    local paletteAndMips = self.struct.size - fixedBodySize
    if paletteAndMips > 0 then
        self.rawData = r:raw(paletteAndMips)
    end
    -- extension: 如果有剩余字节则尝试读取，否则创建空实例
    local remaining = self.size - (self.struct.size + 12)
    if remaining >= 12 then
        self.extension = TextureNativeExtension:readFrom(r, self)
    else
        self.extension = TextureNativeExtension:new()
        self.extension.parent = self
    end
end

function TextureNative:write(w)
    self:getSize()
    w:u32(self.type):u32(self.size):u32(self.version)
    self.struct:write(w)
    if self.rawData then
        w:raw(self.rawData)
    end
    self.extension:write(w)
end

function TextureNative:getSize()
    local body = self.struct:getSize() + #(self.rawData or "")
        + self.extension:getSize()
    self.size = body
    return body + 12
end

SectionRegistry.register(TextureNative)

-- ====== TextureDictionaryStruct ======
TextureDictionaryStruct = Struct:define({
    { name = "textureCount", type = uint16 },
    { name = "deviceID",     type = uint16 },
})

-- ====== TextureDictionary (0x16) ======
TextureDictionary = Section:define(0x16, {
    { name = "struct",   type = TextureDictionaryStruct },
    { name = "textures", type = {TextureNative, "struct.textureCount"} },
})

-- ====== TXDIO — 纹理字典 I/O ======
-- Decoder: fn(source, txdTexture) -> true(handled) | false(not mine)
-- Encoder: fn(txdTexture, format) -> data | nil(not mine)
TXDIO = {}
TXDIO._decoders = {}       -- { name -> {type=srcType, fn=fn} }
TXDIO._decoderOrder = {}   -- ordered name list
TXDIO._encoders = {}       -- { name -> {fmt=fmtKey, fn=fn} }
TXDIO._encoderOrder = {}   -- ordered name list

function TXDIO.register(category, name, dispatchKey, fn)
    if category == "imageDecoder" then
        if not TXDIO._decoders[name] then
            TXDIO._decoderOrder[#TXDIO._decoderOrder + 1] = name
        end
        TXDIO._decoders[name] = {type = dispatchKey, fn = fn}
    elseif category == "imageEncoder" then
        if not TXDIO._encoders[name] then
            TXDIO._encoderOrder[#TXDIO._encoderOrder + 1] = name
        end
        TXDIO._encoders[name] = {fmt = dispatchKey, fn = fn}
    end
end

function TXDIO.unregister(category, name)
    if category == "imageDecoder" then
        TXDIO._decoders[name] = nil
        for i, n in ipairs(TXDIO._decoderOrder) do
            if n == name then table.remove(TXDIO._decoderOrder, i); break end
        end
    elseif category == "imageEncoder" then
        TXDIO._encoders[name] = nil
        for i, n in ipairs(TXDIO._encoderOrder) do
            if n == name then table.remove(TXDIO._encoderOrder, i); break end
        end
    end
end

local function ensureTextureDictionary(self)
    if not self.textureDictionary then
        self.textureDictionary = TextureDictionary:new()
        self.textureDictionary.struct = TextureDictionaryStruct:new()
        self.textureDictionary.struct.textureCount = 0
        self.textureDictionary.struct.deviceID = EnumDeviceID.D3D9
        self.textureDictionary.textures = {}
    end
end

function TXDIO.setTextureFromPixelData(txdTexture, px)
    if not px then return false end
    if px.dataType ~= "raw" then px:convert("raw") end
    if px.depth ~= 32 then
        error("Only 32-bit PixelData is supported for TXD write", 2)
    end
    local st = txdTexture.struct
    st.width = px.width
    st.height = px.height
    st.textureFormat = EnumD3DFormat.A8R8G8B8
    st.mipMapCount = 1
    st.depth = 32
    txdTexture.rawData = px.data
    return true
end


-- ====== TXDIO 实例方法 ======

function TXDIO:new()
    return setmetatable({
        textureDictionary = nil,
    }, { __index = TXDIO })
end

function TXDIO:load(pathOrRaw)
    local data = pathOrRaw
    if fileExists(pathOrRaw) then
        local f = fileOpen(pathOrRaw)
        if f then
            data = fileRead(f, fileGetSize(f))
            fileClose(f)
        end
    end
    local r = Reader.new(data)
    self.textureDictionary = SectionRegistry.read(r)
    return self
end

function TXDIO:save(fileName)
    local w = Writer.new()
    self.textureDictionary:write(w)
    local str = w:build()
    if fileName then
        if fileExists(fileName) then fileDelete(fileName) end
        local f = fileCreate(fileName)
        fileWrite(f, str)
        fileClose(f)
        return true
    end
    return str
end

function TXDIO:listTextures()
    local list = {}
    for i, tex in ipairs(self.textureDictionary.textures or {}) do
        list[i] = tex.struct.name
    end
    return list
end

function TXDIO:getTextureByName(name)
    for _, tex in ipairs(self.textureDictionary.textures or {}) do
        if tex.struct.name == name then return tex end
    end
    return nil
end

function TXDIO:getTextureNativeDataByIndex(index)
    local tex = self.textureDictionary and self.textureDictionary.textures
    tex = tex and tex[index]
    return tex and tex.struct or nil
end

function TXDIO:getTextureNativeDataByName(name)
    local list = {}
    for _, tex in ipairs(self.textureDictionary.textures or {}) do
        if tex.struct.name == name then
            list[#list + 1] = tex
        end
    end
    return unpack(list)
end

function TXDIO:removeTextureDataByIndex(index)
    if not self.textureDictionary then return false end
    if self.textureDictionary.textures[index] then
        table.remove(self.textureDictionary.textures, index)
        self.textureDictionary.struct.textureCount = #self.textureDictionary.textures
        return true
    end
    return false
end

function TXDIO:removeTextureDataByName(name)
    if not self.textureDictionary then return false end
    for i, tex in ipairs(self.textureDictionary.textures) do
        if tex.struct.name == name then
            table.remove(self.textureDictionary.textures, i)
            self.textureDictionary.struct.textureCount = #self.textureDictionary.textures
            return true
        end
    end
    return false
end

function TXDIO:add(source, name)
    ensureTextureDictionary(self)
    -- auto name
    if name == nil then
        if type(source) == "string" and fileExists(source) then
            name = source:match("([^/\\]+)%.[^%.\\/]+$") or source:match("([^/\\]+)$") or "texture"
        else
            name = "texture_" .. (#self.textureDictionary.textures + 1)
        end
    end
    -- create TextureNative
    local tex = TextureNative:new()
    tex.struct = TextureNativeStruct:new()
    tex.extension = TextureNativeExtension:new()
    tex.struct.platform = EnumDeviceID.D3D9
    tex.struct.filterFlags = 0x1106
    tex.struct.name = name
    tex.struct.mask = ""
    tex.struct.maskFlags = 0x8200
    tex.struct.textureFormat = EnumD3DFormat.A8R8G8B8
    tex.struct.width = 0
    tex.struct.height = 0
    tex.struct.depth = 32
    tex.struct.mipMapCount = 1
    tex.struct.texCodeType = 4
    tex.struct.flags = 0x8
    tex.rawData = ""

    table.insert(self.textureDictionary.textures, tex)
    self.textureDictionary.struct.textureCount = #self.textureDictionary.textures

    if source ~= nil then
        local srcType = type(source)
        for _, decName in ipairs(TXDIO._decoderOrder) do
            local dec = TXDIO._decoders[decName]
            if dec and dec.type == srcType then
                if dec.fn(source, tex) then
                    return tex
                end
            end
        end
        -- no decoder matched → remove
        table.remove(self.textureDictionary.textures)
        self.textureDictionary.struct.textureCount = #self.textureDictionary.textures
        return nil
    end
    return tex
end

function TXDIO:getTexture(textureID, format)
    if not self.textureDictionary then return false end
    local tex = self.textureDictionary.textures[textureID]
    if not tex then return false end

    local fmtKey = format or ""  -- "" matches default encoders
    for _, encName in ipairs(TXDIO._encoderOrder) do
        local enc = TXDIO._encoders[encName]
        if enc and enc.fmt == fmtKey then
            local result = enc.fn(tex, format)
            if result then return result end
        end
    end
    return false
end
