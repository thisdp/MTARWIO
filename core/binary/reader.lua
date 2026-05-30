-- Reader.lua — 链式二进制读取器
-- 基于游标的流式读取，每次调用自动推进位置

local stringChar = string.char
local stringByte = string.byte
local stringSub = string.sub
local mathHuge = math.huge

-- Float ↔ Hex 转换（从旧版移植）
local function hex2Float(c)
    if c == 0 then return 0.0 end
    local b1 = (c / 0x1000000) % 1
    b1 = c / 0x1000000 - b1
    c = c - b1 * 0x1000000
    local b2 = (c / 0x10000) % 1
    b2 = c / 0x10000 - b2
    c = c - b2 * 0x10000
    local b3 = (c / 0x100) % 1
    b3 = c / 0x100 - b3
    c = c - b3 * 0x100
    local b4 = c - c % 1
    local sign = (b1 > 0x7F) and -1 or 1
    local temp = b2 / 0x80
    local expo = (b1 % 0x80) * 2 + temp - temp % 1
    local mant = (b2 % 0x80 * 0x100 + b3) * 0x100 + b4
    if mant == 0 and expo == 0 then
        return sign * 0.0
    elseif expo == 0xFF then
        if mant == 0 then return sign * mathHuge
        else return 0.0 / 0.0 end
    end
    return sign * (1.0 + mant / 0x800000) * 2 ^ (expo - 0x7F)
end

Reader = {}
Reader.__index = Reader

function Reader.new(data)
    return setmetatable({
        data = data,
        pos = 1,
        len = #data,
    }, Reader)
end

function Reader:remaining()
    return self.len - self.pos + 1
end

function Reader:skip(n)
    self.pos = self.pos + n
    return self
end

-- 无符号整数
function Reader:u8()
    if self.pos > self.len then return 0 end
    local v = stringByte(self.data, self.pos)
    self.pos = self.pos + 1
    return v
end

function Reader:u16()
    if self.pos + 1 > self.len then return 0 end
    local b1, b2 = stringByte(self.data, self.pos, self.pos + 1)
    self.pos = self.pos + 2
    return b1 + b2 * 0x100
end

function Reader:u32()
    if self.pos + 3 > self.len then return 0 end
    local b1, b2, b3, b4 = stringByte(self.data, self.pos, self.pos + 3)
    self.pos = self.pos + 4
    return b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000
end

function Reader:u24()
    local b1, b2, b3 = stringByte(self.data, self.pos, self.pos + 2)
    self.pos = self.pos + 3
    return b1 + b2 * 0x100 + b3 * 0x10000
end

-- 有符号整数
function Reader:i8()
    local v = self:u8()
    return v >= 0x80 and v - 0x100 or v
end

function Reader:i16()
    local v = self:u16()
    return v >= 0x8000 and v - 0x10000 or v
end

function Reader:i32()
    local v = self:u32()
    return v >= 0x80000000 and v - 0x100000000 or v
end

-- 浮点数
function Reader:f32()
    return hex2Float(self:u32())
end

-- 字符串（定长，自动截断尾部 \0）
function Reader:str(len)
    local s = stringSub(self.data, self.pos, self.pos + len - 1)
    self.pos = self.pos + len
    local nullPos = s:find("\0")
    return nullPos and s:sub(1, nullPos - 1) or s
end

-- 原始字节
function Reader:raw(len)
    local s = stringSub(self.data, self.pos, self.pos + len - 1)
    self.pos = self.pos + len
    return s
end

-- 语义复合类型
function Reader:bool32()
    return self:u32() ~= 0
end

function Reader:bool8()
    return self:u8() ~= 0
end

function Reader:rgba()
    return { self:u8(), self:u8(), self:u8(), self:u8() }
end

function Reader:vec2()
    return { self:f32(), self:f32() }
end

function Reader:vec3()
    return { self:f32(), self:f32(), self:f32() }
end

function Reader:vec4()
    return { self:f32(), self:f32(), self:f32(), self:f32() }
end

function Reader:mat3x3()
    return {
        { self:f32(), self:f32(), self:f32() },
        { self:f32(), self:f32(), self:f32() },
        { self:f32(), self:f32(), self:f32() },
    }
end

-- 读取 Section 头部 (type, size, version) 并返回
-- 不创建对象，由调用方根据 type 分配
function Reader:sectionHeader()
    return self:u32(), self:u32(), self:u32()
end

Reader = Reader
