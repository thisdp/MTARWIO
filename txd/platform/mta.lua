-- txd/platform/mta.lua — MTA DX texture/rendertarget support for TXDIO

local function hasMtaDx()
    return type(dxGetTexturePixels) == "function"
        and type(dxCreateTexture) == "function"
        and type(isElement) == "function"
        and type(getElementType) == "function"
        and type(destroyElement) == "function"
end

if not hasMtaDx() then return end

-- 文件路径 → 使用 MTA 原生 C++ dxCreateTexture 加载 (比纯 Lua 解码快)
TXDIO.register("imageDecoder", "mta_file", "string", function(source, tex)
    if not fileExists(source) then return false end
    local texEl = dxCreateTexture(source)
    if not texEl then return false end
    -- dxGetTexturePixels(surfaceIndex, texture, pixelsFormat, textureFormat, mipmaps)
    local ddsData = dxGetTexturePixels(0, texEl, "dds", "dxt1", true)
    destroyElement(texEl)
    if not ddsData then return false end
    local dds = DDSTexture:new()
    dds:load(ddsData)
    return dds:convertToTXD(tex)
end)

-- MTA texture element (内存中的 texture)
TXDIO.register("imageDecoder", "mta_texture", "userdata", function(source, tex)
    if not isElement(source) then return false end
    if getElementType(source) ~= "texture" then return false end
    local ddsData = dxGetTexturePixels(0, source, "dds", "dxt1", true)
    if not ddsData then return false end
    local dds = DDSTexture:new()
    dds:load(ddsData)
    return dds:convertToTXD(tex)
end)

-- MTA rendertarget element
TXDIO.register("imageDecoder", "mta_rendertarget", "userdata", function(source, tex)
    if not isElement(source) then return false end
    if getElementType(source) ~= "rendertarget" then return false end
    local ddsData = dxGetTexturePixels(0, source, "dds", "dxt1", true)
    if not ddsData then return false end
    local dds = DDSTexture:new()
    dds:load(ddsData)
    return dds:convertToTXD(tex)
end)
