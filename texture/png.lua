local PixelData = PixelData
local m_floor, m_ceil, m_min, m_max, m_abs = math.floor, math.ceil, math.min, math.max, math.abs
local m_huge = math.huge
-- _yield passed per-operation via call chain (not module-level) for concurrent async support

local function round(x)
  local t = x + 0.5
  return t - t % 1
end

local function band(a, b)
  local res = 0
  local bit = 1
  while a > 0 or b > 0 do
    local a1 = a % 2
    local b1 = b % 2
    if a1 == 1 and b1 == 1 then
      res = res + bit
    end
    a = (a - a1) / 2
    b = (b - b1) / 2
    bit = bit * 2
  end
  return res
end

local function bor(a, b)
  local res = 0
  local bit = 1
  while a > 0 or b > 0 do
    local a1 = a % 2
    local b1 = b % 2
    if a1 == 1 or b1 == 1 then
      res = res + bit
    end
    a = (a - a1) / 2
    b = (b - b1) / 2
    bit = bit * 2
  end
  return res
end

local function bxor(a, b)
  local res = 0
  local bit = 1
  while a > 0 or b > 0 do
    local a1 = a % 2
    local b1 = b % 2
    if a1 ~= b1 then
      res = res + bit
    end
    a = (a - a1) / 2
    b = (b - b1) / 2
    bit = bit * 2
  end
  return res
end

local function lshift(a, n)
  return (a * (2 ^ n)) % 2 ^ 32
end

local function rshift(a, n)
  local t = a / (2 ^ n)
  return t - t % 1
end

local function extract(a, pos, len)
  return band(rshift(a, pos), (2 ^ len) - 1)
end

Buffer = {}
Buffer.__index = Buffer

function Buffer.new(len)
  local data = {}
  for i = 1, len do
    data[i] = 0
  end
  return setmetatable({ data = data, size = len }, Buffer)
end

function Buffer.fromString(s)
  local len = #s
  local data = {}
  for i = 1, len do
    data[i] = string.byte(s, i)
  end
  return setmetatable({ data = data, size = len }, Buffer)
end

function Buffer:toString()
  local out = {}
  for i = 1, self.size do
    out[i] = string.char(self.data[i] or 0)
  end
  return table.concat(out)
end

function Buffer:length()
  return self.size
end

function Buffer:readu8(offset)
  return self.data[offset + 1] or 0
end

function Buffer:writeu8(offset, value)
  self.data[offset + 1] = value % 256
end

-- Batch pixel read/write (avoids per-byte method calls)
-- Native BGRA order: bytes are B, G, R, A in memory
function Buffer:readBGRA(offset)
  local d = self.data
  return (d[offset + 1] or 0), (d[offset + 2] or 0), (d[offset + 3] or 0), (d[offset + 4] or 0)
end
function Buffer:writeBGRA(offset, b, g, r, a)
  local d = self.data
  d[offset + 1] = b; d[offset + 2] = g; d[offset + 3] = r; d[offset + 4] = a
end
-- Swapped RGBA order: returns r,g,b,a (reads native BGRA, swaps R/B)
function Buffer:readRGBA(offset)
  local d = self.data
  return (d[offset + 3] or 0), (d[offset + 2] or 0), (d[offset + 1] or 0), (d[offset + 4] or 0)
end
function Buffer:writeRGBA(offset, r, g, b, a)
  local d = self.data
  d[offset + 1] = b; d[offset + 2] = g; d[offset + 3] = r; d[offset + 4] = a
end

function Buffer:readu16(offset)
  local d = self.data
  return (d[offset + 1] or 0) + (d[offset + 2] or 0) * 256
end

function Buffer:writeu16(offset, value)
  local d = self.data
  d[offset + 1] = value % 256
  local t = value / 256; d[offset + 2] = (t - t % 1) % 256
end

function Buffer:readu32(offset)
  local d = self.data
  return (d[offset + 1] or 0) + (d[offset + 2] or 0) * 256
       + (d[offset + 3] or 0) * 65536 + (d[offset + 4] or 0) * 16777216
end

function Buffer:writeu32(offset, value)
  local d = self.data
  d[offset + 1] = value % 256
  local t = value / 256; d[offset + 2] = (t - t % 1) % 256
  t = value / 65536; d[offset + 3] = (t - t % 1) % 256
  t = value / 16777216; d[offset + 4] = t - t % 1
end

-- Big-endian read/write
function Buffer:readu32be(offset)
  local d = self.data
  return (d[offset + 1] or 0) * 16777216 + (d[offset + 2] or 0) * 65536
       + (d[offset + 3] or 0) * 256 + (d[offset + 4] or 0)
end

function Buffer:writeu32be(offset, value)
  local d = self.data
  local t = value / 16777216; d[offset + 1] = t - t % 1
  t = value / 65536; d[offset + 2] = (t - t % 1) % 256
  t = value / 256; d[offset + 3] = (t - t % 1) % 256
  d[offset + 4] = value % 256
end

function Buffer:writestring(offset, s)
  local d = self.data
  for i = 1, #s do
    d[offset + i] = string.byte(s, i)  -- inlined writeu8
  end
end

function Buffer:readstring(offset, len)
  local d = self.data
  local out = {}
  for i = 1, len do
    out[i] = string.char(d[offset + i] or 0)  -- inlined readu8
  end
  return table.concat(out)
end

function Buffer:copy(dstOffset, src, srcOffset, length)
    local dd = self.data
    local sd = src.data
    for i = 0, length - 1 do
        dd[dstOffset + i + 1] = sd[srcOffset + i + 1] or 0
    end
end

function Buffer:readbits(bitOffset, n)
  local value = 0
  for i = 0, n - 1 do
    local byteIndex = rshift(bitOffset + i, 3)
    local bitIndex = (bitOffset + i) % 8
    local bit = extract(self:readu8(byteIndex), bitIndex, 1)
    value = value + bit * (2 ^ i)
  end
  return value
end

function Buffer:writebits(bitOffset, n, value)
  local d = self.data  -- inline data access
  for i = 0, n - 1 do
	local b = bitOffset + i
    local t = b/8;
	local byteIndex = t-t%1  -- m_floor
    local bitIndex = b % 8
    local mask = 2 ^ bitIndex
    local byte = d[byteIndex + 1] or 0  -- inlined readu8
    local t1 = byte / mask;
	byte = byte - (t1 - t1 % 1) % 2 * mask  -- m_floor + clear bit
    local t2 = value / (2 ^ i)
    if (t2 - t2 % 1) % 2 == 1 then  -- m_floor + extract bit
      byte = byte + mask  -- set the bit
    end
    d[byteIndex + 1] = byte  -- inlined writeu8
  end
end

local crc32_lookup = {
  0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
  0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
  0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
  0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
  0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
  0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
  0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
  0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
  0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
  0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
  0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
  0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
  0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
  0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
  0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
  0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
  0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
  0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
  0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
  0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
  0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
  0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
  0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
  0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
  0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
  0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
  0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
  0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
  0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
  0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
  0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
  0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D,
}

-- Precomputed 8-bit XOR table (avoids bxor in crc32)
local XOR8 = {}
for a = 0, 255 do
  local row = {}
  for b = 0, 255 do row[b] = bxor(a, b) end
  XOR8[a] = row
end

-- 32-bit XOR via 4 byte lookups (faster than pure-Lua bxor in hot loop)
local function xor32(a, b)
  local a0, a1, a2, a3 = a % 256, (a / 256) % 256, (a / 65536) % 256, (a / 16777216) % 256
  local b0, b1, b2, b3 = b % 256, (b / 256) % 256, (b / 65536) % 256, (b / 16777216) % 256
  -- floor correction for division results
  local t = a1; a1 = t - t % 1; t = a2; a2 = t - t % 1; t = a3; a3 = t - t % 1
  t = b1; b1 = t - t % 1; t = b2; b2 = t - t % 1; t = b3; b3 = t - t % 1
  return XOR8[a0][b0] + XOR8[a1][b1] * 256 + XOR8[a2][b2] * 65536 + XOR8[a3][b3] * 16777216
end

local function crc32(buf, i, j)
    local code = 0xFFFFFFFF
    local bd = buf.data
    for k = i, j do
        local idx = XOR8[code % 256][bd[k + 1] or 0] + 1
        code = xor32((code / 256) - (code / 256) % 1, crc32_lookup[idx])
    end
    return 0xFFFFFFFF - code
end

local function createHuffmanTable(lengths)
  local MAX_BITS = 15
  local lengthCount = {}
  lengthCount[0] = 0
  for _, length in ipairs(lengths) do
    if length > 0 then
      lengthCount[length] = (lengthCount[length] or 0) + 1
    end
  end

  local lastCode = 1
  local nextCode = {}
  for bits = 1, MAX_BITS do
    lastCode = lshift(lastCode + (lengthCount[bits - 1] or 0), 1)
    nextCode[bits] = lastCode
  end

  local mapping = {}
  local codeValues = {}
  local codeLengths = {}
  for i, length in ipairs(lengths) do
    if length > 0 then
      mapping[nextCode[length]] = i - 1
      codeValues[i - 1] = extract(nextCode[length], 0, length)
      codeLengths[i - 1] = length
      nextCode[length] = nextCode[length] + 1
    end
  end

  return mapping, codeValues, codeLengths
end

local function adler32(input, offset, length)
  local s0, s1, count = 1, 0, 0
  local id = input.data  -- inline data access
  for i = offset, offset + length - 1 do
    s0 = s0 + (id[i + 1] or 0)
    s1 = s1 + s0
    count = count + 1
    if count == 8400000 then
      s0 = s0 % 65521; s1 = s1 % 65521; count = 0
    end
  end
  return (s1 % 65521) * 65536 + (s0 % 65521)  -- inlined bor+lshift
end

local function zlib_inflate(input, output)
  local header0 = input:readu8(0)
  local header1 = input:readu8(1)
  assert(extract(header0, 0, 4) == 8, "invalid zlib comp method")
  assert(extract(header0, 4, 4) <= 7, "invalid zlib window size")
  assert(extract(header1, 5, 1) == 0, "preset dictionary is not allowed")
  assert((header0 * 256 + header1) % 31 == 0, "zlib header sum mismatch")

  local readOffset = 2
  local readOffsetBit = 0

  local function readBit()
    local bit = extract(input:readu8(readOffset), readOffsetBit, 1)
    readOffsetBit = readOffsetBit + 1
    if readOffsetBit == 8 then
      readOffsetBit = 0
      readOffset = readOffset + 1
    end
    return bit
  end

  local function readBits(n)
    local bits = input:readbits(readOffset * 8 + readOffsetBit, n)
    readOffsetBit = readOffsetBit + n
    local t = readOffsetBit / 8; readOffset = readOffset + (t - t % 1)
    readOffsetBit = readOffsetBit % 8
    return bits
  end

  local function readHuffmanTable(huffmanTable)
    local code = 2 + readBit()
    while not huffmanTable[code] do
      code = 2 * code + readBit()
    end
    return huffmanTable[code]
  end

  local writeOffset = 0

  local FIXED_LIT = {}
  for i = 0, 143 do
    FIXED_LIT[#FIXED_LIT + 1] = 8
  end
  for i = 144, 255 do
    FIXED_LIT[#FIXED_LIT + 1] = 9
  end
  for i = 256, 279 do
    FIXED_LIT[#FIXED_LIT + 1] = 7
  end
  for i = 280, 287 do
    FIXED_LIT[#FIXED_LIT + 1] = 8
  end

  local fixedLitTable = createHuffmanTable(FIXED_LIT)
  local fixedDistTable = createHuffmanTable({
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
  })

  local LIT_LEN = {
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
    163, 195, 227, 258,
  }
  local LIT_EXTRA = { 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
  local DIST_OFF = {
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049,
    3073, 4097, 6145, 8193, 12289, 16385, 24577,
  }
  local DIST_EXTRA = { 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
  local LEN_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

  repeat
    local bfinal = readBit()
    local btype = readBits(2)
    assert(btype ~= 3, "reserved btype")

    if btype == 0 then
      if readOffsetBit > 0 then
        readOffset = readOffset + 1
        readOffsetBit = 0
      end
      local len = input:readu16(readOffset)
      local nlen = input:readu16(readOffset + 2)
      assert(len + nlen == 0xFFFF, "len ~= nlen")
      readOffset = readOffset + 4
      output:copy(writeOffset, input, readOffset, len)
      writeOffset = writeOffset + len
      readOffset = readOffset + len
    else
      local litTable = fixedLitTable
      local distTable = fixedDistTable

      if btype == 2 then
        local litsCount = readBits(5) + 257
        local distsCount = readBits(5) + 1
        local codesCount = readBits(4) + 4

        local codeLengths = {}
        for i = 1, codesCount do
          codeLengths[LEN_ORDER[i] + 1] = readBits(3)
        end
        local codeLengthsTable = createHuffmanTable(codeLengths)

        local litLengths = {}
        local litLength = 0
        repeat
          local code = readHuffmanTable(codeLengthsTable)
          local repeatCount = 1
          if code <= 15 then
            litLength = code
          elseif code == 16 then
            repeatCount = readBits(2) + 3
          elseif code == 17 then
            litLength = 0
            repeatCount = readBits(3) + 3
          elseif code == 18 then
            litLength = 0
            repeatCount = readBits(7) + 11
          end
          for _ = 1, repeatCount do
            litLengths[#litLengths + 1] = litLength
          end
        until #litLengths >= litsCount
        litTable = createHuffmanTable(litLengths)

        local distLengths = {}
        local distLength = 0
        repeat
          local code = readHuffmanTable(codeLengthsTable)
          local repeatCount = 1
          if code <= 15 then
            distLength = code
          elseif code == 16 then
            repeatCount = readBits(2) + 3
          elseif code == 17 then
            distLength = 0
            repeatCount = readBits(3) + 3
          elseif code == 18 then
            distLength = 0
            repeatCount = readBits(7) + 11
          end
          for _ = 1, repeatCount do
            distLengths[#distLengths + 1] = distLength
          end
        until #distLengths >= distsCount
        distTable = createHuffmanTable(distLengths)
      end

      repeat
        local v = readHuffmanTable(litTable)
        if v < 0x100 then
          output:writeu8(writeOffset, v)
          writeOffset = writeOffset + 1
        elseif v > 0x100 then
          local len = LIT_LEN[v - 0x100]
          if v > 0x10C then
            len = len + readBits(LIT_EXTRA[v - 0x108])
          elseif v > 0x108 then
            len = len + readBit()
          end

          local d = readHuffmanTable(distTable)
          local dist = DIST_OFF[d + 1]
          if d > 5 then
            dist = dist + readBits(DIST_EXTRA[d])
          elseif d > 3 then
            dist = dist + readBit()
          end

          if len <= dist then
            output:copy(writeOffset, output, writeOffset - dist, len)
            writeOffset = writeOffset + len
          else
            repeat
              local size = m_min(len, dist)
              output:copy(writeOffset, output, writeOffset - dist, size)
              writeOffset = writeOffset + size
              len = len - size
              dist = dist + size
            until len == 0
          end
        end
      until v == 0x100
    end
  until bfinal == 1

  if readOffsetBit > 0 then
    readOffsetBit = 0
    readOffset = readOffset + 1
  end

  local adler = input:readu32be(readOffset)
  assert(adler32(output, 0, output:length()) == adler, "adler-32 checksum mismatch")

  return writeOffset
end

local function zlib_deflate_store(input, _yield)
  local inputSize = input:length()
  local blockSize = 0x8000
  local blockCount = m_ceil(inputSize / blockSize)
  local header = Buffer.new(2)
  header:writeu8(0, 0x78)
  header:writeu8(1, 0x01)

  local blocks = {}
  local offset = 0
  for i = 1, blockCount do
    local remaining = inputSize - offset
    local size = m_min(remaining, blockSize)
    local out = Buffer.new(5 + size)
    local bfinal = (i == blockCount) and 1 or 0
    out:writeu8(0, bfinal)
    out:writeu16(1, size)
    out:writeu16(3, 0xFFFF - size)
    out:copy(5, input, offset, size)
    blocks[#blocks + 1] = out
    offset = offset + size
  end

  local adler = adler32(input, 0, inputSize)
  local footer = Buffer.new(4)
  footer:writeu32be(0, adler)

  local totalLen = header:length() + footer:length()
  for i = 1, #blocks do
    totalLen = totalLen + blocks[i]:length()
  end

  local output = Buffer.new(totalLen)
  local pos = 0
  output:copy(pos, header, 0, header:length())
  pos = pos + header:length()
  for i = 1, #blocks do
    output:copy(pos, blocks[i], 0, blocks[i]:length())
    pos = pos + blocks[i]:length()
  end
  output:copy(pos, footer, 0, footer:length())
  return output, totalLen
end

local function zlib_deflate(input, fast, _yield)
  local MAX_BITS = 15
  local LIT_LEN = {
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
    163, 195, 227, 258,
  }
  local LIT_EXTRA = { 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
  local DIST_OFF = {
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049,
    3073, 4097, 6145, 8193, 12289, 16385, 24577,
  }
  local DIST_EXTRA = { 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
  local FIXED_LIT = {}
  for i = 0, 143 do
    FIXED_LIT[#FIXED_LIT + 1] = 8
  end
  for i = 144, 255 do
    FIXED_LIT[#FIXED_LIT + 1] = 9
  end
  for i = 256, 279 do
    FIXED_LIT[#FIXED_LIT + 1] = 7
  end
  for i = 280, 287 do
    FIXED_LIT[#FIXED_LIT + 1] = 8
  end

  local WINDOW_LOOKAHEAD = 258
  local WINDOW_SEARCH = fast and 1024 or (0x8000 - WINDOW_LOOKAHEAD)
  local MAX_CHAIN_NODES = fast and 4096 or 50000
  local MAX_CHAIN_SEARCH = fast and 1 or 12
  local MAX_MATCH_LENGTH = fast and 16 or 96
  local DEFLATE_BLOCK_SIZE = 0x8000

  local function getStoreSize(blockSize)
    return m_ceil(blockSize / DEFLATE_BLOCK_SIZE) * 5 + blockSize
  end

  local cachedLitValues = {}
  local cachedLitExtraValues = {}
  local cachedLitExtraBits = {}
  for length = 3, 258 do
    local idx
    for i = #LIT_LEN, 1, -1 do
      if length >= LIT_LEN[i] then
        idx = i
        break
      end
    end
    cachedLitValues[length] = 0x100 + idx
    cachedLitExtraValues[length] = length - LIT_LEN[idx]
    cachedLitExtraBits[length] = LIT_EXTRA[idx - 8] or 0
  end

  local cachedDistIndices = {}
  for distance = 1, 1024 do
    local distIdx
    for i = #DIST_OFF, 1, -1 do
      if distance >= DIST_OFF[i] then
        distIdx = i
        break
      end
    end
    cachedDistIndices[distance] = distIdx
  end

  local function getDistIdx(distance)
    if distance < 1025 then
      return cachedDistIndices[distance]
    elseif distance < 1537 then
      return 21
    elseif distance < 2049 then
      return 22
    elseif distance < 3073 then
      return 23
    elseif distance < 4097 then
      return 24
    elseif distance < 6145 then
      return 25
    elseif distance < 8193 then
      return 26
    elseif distance < 12289 then
      return 27
    elseif distance < 16385 then
      return 28
    elseif distance < 24577 then
      return 29
    else
      return 30
    end
  end

  local fixedLitTable, fixedLitCodeValues, fixedLitCodeLengths = createHuffmanTable(FIXED_LIT)
  local fixedDistTable, fixedDistCodeValues, fixedDistCodeLengths = createHuffmanTable({
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
  })

  -- Precompute bit-reversed huffman codes (avoids writeHuffmanBits bit ops)
  local litRev = {}
  for i = 0, 287 do
    local v, bits, r = fixedLitCodeValues[i], fixedLitCodeLengths[i], 0
    for b = 0, bits - 1 do r = r * 2 + v % 2; v = m_floor(v / 2) end
    litRev[i] = r
  end
  local distRev = {}
  for i = 0, 29 do
    local v, bits, r = fixedDistCodeValues[i], fixedDistCodeLengths[i], 0
    for b = 0, bits - 1 do r = r * 2 + v % 2; v = m_floor(v / 2) end
    distRev[i] = r
  end

  local id = input.data  -- cache for inlined readu8/readu32 (avoids method calls in hot loop)
  local inputSize = input:length()
  local output = Buffer.new(getStoreSize(inputSize) + 6)

  output:writeu8(0, 0x78)
  output:writeu8(1, 0x01)

  local writeOffset = 2
  local writeOffsetBits = 0

  local function writeBits(n, width)
    output:writebits(writeOffset * 8 + writeOffsetBits, width, n)
    writeOffsetBits = writeOffsetBits + width
    local t = writeOffsetBits / 8; writeOffset = writeOffset + (t - t % 1)
    writeOffsetBits = writeOffsetBits % 8
  end

  local function writeLitOrLen(value)
    writeBits(litRev[value], fixedLitCodeLengths[value])
  end

  local function writeBackRef(distance, length)
    writeBits(litRev[cachedLitValues[length]], fixedLitCodeLengths[cachedLitValues[length]])
    if length > 10 then
      writeBits(cachedLitExtraValues[length], cachedLitExtraBits[length])
    end
    local distIdx = getDistIdx(distance)
    writeBits(distRev[distIdx - 1], fixedDistCodeLengths[distIdx - 1])
    if distIdx > 3 then
      writeBits(distance - DIST_OFF[distIdx], DIST_EXTRA[distIdx - 1])
    end
  end

  local function getBackRefSize(distance, length)
    local distIdx = getDistIdx(distance)
    return fixedLitCodeLengths[cachedLitValues[length]]
      + cachedLitExtraBits[length]
      + fixedDistCodeLengths[distIdx - 1]
      + (DIST_EXTRA[distIdx - 1] or 0)
  end

  local offsets = {}
  local nexts = {}
  local heads = {}
  local nodeCount = 0

  local function insertNode(offset, nextIndex)
    nodeCount = nodeCount + 1
    offsets[nodeCount] = offset
    nexts[nodeCount] = nextIndex
    return nodeCount
  end

  local function clearTables()
    for k in pairs(offsets) do offsets[k] = nil end
    for k in pairs(nexts) do nexts[k] = nil end
    for k in pairs(heads) do heads[k] = nil end
    nodeCount = 0
  end

  for startReadOffset = 0, inputSize - 1, DEFLATE_BLOCK_SIZE do
    local huffmanSizeBits = 0
    local nextBlockReadOffset = m_min(inputSize, startReadOffset + DEFLATE_BLOCK_SIZE)
    local readOffset = startReadOffset

    local tokens = {}
    while readOffset < nextBlockReadOffset - 3 do
      -- inlined readu32(readOffset) & 0xFFFFFF (24-bit hash for LZ77)
      local hash = ((id[readOffset+1] or 0) + (id[readOffset+2] or 0) * 256 + (id[readOffset+3] or 0) * 65536 + (id[readOffset+4] or 0) * 16777216) % 16777216
      local newNodeIndex = insertNode(readOffset, heads[hash] or 0)
      heads[hash] = newNodeIndex

      local bestLength = 0
      local bestOffset = -1

      local chainCount = 0
      local nodeIndex = nexts[newNodeIndex]
      while
        nodeIndex
        and (offsets[nodeIndex] or -m_huge) >= readOffset - WINDOW_SEARCH
        and chainCount < MAX_CHAIN_SEARCH
        and bestLength < MAX_MATCH_LENGTH
      do
        local searchLength = 3
        local searchOffset = offsets[nodeIndex]

        local exit = false
        local limit = m_min(nextBlockReadOffset, readOffset + WINDOW_LOOKAHEAD)
        if
          readOffset + bestLength < limit
          and (id[searchOffset + bestLength + 1] or 0) ~= (id[readOffset + bestLength + 1] or 0)  -- inlined readu8
        then
          exit = true
        end

        while
          not exit
          and searchLength < WINDOW_LOOKAHEAD
          and readOffset + searchLength < nextBlockReadOffset
          and (id[searchOffset + searchLength + 1] or 0) == (id[readOffset + searchLength + 1] or 0)
        do
          searchLength = searchLength + 1
        end
        if searchLength > bestLength then
          bestLength = searchLength
          bestOffset = searchOffset
          if bestLength >= WINDOW_LOOKAHEAD then
            break
          end
        end
        nodeIndex = nexts[nodeIndex]
        chainCount = chainCount + 1
      end

      if bestLength == 0 then
        local b = (id[readOffset + 1] or 0)  -- inlined readu8
        huffmanSizeBits = huffmanSizeBits + fixedLitCodeLengths[b]
        tokens[#tokens + 1] = { x = 0, y = b }
        readOffset = readOffset + 1
      else
        huffmanSizeBits = huffmanSizeBits + getBackRefSize(readOffset - bestOffset, bestLength)
        tokens[#tokens + 1] = { x = 1, y = readOffset - bestOffset, z = bestLength }
        local maxOffset = m_min(readOffset + bestLength - 1, nextBlockReadOffset - 4)
        for newOffset = readOffset + 1, maxOffset do
          local newHash = ((id[newOffset+1] or 0) + (id[newOffset+2] or 0) * 256 + (id[newOffset+3] or 0) * 65536 + (id[newOffset+4] or 0) * 16777216) % 16777216
          heads[newHash] = insertNode(newOffset, heads[newHash] or 0)
        end
        readOffset = readOffset + bestLength
      end
    end

    while readOffset < nextBlockReadOffset do
      local b = (id[readOffset + 1] or 0)
      huffmanSizeBits = huffmanSizeBits + fixedLitCodeLengths[b]
      tokens[#tokens + 1] = { x = 0, y = b }
      readOffset = readOffset + 1
    end

    huffmanSizeBits = huffmanSizeBits + fixedLitCodeLengths[0x100]
    tokens[#tokens + 1] = { x = 0, y = 0x100 }

    if nextBlockReadOffset == inputSize then
      writeBits(1, 1)
    else
      writeBits(0, 1)
    end

    local blockLength = nextBlockReadOffset - startReadOffset
    local fixedHuffmanSize = m_ceil(huffmanSizeBits / 8) + 1
    if fixedHuffmanSize < getStoreSize(blockLength) then
      writeBits(0x1, 2)
      for i = 1, #tokens do
        local token = tokens[i]
        if token.x == 0 then
          writeLitOrLen(token.y)
        else
          writeBackRef(token.y, token.z)
        end
      end
    else
      writeBits(0x0, 2)
      if writeOffsetBits > 0 then
        writeOffset = writeOffset + 1
        writeOffsetBits = 0
      end
      output:writeu16(writeOffset, blockLength)
      output:writeu16(writeOffset + 2, 0xFFFF - blockLength)  -- bxor(0xFFFF, x) = 0xFFFF - x
      output:copy(writeOffset + 4, input, startReadOffset, blockLength)
      writeOffset = writeOffset + 4 + blockLength
    end

    if nodeCount > MAX_CHAIN_NODES then
      clearTables()
    end
    if _yield then _yield() end  -- async yield point (per-operation, supports concurrent)
  end

  if writeOffsetBits > 0 then
    writeOffset = writeOffset + 1
  end

  local checksum = adler32(input, 0, inputSize)
  output:writeu32be(writeOffset, checksum)

  return output, writeOffset + 4
end

local COLOR_TYPE_CHANNELS = {
  [0] = 1,
  [2] = 3,
  [3] = 1,
  [4] = 2,
  [6] = 4,
}

local COLOR_TYPE_BIT_DEPTH = {
  [0] = { 1, 2, 4, 8, 16 },
  [2] = { 8, 16 },
  [3] = { 1, 2, 4, 8 },
  [4] = { 8, 16 },
  [6] = { 8, 16 },
}

local INTERLACE_ROW_START = { 0, 0, 4, 0, 2, 0, 1 }
local INTERLACE_COL_START = { 0, 4, 0, 2, 0, 1, 0 }
local INTERLACE_ROW_INCR = { 8, 8, 8, 4, 4, 2, 2 }
local INTERLACE_COL_INCR = { 8, 8, 4, 4, 2, 2, 1 }

local SIGNATURE = string.char(137, 80, 78, 71, 13, 10, 26, 10)

local function table_find(t, value)
  for i = 1, #t do
    if t[i] == value then
      return i
    end
  end
  return nil
end

local function read_IHDR(buf, chunk)
  assert(chunk.length == 13, "IHDR data must be 13 bytes")
  local offset = chunk.offset
  local width = buf:readu32be(offset)
  local height = buf:readu32be(offset + 4)
  local bitDepth = buf:readu8(offset + 8)
  local colorType = buf:readu8(offset + 9)
  local compression = buf:readu8(offset + 10)
  local filter = buf:readu8(offset + 11)
  local interlace = buf:readu8(offset + 12)

  assert(width > 0 and width <= 2 ^ 31 and height > 0 and height <= 2 ^ 31, "invalid dimensions")
  assert(compression == 0, "invalid compression method")
  assert(filter == 0, "invalid filter method")
  assert(interlace == 0 or interlace == 1, "invalid interlace method")

  local allowedBitDepth = COLOR_TYPE_BIT_DEPTH[colorType]
  assert(allowedBitDepth ~= nil, "invalid color type")
  assert(table_find(allowedBitDepth, bitDepth) ~= nil, "invalid bit depth")

  return {
    width = width,
    height = height,
    bitDepth = bitDepth,
    colorType = colorType,
    interlaced = interlace == 1,
  }
end

local function read_PLTE(buf, chunk, header)
  assert(chunk.length % 3 == 0, "malformed PLTE chunk")
  local count = chunk.length / 3
  assert(count > 0, "no entries in PLTE")
  assert(count <= 256, "too many entries in PLTE")
  assert(count <= 2 ^ header.bitDepth, "too many entries in PLTE for bit depth")

  local colors = {}
  local offset = chunk.offset
  for i = 1, count do
    colors[i] = {
      r = buf:readu8(offset),
      g = buf:readu8(offset + 1),
      b = buf:readu8(offset + 2),
      a = 255,
    }
    offset = offset + 3
  end

  return { colors = colors }
end

local function read_tRNS(buf, chunk, header, palette)
  local gray = -1
  local red = -1
  local green = -1
  local blue = -1

  local function readU16(offset, depth)
    local v = bor(lshift(buf:readu8(offset), 8), buf:readu8(offset + 1))
    return extract(v, 0, depth)
  end

  if header.colorType == 0 then
    assert(chunk.length == 2, "invalid tRNS length for color type")
    gray = readU16(chunk.offset, header.bitDepth)
  elseif header.colorType == 2 then
    assert(chunk.length == 6, "invalid tRNS length for color type")
    red = readU16(chunk.offset, header.bitDepth)
    green = readU16(chunk.offset + 2, header.bitDepth)
    blue = readU16(chunk.offset + 4, header.bitDepth)
  else
    local count = chunk.length
    assert(palette, "tRNS requires PLTE for color type")
    assert(count <= #palette.colors, "tRNS specified too many PLTE alphas")
    for i = 1, count do
      palette.colors[i].a = buf:readu8(chunk.offset + i - 1)
    end
  end

  return {
    gray = gray,
    red = red,
    green = green,
    blue = blue,
  }
end

local function decode_png(raw, options)
  local buf = Buffer.fromString(raw)
  local bufLen = buf:length()
  assert(bufLen >= 8, "not a PNG")
  assert(buf:readstring(0, 8) == SIGNATURE, "not a PNG")

  local chunks = {}
  local offset = 8
  local skipCRC = options ~= nil and options.allowIncorrectCRC == true

  repeat
    local dataLength = buf:readu32be(offset)
    local chunkType = buf:readstring(offset + 4, 4)
    assert(string.match(chunkType, "%a%a%a%a"), "invalid chunk type")

    local dataOffset = offset + 8
    local nextOffset = dataOffset + dataLength + 4
    assert(nextOffset <= bufLen, "EOF while reading chunk")

    local chunkCode = buf:readu32be(nextOffset - 4)
    local expectCode = crc32(buf, offset + 4, nextOffset - 5)
    assert(skipCRC or chunkCode == expectCode, "incorrect checksum in chunk")

    chunks[#chunks + 1] = {
      type = chunkType,
      offset = dataOffset,
      length = dataLength,
    }
    offset = nextOffset
  until offset >= bufLen
  assert(offset == bufLen, "trailing data in file")

  for i = 1, #chunks do
    local t = chunks[i].type
    if extract(string.byte(t, 1), 5, 1) == 0 then
      if t ~= "IHDR" and t ~= "IDAT" and t ~= "PLTE" and t ~= "IEND" then
        error("unhandled critical chunk " .. t)
      end
    end
  end

  local headerChunk = chunks[1]
  assert(headerChunk.type == "IHDR", "first chunk must be IHDR")
  for i = 2, #chunks do
    assert(chunks[i].type ~= "IHDR", "multiple IHDR chunks are not allowed")
  end
  local header = read_IHDR(buf, headerChunk)

  local dataChunkIndex0 = -1
  local dataChunkIndex1 = -1
  local compressedDataLength = 0
  for i = 1, #chunks do
    local chunk = chunks[i]
    if chunk.type == "IDAT" then
      if dataChunkIndex0 < 0 then
        dataChunkIndex0 = i
      else
        assert(i == dataChunkIndex1 + 1, "multiple IDAT chunks must be consecutive")
      end
      dataChunkIndex1 = i
      compressedDataLength = compressedDataLength + chunk.length
    end
  end
  assert(dataChunkIndex0 > 0, "no IDAT chunks")
  assert(compressedDataLength > 0, "no image data in IDAT chunks")

  local palette = nil
  local paletteChunkIndex = -1
  for i = 1, #chunks do
    local chunk = chunks[i]
    if chunk.type == "PLTE" then
      assert(not palette, "multiple PLTE chunks are not allowed")
      assert(i < dataChunkIndex0, "PLTE not allowed after IDAT chunks")
      assert(header.colorType ~= 0 and header.colorType ~= 4, "PLTE not allowed for color type")
      palette = read_PLTE(buf, chunk, header)
      paletteChunkIndex = i
    end
  end
  if header.colorType == 3 then
    assert(palette ~= nil, "color type requires a PLTE chunk")
  end

  local transparencyData = nil
  for i = 1, #chunks do
    local chunk = chunks[i]
    if chunk.type == "tRNS" then
      assert(transparencyData == nil, "multiple tRNS chunks are not allowed")
      assert(i < dataChunkIndex0, "tRNS not allowed after IDAT chunks")
      assert((not palette) or i > paletteChunkIndex, "tRNS must be after PLTE")
      assert(header.colorType ~= 4 and header.colorType ~= 6, "tRNS not allowed for color type")
      transparencyData = read_tRNS(buf, chunk, header, palette)
    end
  end

  local finalChunk = chunks[#chunks]
  assert(finalChunk.type == "IEND", "final chunk must be IEND")
  assert(finalChunk.length == 0, "IEND chunk must be empty")
  for i = 2, #chunks - 1 do
    assert(chunks[i].type ~= "IEND", "multiple IEND chunks are not allowed")
  end

  local compressedData = Buffer.new(compressedDataLength)
  local compressedOffset = 0
  for i = 1, #chunks do
    local chunk = chunks[i]
    if chunk.type == "IDAT" then
      compressedData:copy(compressedOffset, buf, chunk.offset, chunk.length)
      compressedOffset = compressedOffset + chunk.length
    end
  end

  local width = header.width
  local height = header.height
  local bitDepth = header.bitDepth
  local colorType = header.colorType
  local channels = COLOR_TYPE_CHANNELS[colorType]

  local rawSize = 0
  if not header.interlaced then
    rawSize = height * (m_ceil(width * channels * bitDepth / 8) + 1)
  else
    for i = 1, 7 do
      local w = m_ceil((width - INTERLACE_COL_START[i]) / INTERLACE_COL_INCR[i])
      local h = m_ceil((height - INTERLACE_ROW_START[i]) / INTERLACE_ROW_INCR[i])
      if w > 0 and h > 0 then
        local scanlineSize = m_ceil(w * channels * bitDepth / 8) + 1
        rawSize = rawSize + h * scanlineSize
      end
    end
  end

  local paletteColors = nil
  if palette then
    paletteColors = palette.colors
  end

  local rescale = nil
  if colorType ~= 3 and bitDepth < 8 then
    rescale = 0xFF / (2 ^ bitDepth - 1)
  end

  local bpp = m_ceil(channels * bitDepth / 8)
  local defaultAlpha = 2 ^ bitDepth - 1

  local idx = 0
  local working = Buffer.new(rawSize)
  local inflatedSize = zlib_inflate(compressedData, working)
  assert(inflatedSize == rawSize, "decompressed data size mismatch")

  local rgba8 = Buffer.new(width * height * 4)

  local alphaGray = transparencyData and transparencyData.gray or -1
  local alphaRed = transparencyData and transparencyData.red or -1
  local alphaGreen = transparencyData and transparencyData.green or -1
  local alphaBlue = transparencyData and transparencyData.blue or -1

  local function pass(sx, sy, dx, dy)
    local w = m_ceil((width - sx) / dx)
    local h = m_ceil((height - sy) / dy)
    if w < 1 or h < 1 then
      return
    end

    local scanlineSize = m_ceil(w * channels * bitDepth / 8)
    local newIdx = idx

    for y = 1, h do
      local rowFilter = working:readu8(idx)
      idx = idx + 1

      if rowFilter == 0 or (rowFilter == 2 and y == 1) then
        idx = idx + scanlineSize
      elseif rowFilter == 1 then
        for x = 1, scanlineSize do
          local sub = (x <= bpp) and 0 or working:readu8(idx - bpp)
          local value = (working:readu8(idx) + sub) % 256
          working:writeu8(idx, value)
          idx = idx + 1
        end
      elseif rowFilter == 2 then
        for _ = 1, scanlineSize do
          local up = working:readu8(idx - scanlineSize - 1)
          local value = (working:readu8(idx) + up % 256)
          working:writeu8(idx, value)
          idx = idx + 1
        end
      elseif rowFilter == 3 then
        for x = 1, scanlineSize do
          local sub = (x <= bpp) and 0 or working:readu8(idx - bpp)
          local up = (y == 1) and 0 or working:readu8(idx - scanlineSize - 1)
          local value = (working:readu8(idx) + rshift(sub + up, 1) % 256)
          working:writeu8(idx, value)
          idx = idx + 1
        end
      elseif rowFilter == 4 then
        for x = 1, scanlineSize do
          local sub = (x <= bpp) and 0 or working:readu8(idx - bpp)
          local up = (y == 1) and 0 or working:readu8(idx - scanlineSize - 1)
          local corner = (x <= bpp or y == 1) and 0 or working:readu8(idx - scanlineSize - bpp - 1)
          local p0 = m_abs(up - corner)
          local p1 = m_abs(sub - corner)
          local p2 = m_abs(sub + up - 2 * corner)
          local paeth
          if p0 <= p1 and p0 <= p2 then
            paeth = sub
          elseif p1 <= p2 then
            paeth = up
          else
            paeth = corner
          end
          local value = (working:readu8(idx) + paeth % 256)
          working:writeu8(idx, value)
          idx = idx + 1
        end
      else
        error("invalid row filter")
      end
    end

    local bit = 8
    local wd = working.data  -- inline data access
    local function readValue()
      local b = wd[newIdx + 1] or 0
      if bitDepth < 8 then
        local shift = bit - bitDepth
        local t = b / (2 ^ shift); b = (t - t % 1) % (2 ^ bitDepth)  -- extract bit field
        bit = bit - bitDepth
        if bit == 0 then
          bit = 8
          newIdx = newIdx + 1
        end
      elseif bitDepth == 8 then
        newIdx = newIdx + 1
      else
        b = b * 256 + (wd[newIdx + 2] or 0)  -- inlined bor+lshift+readu8
        newIdx = newIdx + 2
      end
      return b
    end

    for y = 1, h do
      newIdx = newIdx + 1
      if bit < 8 then
        bit = 8
        newIdx = newIdx + 1
      end

      for x = 1, w do
        local r, g, b, a

        if colorType == 0 then
          local gray = readValue()
          r = gray
          g = gray
          b = gray
          a = (gray == alphaGray) and 0 or defaultAlpha
        elseif colorType == 2 then
          r = readValue()
          g = readValue()
          b = readValue()
          a = (r == alphaRed and g == alphaGreen and b == alphaBlue) and 0 or defaultAlpha
        elseif colorType == 3 then
          local color = paletteColors[readValue() + 1]
          r = color.r
          g = color.g
          b = color.b
          a = color.a
        elseif colorType == 4 then
          local gray = readValue()
          r = gray
          g = gray
          b = gray
          a = readValue()
        elseif colorType == 6 then
          r = readValue()
          g = readValue()
          b = readValue()
          a = readValue()
        end

        local py = sy + (y - 1) * dy
        local px = sx + (x - 1) * dx
        local i = (py * width + px) * 4

        if rescale then
          r = round(r * rescale)
          g = round(g * rescale)
          b = round(b * rescale)
          a = round(a * rescale)
        elseif bitDepth == 16 then
          r = rshift(r, 8)
          g = rshift(g, 8)
          b = rshift(b, 8)
          a = rshift(a, 8)
        end

        rgba8:writeu32(i, bor(lshift(a, 24), bor(lshift(b, 16), bor(lshift(g, 8), r))))
      end
    end
  end

  if not header.interlaced then
    pass(0, 0, 1, 1)
  else
    for i = 1, 7 do
      pass(INTERLACE_COL_START[i], INTERLACE_ROW_START[i], INTERLACE_COL_INCR[i], INTERLACE_ROW_INCR[i])
    end
  end

  return {
    width = width,
    height = height,
    pixels = rgba8,
  }
end

local function encode_png(pixels, options, fast, _yield)
  local width = options.width
  local height = options.height
  local dataSize = pixels:length()
  local expectSize = width * height * 4
  assert(dataSize == expectSize, "pixel data size mismatch")

  local imageDataRowSize = width * 4 + 1
  local imageData = Buffer.new(height * imageDataRowSize)
  for row = 0, height - 1 do
    local sourceOffset = row * width * 4
    local targetOffset = row * imageDataRowSize
    imageData:writeu8(targetOffset, 0)
    imageData:copy(targetOffset + 1, pixels, sourceOffset, 4 * width)
  end
  local imageDataDeflated, imageDataDeflatedLength
  if fast == "store" then
    imageDataDeflated, imageDataDeflatedLength = zlib_deflate_store(imageData, _yield)
  else
    imageDataDeflated, imageDataDeflatedLength = zlib_deflate(imageData, fast, _yield)
  end
  local outputLength = 8 + 25 + (8 + imageDataDeflatedLength + 4) + 12
  local output = Buffer.new(outputLength)
  output:writestring(0, SIGNATURE)

  output:writeu32be(8, 13)
  output:writestring(12, "IHDR")
  output:writeu32be(16, width)
  output:writeu32be(20, height)
  output:writeu8(24, 8)
  output:writeu8(25, 6)
  output:writeu8(26, 0)
  output:writeu8(27, 0)
  output:writeu8(28, 0)
  output:writeu32be(29, crc32(output, 12, 28))

  output:writeu32be(33, imageDataDeflatedLength)
  output:writestring(37, "IDAT")
  output:copy(41, imageDataDeflated, 0, imageDataDeflatedLength)
  local x = 41 + imageDataDeflatedLength
  output:writeu32be(x, crc32(output, 37, x - 1))

  output:writeu32(x + 4, 0)
  output:writestring(x + 8, "IEND")
  output:writeu32be(x + 12, crc32(output, x + 8, x + 11))
    return output
end

local function rgba_to_bgra(buf)
  local out = Buffer.new(buf:length())
  local i, n = 0, buf:length()
  while i < n do
    out:writeBGRA(i, buf:readRGBA(i))
    i = i + 4
  end
  return out
end

local function bgra_to_rgba(buf)
  local out = Buffer.new(buf:length())
  local i, n = 0, buf:length()
  while i < n do
    out:writeRGBA(i, buf:readBGRA(i))
    i = i + 4
  end
  return out
end

local PNG = {}
PNG.__index = PNG

function PNG.new()
  local self = setmetatable({}, PNG)
  self.width = 0
  self.height = 0
  self.pixels = nil
  return self
end

function PNG:load(data)
  local raw = data
  if type(data) == "string" and fileExists(data) then
    local f = fileOpen(data)
    if f then
      raw = fileRead(f, fileGetSize(f))
      fileClose(f)
    end
  end
  assert(type(raw) == "string", "invalid PNG data")

  local decoded = decode_png(raw)
  self.width = decoded.width
  self.height = decoded.height
  local bgra = rgba_to_bgra(decoded.pixels)

  local px = PixelData:new()
  px.width = self.width
  px.height = self.height
  px.depth = 32
  px.rowAlignment = 1
  px.dataType = "raw"
  px.data = bgra:toString()
  self.pixels = px
  return self
end

function PNG:save(fileName, fast)
    assert(self.pixels, 'no pixel data')
    local width = self.width > 0 and self.width or self.pixels.width
    local height = self.height > 0 and self.height or self.pixels.height
    assert(width and height, 'missing dimensions')
    local raw = self.pixels.data
    local buf = Buffer.fromString(raw)
    local rgba = bgra_to_rgba(buf)
    local encoded = encode_png(rgba, { width = width, height = height }, fast, self._yield)
    local out = encoded:toString()
    if fileName then
        if fileExists(fileName) then fileDelete(fileName) end
        local f = fileCreate(fileName)
        if f then fileWrite(f, out); fileClose(f) end
    end
    return out
end

-- ====== Timing & Async ======

function PNG:saveTimed(fileName, fast)
    local t = os.clock()
    local result = self:save(fileName, fast)
    local dt = os.clock() - t
    local w = self.width > 0 and self.width or (self.pixels and self.pixels.width or 0)
    local h = self.height > 0 and self.height or (self.pixels and self.pixels.height or 0)
    print(string.format('[PNG:save] %.2fs  %dx%d  %d bytes', dt, w, h, result and #result or 0))
    return result
end

function PNG:saveAsync(fileName, fast)
    local s = self
    return coroutine.create(function()
        s._yield = function() coroutine.yield() end
        local result = PNG.save(s, fileName, fast)
        s._yield = nil
        return result
    end)
end

-- ====== TXDIO 注册 ======
if TXDIO then
    TXDIO.register("imageDecoder", "png_binary", "string", function(source, tex)
        local data = source
        if fileExists(source) then
            local f = fileOpen(source)
            if f then data = fileRead(f, fileGetSize(f)); fileClose(f) end
        end
        if data:sub(1, 8) ~= "\137PNG\r\n\26\n" then return false end
        local png = PNG:new(); png:load(data)
        return TXDIO.setTextureFromPixelData(tex, png.pixels)
    end)
    TXDIO.register("imageDecoder", "png", "table", function(source, tex)
        if getmetatable(source) ~= PNG then return false end
        return TXDIO.setTextureFromPixelData(tex, source.pixels)
    end)
    TXDIO.register("imageEncoder", "png", "png", function(tex, format)
        local isDXT = tex.struct.textureFormat == EnumD3DFormat.DXT1
            or tex.struct.textureFormat == EnumD3DFormat.DXT3
            or tex.struct.textureFormat == EnumD3DFormat.DXT5
        if isDXT then
            local dds = DDSTexture:new()
            if not dds:convertFromTXD(tex) then return nil end
            local bgra = dds:decodeToBGRA()
            if not bgra then return nil end
            local px = PixelData:new()
            px.width = tex.struct.width; px.height = tex.struct.height
            px.depth = 32; px.rowAlignment = 1; px.dataType = "raw"; px.data = bgra
            local png = PNG:new(); png.width = px.width; png.height = px.height; png.pixels = px
            return png:save(nil, true)
        end
        local bmp = BMPTexture:new()
        if not bmp:convertFromTXD(tex) then return nil end
        local png = PNG:new(); png.pixels = bmp.bmp.pixels
        return png:save(nil, true)
    end)
end

return PNG
