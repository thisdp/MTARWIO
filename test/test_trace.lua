-- Trace the actual DXT decoding
local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"
dofile(BASE .. "/core/binary/reader.lua")
dofile(BASE .. "/core/binary/writer.lua")

-- Replicate the DXT decoder inline with traces
local function decodeRGB565(v)
    local r = math.floor(v / 0x800) % 0x20
    local g = math.floor(v / 0x20) % 0x40
    local b = v % 0x20
    return math.floor(r * 255 / 31), math.floor(g * 255 / 63), math.floor(b * 255 / 31)
end

local POW4 = {1, 4, 16, 64, 256, 1024, 4096, 16384, 65536, 262144, 1048576, 4194304, 16777216, 67108864, 268435456, 1073741824}

-- Block: c0=0x001F(blue), c1=0xFFE0(yellow), indices=0xE4E4E4E4(alt 0,1,2,3)
local block = string.char(0x1F, 0x00, 0xE0, 0xFF, 0xE4, 0xE4, 0xE4, 0xE4)

local r = Reader.new(block)
local c0 = r:u16()
local c1 = r:u16()
local indices = r:u32()

print(string.format("c0=0x%04X (%d), c1=0x%04X (%d), indices=0x%08X (%d)",
    c0, c0, c1, c1, indices, indices))

local r0, g0, b0 = decodeRGB565(c0)
local r1, g1, b1 = decodeRGB565(c1)
print(string.format("c0: R=%d G=%d B=%d   c1: R=%d G=%d B=%d", r0, g0, b0, r1, g1, b1))

-- colors table
local colors = {}
if c0 > c1 then
    colors = {
        {r0, g0, b0, 255},
        {r1, g1, b1, 255},
        {math.floor((2*r0+r1)/3), math.floor((2*g0+g1)/3), math.floor((2*b0+b1)/3), 255},
        {math.floor((r0+2*r1)/3), math.floor((g0+2*g1)/3), math.floor((b0+2*b1)/3), 255},
    }
    print("c0 > c1: 4-color mode")
else
    colors = {
        {r0, g0, b0, 255},
        {r1, g1, b1, 255},
        {math.floor((r0+r1)/2), math.floor((g0+g1)/2), math.floor((b0+b1)/2), 255},
        {0, 0, 0, 0},
    }
    print("c0 <= c1: 3-color + transparent")
end

for i = 1, 4 do
    print(string.format("  color[%d]: R=%d G=%d B=%d A=%d", i, colors[i][1], colors[i][2], colors[i][3], colors[i][4]))
end

print("\nPixel decoding (first 8 pixels):")
for row = 0, 3 do
    for col = 0, 3 do
        local shift = row * 4 + col
        if shift < 8 then
            local idx = math.floor(indices / POW4[shift + 1]) % 4 + 1
            local c = colors[idx]
            print(string.format("  [r=%d,c=%d] shift=%2d idx=%d → R=%3d G=%3d B=%3d A=%3d",
                row, col, shift, idx-1, c[1], c[2], c[3], c[4]))
        end
    end
end
