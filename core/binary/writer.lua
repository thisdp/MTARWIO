-- Writer.lua — 链式二进制写入器
-- 支持占位符 + 回填，用于 Section 的 size 字段等场景

local stringChar = string.char
local stringRep = string.rep
local tableConcat = table.concat
local mathFrexp = math.frexp
local mathHuge = math.huge

-- Float → Hex 转换
local function float2Hex(n)
    if n == 0 then return 0 end
    local sign = 0
    if n < 0 then sign = 0x80; n = -n end
    local mant, expo = mathFrexp(n)
    if mant ~= mant then
        return 0xFF880000
    elseif mant == mathHuge or expo > 0x80 then
        return 0x880000 + (sign == 0 and 0x7F or 0xFF) * 0x1000000
    elseif (mant == 0.0 and expo == 0) or expo < -0x7E then
        return sign * 0x1000000
    end
    expo = expo + 0x7E
    mant = (mant * 2.0 - 1.0) * 0x800000
    local t1 = expo / 0x2
    local t2 = mant / 0x10000
    local t3 = mant / 0x100
    local h1 = sign + t1 - t1 % 1
    local h2 = (expo % 0x2) * 0x80 + t2 - t2 % 1
    local h3 = (t3 - t3 % 1) % 0x100
    local h4 = mant % 0x100
    return (h1 * 0x1000000 + h2 * 0x10000 + h3 * 0x100 + h4) - (h1 * 0x1000000 + h2 * 0x10000 + h3 * 0x100 + h4) % 1
end

local function writeNumLE(num, bytes)
    local parts = {}
    for i = 1, bytes do
        local byte = num % 0x100
        parts[i] = stringChar(byte - byte % 1)
        num = (num - byte) / 0x100
    end
    return tableConcat(parts)
end

Writer = {}
Writer.__index = Writer

function Writer.new()
    return setmetatable({ buf = {} }, Writer)
end

function Writer:u8(v)
    self.buf[#self.buf + 1] = stringChar(v % 0x100)
    return self
end

function Writer:u16(v)
    if v < 0 then v = v + 0x10000 end
    self.buf[#self.buf + 1] = writeNumLE(v, 2)
    return self
end

function Writer:u32(v)
    if v < 0 then v = v + 4294967296.0 end
    self.buf[#self.buf + 1] = writeNumLE(v, 4)
    return self
end

function Writer:u24(v)
    if v < 0 then v = v + 0x1000000 end
    self.buf[#self.buf + 1] = writeNumLE(v, 3)
    return self
end

function Writer:i8(v)
    return self:u8(v)
end

function Writer:i16(v)
    return self:u16(v)
end

function Writer:i32(v)
    return self:u32(v)
end

function Writer:f32(v)
    return self:u32(float2Hex(v))
end

-- 字符串（定长，不足补 \0）
function Writer:str(s, len)
    local padded = s .. stringRep("\0", len - #s)
    self.buf[#self.buf + 1] = padded:sub(1, len)
    return self
end

-- 原始字节
function Writer:raw(s)
    self.buf[#self.buf + 1] = s
    return self
end

-- 语义复合类型
function Writer:bool32(v)
    return self:u32(v and 1 or 0)
end

function Writer:bool8(v)
    return self:u8(v and 1 or 0)
end

function Writer:rgba(t)
    return self:u8(t[1]):u8(t[2]):u8(t[3]):u8(t[4])
end

function Writer:vec2(t)
    return self:f32(t[1]):f32(t[2])
end

function Writer:vec3(t)
    return self:f32(t[1]):f32(t[2]):f32(t[3])
end

function Writer:vec4(t)
    return self:f32(t[1]):f32(t[2]):f32(t[3]):f32(t[4])
end

function Writer:mat3x3(m)
    for x = 1, 3 do
        for y = 1, 3 do
            self:f32(m[x][y])
        end
    end
    return self
end

-- 占位符：预留 u32 位置，返回回填函数
function Writer:reserveU32()
    local idx = #self.buf + 1
    self.buf[idx] = "\0\0\0\0"
    return {
        fill = function(val)
            self.buf[idx] = writeNumLE(val, 4)
        end
    }
end

-- 当前已写入的字节数（用于外部计算 offset）
function Writer:position()
    local total = 0
    for i = 1, #self.buf do
        total = total + #self.buf[i]
    end
    return total
end

-- 输出最终字符串
function Writer:build()
    return tableConcat(self.buf)
end

Writer = Writer
