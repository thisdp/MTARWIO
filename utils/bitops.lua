-- bitops.lua — 位操作工具（Lua 5.1 兼容，纯算术实现）

-- Lua 5.1 没有位运算符，全部用算术模拟

local floor = math.floor

-- 左移: lshift(n, bits) = n << bits
function lshift(n, bits)
    return floor(n * 2 ^ bits + 0.5)
end

-- 右移: rshift(n, bits) = n >> bits
function rshift(n, bits)
    return floor(n / 2 ^ bits)
end

-- 创建位掩码: bitmask(width) = 2^width - 1
function bitmask(width)
    return 2 ^ width - 1
end

-- 提取位域: bExtract(num, pos, length) → 提取 pos 起 length 位
function bExtract(num, pos, length)
    length = length or 1
    return rshift(num, pos) % (2 ^ length)
end

-- 组装多个 bool 到位标志: bAssemble(true, false, true) → 5 (最低位在前)
function bAssemble(...)
    local result = 0
    for i = 1, select("#", ...) do
        if select(i, ...) then
            result = result + 2 ^ (i - 1)
        end
    end
    return result
end

-- 替换单个位: bReplace(num, bit, pos)
function bReplace(num, bit, pos)
    local v = num % (2 ^ (pos + 1)) / (2 ^ pos)
    local p = v - v % 1
    local newBit = ((p == 1) or (bit == 1)) and 1 or 0
    return num - p * (2 ^ pos) + newBit * (2 ^ pos)
end

-- 位或: bitOr(a, b) = a | b
function bitOr(a, b)
    local result = 0
    local shift = 0
    while a > 0 or b > 0 do
        if (a % 2 == 1) or (b % 2 == 1) then
            result = result + 2 ^ shift
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        shift = shift + 1
    end
    return result
end
