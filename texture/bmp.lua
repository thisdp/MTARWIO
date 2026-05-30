-- texture/bmp.lua — BMP 位图完整读写、缩放、行列操作

-- ====== BMP 枚举 ======
EnumBMPCompression = { NONE = 0, RLE8 = 1, RLE4 = 2, BITFIELDS = 3, JPEG = 4, PNG = 5 }

-- ====== BMPFileHeader (14 bytes) ======
BMPFileHeader = RawStruct:define({
    { name = "fileType",   type = uint16 },
    { name = "fileSize",   type = uint32 },
    { name = "reserved",   type = uint32 },
    { name = "dataOffset", type = uint32 },
})

-- ====== BMPInfoHeader (40 bytes) ======
BMPInfoHeader = RawStruct:define({
    { name = "size",             type = uint32 },
    { name = "width",            type = int32 },
    { name = "height",           type = int32 },
    { name = "planes",           type = uint16 },
    { name = "bitDepth",         type = uint16 },
    { name = "compression",      type = uint32 },
    { name = "imageSize",        type = uint32 },
    { name = "hResolution",      type = int32 },
    { name = "vResolution",      type = int32 },
    { name = "colorsUsed",       type = uint32 },
    { name = "colorsImportant",  type = uint32 },
})

-- ====== BMPPalette ======
BMPPalette = {}
BMPPalette.__index = BMPPalette

function BMPPalette:new()
    return setmetatable({ colors = {} }, BMPPalette)
end

function BMPPalette:read(r, colorCount)
    for i = 1, colorCount do
        self.colors[i] = { r:u8(), r:u8(), r:u8(), r:u8() }
    end
end

function BMPPalette:write(w)
    for _, c in ipairs(self.colors) do
        w:u8(c[1]):u8(c[2]):u8(c[3]):u8(c[4] or 0)
    end
end

function BMPPalette:set(index, r, g, b)
    if index < 1 or index > #self.colors then
        error("Palette index out of range [1," .. #self.colors .. "]: " .. index)
    end
    self.colors[index] = { r, g, b, 0 }
end

function BMPPalette:add(r, g, b)
    self.colors[#self.colors + 1] = { r or 0, g or 0, b or 0, 0 }
    return #self.colors
end

function BMPPalette:getColor(index)
    return self.colors[index]
end

-- ====== PixelData ======
PixelData = {}
PixelData.__index = PixelData

function PixelData:new()
    return setmetatable({
        width = 0, height = 0, depth = 24,
        rowAlignment = 4,
        dataType = "raw",   -- "raw" | "table"
        data = "",
    }, PixelData)
end

function PixelData:read(r, size)
    self.dataType = "raw"
    self.data = r:raw(size)
end

function PixelData:write(w)
    if self.dataType ~= "raw" then self:convert("raw") end
    w:raw(self.data)
end

function PixelData:rowSize()
    local align = self.rowAlignment or 4
    local bytesPerRow = math.ceil(self.depth * self.width / 8)
    return math.floor((bytesPerRow + align - 1) / align) * align
end

function PixelData:getSize()
    return self:rowSize() * self.height
end

function PixelData:flipVertically(_yield)
    if self.dataType ~= "raw" then self:convert("raw", _yield) end
    local rs = self:rowSize()
    local t = {}
    for y = 1, self.height do
        local src = (self.height - y) * rs + 1
        t[y] = self.data:sub(src, src + rs - 1)
        if _yield and y % 8 == 0 then _yield() end  -- yield per 8 rows
    end
    self.data = table.concat(t)
end

function PixelData:convert(toType, _yield)
    if self.dataType == toType then return true end
    if toType == "raw" then
        local w = Writer.new()
        local pick
        if     self.depth == 8  then pick = function(v) w:u8(v) end
        elseif self.depth == 16 then pick = function(v) w:u16(v) end
        elseif self.depth == 24 then pick = function(v) w:u24(v) end
        elseif self.depth == 32 then pick = function(v) w:u32(v) end
        else error("Unsupported depth: " .. self.depth) end
        local dt = self.data
        for y = 1, self.height do
            local rStart = w:position()
            for x = 1, self.width do pick(dt[y][x]) end
            local align = self.rowAlignment or 4
            local pad = (align - (w:position() - rStart) % align) % align
            if pad > 0 then w:raw(string.rep("\0", pad)) end
            if _yield then _yield() end  -- yield per row (per-pixel loop already done)
        end
        self.data = w:build()
        self.dataType = "raw"
    elseif toType == "table" then
        local r = Reader.new(self.data)
        local pick
        if     self.depth == 8  then pick = function() return r:u8() end
        elseif self.depth == 16 then pick = function() return r:u16() end
        elseif self.depth == 24 then pick = function() return r:u24() end
        elseif self.depth == 32 then pick = function() return r:u32() end
        else error("Unsupported depth: " .. self.depth) end
        local rs = self:rowSize()
        self.data = {}
        for y = 1, self.height do
            self.data[y] = {}
            local rowStart = r.pos
            for x = 1, self.width do self.data[y][x] = pick() end
            r.pos = rowStart + rs  -- 跳到下一行 (含 padding)
            if _yield then _yield() end  -- yield per row
        end
        self.dataType = "table"
    end
end

function PixelData:resize(newWidth, newHeight, mode)
    if self.dataType ~= "table" then self:convert("table") end
    local old, ow, oh = self.data, self.width, self.height
    local nd = {}
    if mode == "pixel" then
        for y = 1, newHeight do
            nd[y] = {}
            for x = 1, newWidth do
                nd[y][x] = old[math.ceil(y / newHeight * oh)][math.ceil(x / newWidth * ow)]
            end
        end
        self.data, self.width, self.height = nd, newWidth, newHeight
    end
end

function PixelData:addRow(insertAfter, fillColor)
    if self.dataType ~= "table" then self:convert("table") end
    insertAfter = insertAfter or self.height
    fillColor = fillColor or 0xFFFFFFFF
    self.height = self.height + 1
    table.insert(self.data, insertAfter + 1, {})
    for x = 1, self.width do self.data[insertAfter + 1][x] = fillColor end
    return insertAfter + 1
end

function PixelData:addCol(insertAfter, fillColor)
    if self.dataType ~= "table" then self:convert("table") end
    insertAfter = insertAfter or self.width
    fillColor = fillColor or 0xFFFFFFFF
    self.width = self.width + 1
    for y = 1, self.height do
        table.insert(self.data[y], insertAfter + 1, fillColor)
    end
    return insertAfter + 1
end

-- ====== BMP ======
BMP = {}
BMP.__index = BMP

function BMP:new()
    return setmetatable({
        fileHeader = nil,
        infoHeader = nil,
        palette    = nil,
        pixels     = nil,
    }, BMP)
end

function BMP:load(pathOrRaw)
    local data = pathOrRaw
    if fileExists(pathOrRaw) then
        local f = fileOpen(pathOrRaw)
        if f then data = fileRead(f, fileGetSize(f)); fileClose(f) end
    end
    local r = Reader.new(data)

    self.fileHeader = BMPFileHeader:new()
    self.fileHeader:read(r)
    if self.fileHeader.fileType ~= 0x4D42 then
        error("Unsupported BMP type: 0x" .. string.format("%04X", self.fileHeader.fileType))
    end

    self.infoHeader = BMPInfoHeader:new()
    self.infoHeader:read(r)
    if self.infoHeader.compression ~= 0 then
        error("Compressed BMP not supported")
    end

    -- 调色板
    if self.infoHeader.bitDepth <= 8 then
        local n = self.infoHeader.colorsUsed
        if n == 0 then n = 2 ^ self.infoHeader.bitDepth end
        self.palette = BMPPalette:new()
        self.palette:read(r, n)
    end

    -- 像素数据
    r.pos = self.fileHeader.dataOffset + 1
    local size = self.fileHeader.fileSize - self.fileHeader.dataOffset
    self.pixels = PixelData:new()
    self.pixels.width  = self.infoHeader.width
    self.pixels.height = math.abs(self.infoHeader.height)
    self.pixels.depth  = self.infoHeader.bitDepth
    self.pixels:read(r, size)
    -- BMP 标准 bottom-up → 翻转为 top-down
    self.pixels:flipVertically(self._yield)

    return self
end

function BMP:save(fileName)
    local px = self.pixels
    local oldType = px.dataType
    local yld = self._yield

    if px.dataType ~= "raw" then px:convert("raw", yld) end
    -- BMP 标准 bottom-up (height>0)，内部 top-down → 需要 flip
    px:flipVertically(yld)  -- top-down → bottom-up

    local info = self.infoHeader
    info.width    = px.width
    info.height   = px.height
    info.bitDepth = px.depth
    info.imageSize = px:getSize()
    info.colorsUsed = self.palette and #self.palette.colors or 0

    self.fileHeader.dataOffset = 14 + info:getSize()
    if self.palette then
        self.fileHeader.dataOffset = self.fileHeader.dataOffset + #self.palette.colors * 4
    end
    self.fileHeader.fileSize = self.fileHeader.dataOffset + px:getSize()

    local w = Writer.new()
    self.fileHeader:write(w)
    self.infoHeader:write(w)
    if self.palette then self.palette:write(w) end
    w:raw(px.data)

    local str = w:build()
    if fileName then
        if fileExists(fileName) then fileDelete(fileName) end
        local f = fileCreate(fileName)
        fileWrite(f, str); fileClose(f)
        return true
    end

    -- 恢复原始格式
    px:flipVertically(yld)  -- bottom-up → top-down
    if oldType == "table" then px:convert("table", yld) end
    return str
end

-- ====== BMPTexture — TXD 互转辅助 ======
BMPTexture = {}
BMPTexture.__index = BMPTexture

local function calcUncompressedMipSize(width, height, fmt)
    if fmt == EnumD3DFormat.A8R8G8B8 or fmt == EnumD3DFormat.X8R8G8B8
        or fmt == EnumD3DFormat.A8B8G8R8 then
        return width * height * 4
    elseif fmt == EnumD3DFormat.R5G6B5 or fmt == EnumD3DFormat.A1R5G5B5
        or fmt == EnumD3DFormat.A4R4G4B4 or fmt == EnumD3DFormat.A8L8 then
        return width * height * 2
    elseif fmt == EnumD3DFormat.L8 then
        return width * height
    end
    return width * height * 4
end

local function splitRawMipmaps(txdTexture)
    local st = txdTexture.struct
    local raw = txdTexture.rawData or ""
    local w, h = st.width, st.height
    local fmt = st.textureFormat
    local mipCount = st.mipMapCount or 1
    local expectedFirst = calcUncompressedMipSize(w, h, fmt)

    local paletteSize = 0
    local r = Reader.new(raw)

    if #raw >= 1024 + 4 then
        local r2 = Reader.new(raw)
        r2:skip(1024)
        if r2:u32() == expectedFirst then
            paletteSize = 1024
        end
    end

    if paletteSize > 0 then
        r:skip(paletteSize)
    end

    local hasSizeHeaders = false
    if r:remaining() >= 4 then
        local peek = Reader.new(raw:sub((paletteSize or 0) + 1))
        if peek:u32() == expectedFirst then
            hasSizeHeaders = true
        end
    end

    local mipmaps = {}
    for i = 1, mipCount do
        local mw = math.max(1, math.floor(w / 2 ^ (i - 1)))
        local mh = math.max(1, math.floor(h / 2 ^ (i - 1)))
        local size = calcUncompressedMipSize(mw, mh, fmt)
        if hasSizeHeaders and r:remaining() >= 4 then
            size = r:u32()
        end
        if size <= 0 or r:remaining() <= 0 then break end
        if r:remaining() < size then
            mipmaps[i] = r:raw(r:remaining())
            break
        end
        mipmaps[i] = r:raw(size)
    end

    return mipmaps
end

local function decodeToBGRA(raw, width, height, fmt, _yield)
    if fmt == EnumD3DFormat.A8R8G8B8 then
        return raw
    end

    local r = Reader.new(raw)
    local w = Writer.new()
    local count = width * height

    if fmt == EnumD3DFormat.X8R8G8B8 then
        for i = 1, count do
            local b = r:u8()
            local g = r:u8()
            local rr = r:u8()
            r:u8()
            w:u8(b):u8(g):u8(rr):u8(255)
            if _yield and i % width == 0 then _yield() end  -- yield per row
        end
        return w:build()
    end

    if fmt == EnumD3DFormat.R5G6B5 then
        for i = 1, count do
            local v = r:u16()
            local r5 = math.floor(v / 0x800) % 0x20
            local g6 = math.floor(v / 0x20) % 0x40
            local b5 = v % 0x20
            w:u8(math.floor(b5 * 255 / 31))
             :u8(math.floor(g6 * 255 / 63))
             :u8(math.floor(r5 * 255 / 31))
             :u8(255)
            if _yield and i % width == 0 then _yield() end
        end
        return w:build()
    end

    if fmt == EnumD3DFormat.A1R5G5B5 then
        for i = 1, count do
            local v = r:u16()
            local a1 = math.floor(v / 0x8000)
            local r5 = math.floor(v / 0x400) % 0x20
            local g5 = math.floor(v / 0x20) % 0x20
            local b5 = v % 0x20
            w:u8(math.floor(b5 * 255 / 31))
             :u8(math.floor(g5 * 255 / 31))
             :u8(math.floor(r5 * 255 / 31))
             :u8(a1 == 1 and 255 or 0)
            if _yield and i % width == 0 then _yield() end
        end
        return w:build()
    end

    if fmt == EnumD3DFormat.A4R4G4B4 then
        for i = 1, count do
            local v = r:u16()
            local a4 = math.floor(v / 0x1000)
            local r4 = math.floor(v / 0x100) % 0x10
            local g4 = math.floor(v / 0x10) % 0x10
            local b4 = v % 0x10
            w:u8(math.floor(b4 * 255 / 15))
             :u8(math.floor(g4 * 255 / 15))
             :u8(math.floor(r4 * 255 / 15))
             :u8(math.floor(a4 * 255 / 15))
            if _yield and i % width == 0 then _yield() end
        end
        return w:build()
    end

    if fmt == EnumD3DFormat.L8 then
        for i = 1, count do
            local l = r:u8()
            w:u8(l):u8(l):u8(l):u8(255)
            if _yield and i % width == 0 then _yield() end
        end
        return w:build()
    end

    if fmt == EnumD3DFormat.A8L8 then
        for i = 1, count do
            local v = r:u16()
            local l = v % 0x100
            local a = math.floor(v / 0x100)
            w:u8(l):u8(l):u8(l):u8(a)
            if _yield and i % width == 0 then _yield() end
        end
        return w:build()
    end

    return raw
end

function BMPTexture:new()
    return setmetatable({ bmp = BMP:new() }, BMPTexture)
end

function BMPTexture:load(pathOrRaw)
    self.bmp = BMP:new()
    self.bmp:load(pathOrRaw)
    return self
end

function BMPTexture:save(fileName)
    return self.bmp:save(fileName)
end

function BMPTexture:convertFromTXD(txdTexture)
    local st = txdTexture.struct
    local fmt = st.textureFormat
    if fmt == EnumD3DFormat.DXT1 or fmt == EnumD3DFormat.DXT3 or fmt == EnumD3DFormat.DXT5 then
        return false
    end

    local mips = splitRawMipmaps(txdTexture)
    local top = mips[1] or ""
    local bgra = decodeToBGRA(top, st.width, st.height, fmt, self._yield)

    local bmp = BMP:new()
    bmp.fileHeader = BMPFileHeader:new()
    bmp.infoHeader = BMPInfoHeader:new()
    bmp.infoHeader.planes = 1
    bmp.infoHeader.compression = 0
    bmp.palette = nil

    bmp.pixels = PixelData:new()
    bmp.pixels.width = st.width
    bmp.pixels.height = st.height
    bmp.pixels.depth = 32
    bmp.pixels.rowAlignment = 4
    bmp.pixels.dataType = "raw"
    bmp.pixels.data = bgra

    self.bmp = bmp
    return true
end

function BMPTexture:convertToTXD(txdTexture)
    local bmp = self.bmp
    if not bmp or not bmp.pixels then
        return false
    end

    local px = bmp.pixels
    if px.dataType ~= "raw" then px:convert("raw") end

    local st = txdTexture.struct
    st.width = px.width
    st.height = px.height
    st.textureFormat = EnumD3DFormat.A8R8G8B8
    st.mipMapCount = 1
    st.depth = 32
    txdTexture.rawData = px.data
    return true
end

-- ====== Timing & Async ======

function BMPTexture:convertFromTXDTimed(txdTexture)
    local t = os.clock()
    local result = self:convertFromTXD(txdTexture)
    local st = txdTexture.struct
    print(string.format('[BMP:convertFromTXD] %.2fs  %dx%d', os.clock() - t, st.width, st.height))
    return result
end

function BMPTexture:convertToTXDTimed(txdTexture)
    local t = os.clock()
    local result = self:convertToTXD(txdTexture)
    local st = txdTexture.struct
    print(string.format('[BMP:convertToTXD] %.2fs  %dx%d', os.clock() - t, st.width, st.height))
    return result
end

function BMPTexture:convertFromTXDAsync(txdTexture)
    local s = self
    return coroutine.create(function()
        s._yield = function() coroutine.yield() end
        local result = BMPTexture.convertFromTXD(s, txdTexture)
        s._yield = nil
        return result
    end)
end

function BMPTexture:convertToTXDAsync(txdTexture)
    local s = self
    return coroutine.create(function()
        s._yield = function() coroutine.yield() end
        local result = BMPTexture.convertToTXD(s, txdTexture)
        s._yield = nil
        return result
    end)
end

function BMP:loadAsync(pathOrRaw)
    local s = self
    return coroutine.create(function()
        s._yield = function() coroutine.yield() end
        local result = BMP.load(s, pathOrRaw)
        s._yield = nil
        return result
    end)
end

function BMP:saveAsync(fileName)
    local s = self
    return coroutine.create(function()
        s._yield = function() coroutine.yield() end
        local result = BMP.save(s, fileName)
        s._yield = nil
        return result
    end)
end

-- ====== TXDIO 注册 ======
if TXDIO then
    TXDIO.register("imageDecoder", "bmp_binary", "string", function(source, tex)
        local data = source
        if fileExists(source) then
            local f = fileOpen(source)
            if f then data = fileRead(f, fileGetSize(f)); fileClose(f) end
        end
        if data:sub(1, 2) ~= "BM" then return false end
        local bmp = BMPTexture:new(); bmp:load(data)
        return bmp:convertToTXD(tex)
    end)
    TXDIO.register("imageDecoder", "bmptexture", "table", function(source, tex)
        if getmetatable(source) ~= BMPTexture then return false end
        return source:convertToTXD(tex)
    end)
    TXDIO.register("imageDecoder", "bmp", "table", function(source, tex)
        if getmetatable(source) ~= BMP then return false end
        local bt = BMPTexture:new(); bt.bmp = source
        return bt:convertToTXD(tex)
    end)
    TXDIO.register("imageDecoder", "pixeldata", "table", function(source, tex)
        if not source.data or not source.width or not source.height or not source.depth then return false end
        if source.pixels or source.bmp or source.ddsHeader or source.fileHeader then return false end
        return TXDIO.setTextureFromPixelData(tex, source)
    end)
    TXDIO.register("imageEncoder", "bmp", "", function(tex, format)
        -- default (nil/"") for uncompressed textures
        local isDXT = tex.struct.textureFormat == EnumD3DFormat.DXT1
            or tex.struct.textureFormat == EnumD3DFormat.DXT3
            or tex.struct.textureFormat == EnumD3DFormat.DXT5
        if isDXT then return nil end  -- DXT goes to DDS encoder
        local bmp = BMPTexture:new()
        if not bmp:convertFromTXD(tex) then return nil end
        return bmp:save()
    end)
    TXDIO.register("imageEncoder", "bmp", "bmp", function(tex, format)
        local bmp = BMPTexture:new()
        if not bmp:convertFromTXD(tex) then return nil end
        return bmp:save()
    end)
end
