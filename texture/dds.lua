-- texture/dds.lua — DDS (DirectDraw Surface) 格式读写与 TXD 互转

local s_char = string.char
local s_byte = string.byte
local m_floor = math.floor
local m_ceil = math.ceil
local m_max = math.max
local t_concat = table.concat
-- _yield stored per-instance (self._yield) for concurrent async support

-- ====== DDS 枚举 ======
EnumDDPF = {
    ALPHAPIXELS  = 0x00000001,
    ALPHA        = 0x00000002,
    D3DFORMAT    = 0x00000004,
    RGB          = 0x00000040,
}

EnumDDSCaps1 = {
    COMPLEX = 0x00000008,
    TEXTURE = 0x00001000,
    MIPMAP  = 0x00400008,  -- COMPLEX | MIPMAP
}

-- ====== DDSPixelFormat (32 bytes) ======
DDSPixelFormat = RawStruct:define({
    { name = "blockSize",        type = uint32 },
    { name = "flags",            type = uint32 },
    { name = "d3dFormat",        type = uint32 },
    { name = "RGBBitCount",      type = uint32 },
    { name = "RBitMask",         type = uint32 },
    { name = "GBitMask",         type = uint32 },
    { name = "BBitMask",         type = uint32 },
    { name = "RGBAlphaBitMask",  type = uint32 },
})

-- ====== DDSCaps (16 bytes) ======
DDSCaps = RawStruct:define({
    { name = "caps1", type = uint32 },
    { name = "caps2", type = uint32 },
    { name = "reserved1", type = uint32 },
    { name = "reserved2", type = uint32 },
})

-- ====== DDSHeader ======
-- 字段多且有嵌入子结构, RawStruct:define 只用来生成 new() 默认值
DDSHeader = RawStruct:define({
    { name = "magic",             type = uint32 },
    { name = "blockSize",         type = uint32 },
    { name = "flags",             type = uint32 },
    { name = "height",            type = uint32 },
    { name = "width",             type = uint32 },
    { name = "pitchOrLinearSize", type = uint32 },
    { name = "depth",             type = uint32 },
    { name = "mipmapLevels",      type = uint32 },
})

-- ====== Mipmap 大小计算 ======
function getMipMapSize(width, height, d3dFormat)
    if d3dFormat == EnumD3DFormat.DXT1 then
        return m_max(1, m_floor((width + 3) / 4)) * m_max(1, m_floor((height + 3) / 4)) * 8
    elseif d3dFormat == EnumD3DFormat.DXT3 or d3dFormat == EnumD3DFormat.DXT5 then
        return m_max(1, m_floor((width + 3) / 4)) * m_max(1, m_floor((height + 3) / 4)) * 16
    else
        return width * height * 4  -- default RGBA
    end
end

-- ====== DDS 头部构建 ======
function makeDDSHeader(width, height, d3dFormat, mipmapCount)
    local hdr = DDSHeader:new()
    hdr.magic = 0x20534444
    hdr.blockSize = 124
    hdr.flags = 0x00001007  -- DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT
    hdr.height = height
    hdr.width = width
    hdr.pitchOrLinearSize = 0
    hdr.depth = 0
    hdr.mipmapLevels = mipmapCount or 1

    -- Pixel Format
    hdr.pixelFormat = DDSPixelFormat:new()
    hdr.pixelFormat.blockSize = 32
    hdr.pixelFormat.flags = EnumDDPF.D3DFORMAT
    hdr.pixelFormat.d3dFormat = d3dFormat

    -- Caps
    hdr.caps = DDSCaps:new()
    hdr.caps.caps1 = EnumDDSCaps1.TEXTURE
    if mipmapCount and mipmapCount > 1 then
        hdr.caps.caps1 = EnumDDSCaps1.MIPMAP
    end
    hdr.caps.caps2 = 0

    hdr.reserved2 = 0
    return hdr
end

-- DDSHeader 有嵌入子结构, 用手动 read/write 覆盖 RawStruct 生成的
DDSHeader.read = function(self, r)
    self.magic = r:u32()
    self.blockSize = r:u32()
    self.flags = r:u32()
    self.height = r:u32()
    self.width = r:u32()
    self.pitchOrLinearSize = r:u32()
    self.depth = r:u32()
    self.mipmapLevels = r:u32()
    r:skip(44)  -- reserved1 (11 * uint32)
    self.pixelFormat = DDSPixelFormat:new()
    self.pixelFormat:read(r)
    self.caps = DDSCaps:new()
    self.caps:read(r)
    self.reserved2 = r:u32()
end

DDSHeader.write = function(self, w)
    w:u32(self.magic or 0x20534444)
    w:u32(self.blockSize or 124)
    w:u32(self.flags or 0)
    w:u32(self.height or 0)
    w:u32(self.width or 0)
    w:u32(self.pitchOrLinearSize or 0)
    w:u32(self.depth or 0)
    w:u32(self.mipmapLevels or 1)
    -- 11 reserved uint32
    for _ = 1, 11 do w:u32(0) end
    if self.pixelFormat then self.pixelFormat:write(w)
    else DDSPixelFormat:new():write(w) end
    if self.caps then self.caps:write(w)
    else DDSCaps:new():write(w) end
    w:u32(self.reserved2 or 0)
end

DDSHeader.getSize = function(self)
    return 4 + 124  -- magic + block
end

-- ====== DDSTexture ======
DDSTexture = {}
DDSTexture.__index = DDSTexture

function DDSTexture:new()
    return setmetatable({
        ddsHeader = nil,
        mipmaps = {},  -- array of { data = string }
    }, DDSTexture)
end

function DDSTexture:read(r)
    self.ddsHeader = DDSHeader:new()
    self.ddsHeader:read(r)
    self.mipmaps = {}
    for i = 1, self.ddsHeader.mipmapLevels do
        local w = m_max(1, m_floor(self.ddsHeader.width  / 2 ^ (i - 1)))
        local h = m_max(1, m_floor(self.ddsHeader.height / 2 ^ (i - 1)))
        local sz = getMipMapSize(w, h, self.ddsHeader.pixelFormat.d3dFormat)
        self.mipmaps[i] = { data = r:raw(sz) }
    end
end

function DDSTexture:write(w)
    self.ddsHeader.mipmapLevels = #self.mipmaps
    self.ddsHeader:write(w)
    for i, mip in ipairs(self.mipmaps) do
        w:raw(mip.data)
    end
end

-- ====== TXD → DDS ======
function DDSTexture:convertFromTXD(txdTexture)
    local st = txdTexture.struct
    local fmt = st.textureFormat
    if not (fmt == EnumD3DFormat.DXT1 or fmt == EnumD3DFormat.DXT3 or fmt == EnumD3DFormat.DXT5
         or fmt == EnumD3DFormat.A8R8G8B8 or fmt == EnumD3DFormat.R5G6B5
         or fmt == EnumD3DFormat.A1R5G5B5 or fmt == EnumD3DFormat.A4R4G4B4
         or fmt == EnumD3DFormat.X8R8G8B8 or fmt == EnumD3DFormat.L8
         or fmt == EnumD3DFormat.A8L8) then
        return false
    end

    self.ddsHeader = makeDDSHeader(st.width, st.height, fmt, st.mipMapCount)

    -- 从 rawData 拆分 mipmap 数据
    self.mipmaps = {}
    if txdTexture.rawData and #txdTexture.rawData > 0 then
        local r = Reader.new(txdTexture.rawData)
        local firstMipSize = getMipMapSize(st.width, st.height, fmt)

        -- 跳过可选的 1024 字节调色板
        if r:remaining() >= 1028 then
            local peek = Reader.new(txdTexture.rawData)
            peek:skip(1024)
            if peek:u32() == firstMipSize then
                r:skip(1024)
            end
        end

        -- 检测是否有 per-mipmap size header（前 4 字节 == 第一个 mip 的大小）
        local hasSizeHeaders = false
        if r:remaining() >= 4 then
            local peek = Reader.new(txdTexture.rawData)
            local peekOffset = r.pos - 1  -- 0-indexed offset in raw string
            peek:skip(peekOffset)
            if peek:u32() == firstMipSize then
                hasSizeHeaders = true
            end
        end

        for i = 1, st.mipMapCount do
            local mw = m_max(1, m_floor(st.width  / 2 ^ (i - 1)))
            local mh = m_max(1, m_floor(st.height / 2 ^ (i - 1)))
            -- 跳过 size header（4 字节 LE uint32）
            if hasSizeHeaders and r:remaining() >= 4 then
                r:u32()
            end
            local sz = getMipMapSize(mw, mh, fmt)
            if r.pos - 1 + sz <= r.len then
                self.mipmaps[i] = { data = r:raw(sz) }
            elseif r:remaining() > 0 then
                self.mipmaps[i] = { data = r:raw(r:remaining()) }
                break
            else
                break
            end
        end
    end
    return true
end

-- ====== DDS → TXD ======
function DDSTexture:convertToTXD(txdTexture)
    local hdr = self.ddsHeader
    local fmt = hdr.pixelFormat.d3dFormat
    if not (fmt == EnumD3DFormat.DXT1 or fmt == EnumD3DFormat.DXT3 or fmt == EnumD3DFormat.DXT5
         or fmt == EnumD3DFormat.A8R8G8B8 or fmt == EnumD3DFormat.R5G6B5) then
        return false
    end

    local st = txdTexture.struct
    st.width = hdr.width
    st.height = hdr.height
    st.textureFormat = fmt
    st.mipMapCount = hdr.mipmapLevels

    -- 合并所有 mipmap 为 rawData
    local w2 = Writer.new()
    for _, mip in ipairs(self.mipmaps) do
        w2:raw(mip.data)
    end
    txdTexture.rawData = w2:build()
    return true
end

-- ====== 文件级 load/save ======
function DDSTexture:load(pathOrRaw)
    local data = pathOrRaw
    if fileExists(pathOrRaw) then
        local f = fileOpen(pathOrRaw)
        if f then data = fileRead(f, fileGetSize(f)); fileClose(f) end
    end
    self:read(Reader.new(data))
    return self
end

function DDSTexture:save(fileName)
    local w = Writer.new()
    self:write(w)
    local str = w:build()
    if fileName then
        if fileExists(fileName) then fileDelete(fileName) end
        local f = fileCreate(fileName)
        fileWrite(f, str); fileClose(f)
        return true
    end
    return str
end
-- ====== DXT Block Decoding (string-based, zero Buffer calls) ======

-- Pre-computed lookup tables
local R5 = {}; for i = 0, 31 do R5[i] = m_floor((i * 255 + 15) / 31) end
local G6 = {}; for i = 0, 63 do G6[i] = m_floor((i * 255 + 31) / 63) end
local B5 = {}; for i = 0, 31 do B5[i] = m_floor((i * 255 + 15) / 31) end
local A4 = {}; for i = 0, 15 do A4[i] = i * 17 end

-- IDX2[byte] = {idx0, idx1, idx2, idx3} — 4x 2-bit indices from a byte
local IDX2 = {}
for b = 0, 255 do
    IDX2[b] = {b % 4, m_floor(b / 4) % 4, m_floor(b / 16) % 4, m_floor(b / 64) % 4}
end

-- Fast RGB565 decode
local function decodeRGB565(v)
    local t = v / 0x800; local r = R5[(t - t % 1) % 0x20]
    t = v / 0x20; local g = G6[(t - t % 1) % 0x40]
    return r, g, B5[v % 0x20]
end

-- Returns: seg0..seg3 — 16-byte BGRA strings (4 pixels each), or nil if row OOB
local function decodeDXT1Block(r, bx, by, w, h)
    local c0 = r:u16(); local c1 = r:u16(); local indices = r:u32()
    local r0, g0, b0 = decodeRGB565(c0)
    local r1, g1, b1 = decodeRGB565(c1)

    -- Pre-compute 4 colors as locals (no table/closure allocation)
    local cr0, cg0, cb0 = r0, g0, b0
    local cr1, cg1, cb1 = r1, g1, b1
    local cr2, cg2, cb2, cr3, cg3, cb3, ca3
    if c0 > c1 then
        local t = (2*r0+r1)/3; cr2 = t - t % 1; t = (2*g0+g1)/3; cg2 = t - t % 1; t = (2*b0+b1)/3; cb2 = t - t % 1
        t = (r0+2*r1)/3; cr3 = t - t % 1; t = (g0+2*g1)/3; cg3 = t - t % 1; t = (b0+2*b1)/3; cb3 = t - t % 1; ca3 = 255
    else
        local t = (r0+r1)/2; cr2 = t - t % 1; t = (g0+g1)/2; cg2 = t - t % 1; t = (b0+b1)/2; cb2 = t - t % 1
        cr3, cg3, cb3, ca3 = 0, 0, 0, 0
    end

    local ib0 = indices % 256; local t = indices/256; local ib1 = (t - t % 1) % 256
    t = indices/65536; local ib2 = (t - t % 1) % 256
    t = indices/16777216; local ib3 = t - t % 1
    local t0, t1, t2, t3 = IDX2[ib0], IDX2[ib1], IDX2[ib2], IDX2[ib3]

    -- Pre-compute BGRA byte strings for all 4 colors (avoids repeated s_char calls)
    local P0 = s_char(cb0, cg0, cr0, 255)
    local P1 = s_char(cb1, cg1, cr1, 255)
    local P2 = s_char(cb2, cg2, cr2, 255)
    local P3 = s_char(cb3, cg3, cr3, ca3)
    local PIX = {P0, P1, P2, P3}
    local ZERO = s_char(0,0,0,0)

    local x0 = bx * 4
    local s0, s1, s2, s3
    if by*4 < h and x0 < w then
        s0 = PIX[t0[1]+1]
        if x0+1 < w then s0 = s0 .. PIX[t0[2]+1] else s0 = s0 .. ZERO end
        if x0+2 < w then s0 = s0 .. PIX[t0[3]+1] else s0 = s0 .. ZERO end
        if x0+3 < w then s0 = s0 .. PIX[t0[4]+1] else s0 = s0 .. ZERO end
    end
    if by*4+1 < h and x0 < w then
        s1 = PIX[t1[1]+1]
        if x0+1 < w then s1 = s1 .. PIX[t1[2]+1] else s1 = s1 .. ZERO end
        if x0+2 < w then s1 = s1 .. PIX[t1[3]+1] else s1 = s1 .. ZERO end
        if x0+3 < w then s1 = s1 .. PIX[t1[4]+1] else s1 = s1 .. ZERO end
    end
    if by*4+2 < h and x0 < w then
        s2 = PIX[t2[1]+1]
        if x0+1 < w then s2 = s2 .. PIX[t2[2]+1] else s2 = s2 .. ZERO end
        if x0+2 < w then s2 = s2 .. PIX[t2[3]+1] else s2 = s2 .. ZERO end
        if x0+3 < w then s2 = s2 .. PIX[t2[4]+1] else s2 = s2 .. ZERO end
    end
    if by*4+3 < h and x0 < w then
        s3 = PIX[t3[1]+1]
        if x0+1 < w then s3 = s3 .. PIX[t3[2]+1] else s3 = s3 .. ZERO end
        if x0+2 < w then s3 = s3 .. PIX[t3[3]+1] else s3 = s3 .. ZERO end
        if x0+3 < w then s3 = s3 .. PIX[t3[4]+1] else s3 = s3 .. ZERO end
    end
    return s0, s1, s2, s3
end

local function decodeDXT3Block(r, bx, by, w, h)
    local aa = {}
    for i = 0, 7 do
        local v = r:u8()
        aa[i*2+1] = A4[v % 0x10]; aa[i*2+2] = A4[m_floor(v/0x10)]
    end
    local c0 = r:u16(); local c1 = r:u16(); local indices = r:u32()
    local r0, g0, b0 = decodeRGB565(c0); local r1, g1, b1 = decodeRGB565(c1)
    local cr0, cg0, cb0 = r0, g0, b0; local cr1, cg1, cb1 = r1, g1, b1
    local cr2 = m_floor((2*r0+r1)/3); local cg2 = m_floor((2*g0+g1)/3); local cb2 = m_floor((2*b0+b1)/3)
    local cr3 = m_floor((r0+2*r1)/3); local cg3 = m_floor((g0+2*g1)/3); local cb3 = m_floor((b0+2*b1)/3)

    local ib0 = indices % 256; local ib1 = m_floor(indices/256) % 256
    local ib2 = m_floor(indices/65536) % 256; local ib3 = m_floor(indices/16777216)
    local t = {IDX2[ib0], IDX2[ib1], IDX2[ib2], IDX2[ib3]}

    local function C(idx)
        if idx == 0 then return cr0, cg0, cb0
        elseif idx == 1 then return cr1, cg1, cb1
        elseif idx == 2 then return cr2, cg2, cb2
        else return cr3, cg3, cb3 end
    end

    local x0 = bx * 4
    local s = {}
    for row = 0, 3 do
        local y = by*4 + row
        if y >= h or x0 >= w then break end
        local ti = t[row+1]
        local seg = {}
        for col = 0, 3 do
            if x0+col >= w then break end
            local r, g, b = C(ti[col+1])
            seg[col+1] = s_char(b, g, r, aa[row*4+col+1])
        end
        s[row+1] = t_concat(seg)
    end
    return s[1], s[2], s[3], s[4]
end

local function decodeDXT5Block(r, bx, by, w, h)
    local a0 = r:u8(); local a1 = r:u8()
    local aBytes = {r:u8(), r:u8(), r:u8(), r:u8(), r:u8(), r:u8()}
    local alphaIdx = {}
    for i = 0, 15 do
        local bitPos = i*3; local byteIdx = m_floor(bitPos/8); local bitShift = bitPos % 8
        local ab = aBytes[byteIdx+1]; local val = m_floor(ab/(2^bitShift)) % 8
        if bitShift > 5 then
            local nb = aBytes[byteIdx+2] or 0
            val = val + ((nb % (2^(bitShift-5))) * (2^(8-bitShift)))
        end
        alphaIdx[i] = val
    end

    local alphaVals = {a0, a1}
    if a0 > a1 then
        for i = 1, 6 do alphaVals[i+2] = m_floor(((8-(i+1))*a0 + i*a1)/7) end
    else
        for i = 1, 4 do alphaVals[i+2] = m_floor(((4-i)*a0 + (i-1)*a1)/3) end
        alphaVals[7] = 0; alphaVals[8] = 255
    end

    local c0 = r:u16(); local c1 = r:u16(); local indices = r:u32()
    local r0, g0, b0 = decodeRGB565(c0); local r1, g1, b1 = decodeRGB565(c1)
    local cr0, cg0, cb0 = r0, g0, b0; local cr1, cg1, cb1 = r1, g1, b1
    local cr2 = m_floor((2*r0+r1)/3); local cg2 = m_floor((2*g0+g1)/3); local cb2 = m_floor((2*b0+b1)/3)
    local cr3 = m_floor((r0+2*r1)/3); local cg3 = m_floor((g0+2*g1)/3); local cb3 = m_floor((b0+2*b1)/3)

    local ib0 = indices % 256; local ib1 = m_floor(indices/256) % 256
    local ib2 = m_floor(indices/65536) % 256; local ib3 = m_floor(indices/16777216)
    local t = {IDX2[ib0], IDX2[ib1], IDX2[ib2], IDX2[ib3]}

    local function C(idx)
        if idx == 0 then return cr0, cg0, cb0
        elseif idx == 1 then return cr1, cg1, cb1
        elseif idx == 2 then return cr2, cg2, cb2
        else return cr3, cg3, cb3 end
    end

    local x0 = bx * 4
    local s = {}
    for row = 0, 3 do
        local y = by*4 + row
        if y >= h or x0 >= w then break end
        local ti = t[row+1]
        local seg = {}
        for col = 0, 3 do
            if x0+col >= w then break end
            local r, g, b = C(ti[col+1])
            seg[col+1] = s_char(b, g, r, alphaVals[alphaIdx[row*4+col]+1])
        end
        s[row+1] = t_concat(seg)
    end
    return s[1], s[2], s[3], s[4]
end

-- DDSTexture:decodeToBGRA() → string (raw BGRA pixel data for top mip)
function DDSTexture:decodeToBGRA()
    local hdr = self.ddsHeader
    local fmt = hdr.pixelFormat.d3dFormat
    local w, h = hdr.width, hdr.height
    if not (fmt == EnumD3DFormat.DXT1 or fmt == EnumD3DFormat.DXT3 or fmt == EnumD3DFormat.DXT5) then
        return false
    end

    local blockDecoder
    if fmt == EnumD3DFormat.DXT1 then blockDecoder = decodeDXT1Block
    elseif fmt == EnumD3DFormat.DXT3 then blockDecoder = decodeDXT3Block
    elseif fmt == EnumD3DFormat.DXT5 then blockDecoder = decodeDXT5Block
    end

    local raw = self.mipmaps[1] and self.mipmaps[1].data or ""
    if #raw == 0 then return false end

    local r = Reader.new(raw)
    local blocksX = m_ceil(w/4); local blocksY = m_ceil(h/4)

    -- Flat output: process by block-row, concat 4 scanlines at a time
    local out = {}
    for by = 0, blocksY-1 do
        local r0, r1, r2, r3 = {}, {}, {}, {}
        for bx = 0, blocksX-1 do
            local s0, s1, s2, s3 = blockDecoder(r, bx, by, w, h)
            if s0 then r0[bx+1] = s0 end
            if s1 then r1[bx+1] = s1 end
            if s2 then r2[bx+1] = s2 end
            if s3 then r3[bx+1] = s3 end
        end
        out[#out+1] = t_concat(r0)
        if by*4+1 < h then out[#out+1] = t_concat(r1) end
        if by*4+2 < h then out[#out+1] = t_concat(r2) end
        if by*4+3 < h then out[#out+1] = t_concat(r3) end
        if self._yield then self._yield() end  -- async yield point (per-instance, supports concurrent)
    end
    return t_concat(out)
end

-- ====== Timing & Async ======

function DDSTexture:decodeToBGRATimed()
    local t = os.clock()
    local result = self:decodeToBGRA()
    print(string.format('[DDS:decode] %.2fs  %dx%d', os.clock() - t, self.ddsHeader.width, self.ddsHeader.height))
    return result
end

function DDSTexture:decodeToBGRAAsync()
    local s = self
    return coroutine.create(function()
        s._yield = function() coroutine.yield() end
        local result = DDSTexture.decodeToBGRA(s)
        s._yield = nil
        return result
    end)
end

-- ====== TXDIO 注册 ======
if TXDIO then
    TXDIO.register("imageDecoder", "dds_binary", "string", function(source, tex)
        local data = source
        if fileExists(source) then
            local f = fileOpen(source)
            if f then data = fileRead(f, fileGetSize(f)); fileClose(f) end
        end
        if data:sub(1, 4) ~= "DDS " then return false end
        local dds = DDSTexture:new(); dds:load(data)
        return dds:convertToTXD(tex)
    end)
    TXDIO.register("imageDecoder", "ddstexture", "table", function(source, tex)
        if getmetatable(source) ~= DDSTexture then return false end
        return source:convertToTXD(tex)
    end)
    TXDIO.register("imageEncoder", "dds", "", function(tex, format)
        -- handles default (nil/"" → "dds") for DXT textures
        local st = tex.struct
        local isDXT = st.textureFormat == EnumD3DFormat.DXT1
            or st.textureFormat == EnumD3DFormat.DXT3
            or st.textureFormat == EnumD3DFormat.DXT5
        if not isDXT then return nil end
        local dds = DDSTexture:new()
        if not dds:convertFromTXD(tex) then return nil end
        return dds:save()
    end)
    TXDIO.register("imageEncoder", "dds", "dds", function(tex, format)
        local dds = DDSTexture:new()
        if not dds:convertFromTXD(tex) then return nil end
        return dds:save()
    end)
end
