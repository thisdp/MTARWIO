-- base.lua — Section / Struct / Extension 基类
-- 原型链继承，配合 Schema 引擎生成 read/write/getSize
-- 依赖: Reader, Writer, Engine, SectionRegistry（由 meta.xml 加载顺序保证）

-- ====== Section ======

Section = {}
Section.__index = Section
Section.typeID = nil
Section._isStruct = false

function Section:new()
    local obj = setmetatable({}, self)
    obj.type = self.typeID
    obj.size = 0
    obj.version = 0
    obj.parent = nil
    return obj
end

-- 创建子类（继承当前 Section）
function Section:extend(overrides)
    local cls = setmetatable(overrides or {}, { __index = self })
    cls.__index = cls
    return cls
end

-- 声明式定义：给定 fields 表，自动生成 read/write/getSize
-- 用法: Class = Section:define({...})          -- typeID 从父类继承
--       Class = Section:define(0x06, {...})    -- 显式指定 typeID
function Section:define(typeID, fields)
    -- 兼容旧语法: 如果第一个参数是 table，则是 fields
    if type(typeID) == "table" then
        fields = typeID
        typeID = nil
    end
    local cls = self:extend()
    if typeID then cls.typeID = typeID end

    cls._fields = fields
    cls._readBody = Engine.makeReader(fields)
    cls._writeBody = Engine.makeWriter(fields)
    cls._calcSize = Engine.makeSizeCalc(fields)
    -- 仅注册有唯一 typeID 的 Section (跳过 Struct 0x01 / Extension 0x03)
    if cls.typeID ~= 0x01 and cls.typeID ~= 0x03 then
        SectionRegistry.register(cls)
    end

    -- 实例方法：读取 body（头部已由 SectionRegistry.read 读取）
    function cls:read(r)
        self:_readBody(r)
    end

    -- 实例方法：完整写入（头部 + body）
    function cls:write(w)
        self:getSize()
        w:u32(self.type or self.typeID)
        w:u32(self.size)
        w:u32(self.version)
        self:_writeBody(w)
        if self._trailingData then w:raw(self._trailingData) end
    end

    -- 实例方法：计算总大小（头部12 + body）
    function cls:getSize()
        local bodySize = self:_calcSize()
        local trailingSize = self._trailingData and #self._trailingData or 0
        self.size = bodySize + trailingSize
        return bodySize + trailingSize + 12
    end

    return cls
end

-- 默认实例 read（空操作，由 Section:define() 或子类覆盖）
function Section:read(r)
end

-- 静态 readFrom: 从流中读取 header + body，返回新实例
-- 用法: local obj = ClumpStruct:readFrom(r, parent)
function Section:readFrom(r, parent)
    return Engine._readSingleStruct(r, self, parent)
end

-- 默认 getSize: 返回 header(12) + body(0), 子类可覆盖
function Section:getSize()
    return 12
end

-- 默认 write: 写 header 即可（body 为空）
function Section:write(w)
    self:getSize()
    w:u32(self.type or self.typeID)
    w:u32(self.size or 0)
    w:u32(self.version or 0)
end

-- 获取 body 大小（不含头部）
function Section:getBodySize()
    return self.size
end

-- 版本转换（默认仅改版本号）
function Section:convert(targetVersion)
    self.version = targetVersion
end

-- ====== Struct (typeID = 0x01) ======

Struct = Section:extend({ typeID = 0x01, _isStruct = true })

function Struct:init(version)
    self.type = Struct.typeID
    self.version = version
    self.size = 0
    return self
end

SectionRegistry.register(Struct)

-- ====== Extension (typeID = 0x03) ======

Extension = Section:extend({ typeID = 0x03 })

function Extension:init(version)
    self.type = Extension.typeID
    self.version = version
    self.size = 0
    return self
end

SectionRegistry.register(Extension)

-- ====== String (typeID = 0x02) ======

String = Section:extend({ typeID = 0x02 })

function String:new()
    local obj = setmetatable({}, String)
    obj.type = String.typeID
    obj.size = 0
    obj.version = 0
    obj.string = ""
    obj.parent = nil
    return obj
end

function String:read(r)
    -- 头部已读，size 已知，直接读字符串体
    self.string = r:str(self.size)
end

function String:write(w)
    self.size = #self.string
    w:u32(self.type)
    w:u32(self.size)
    w:u32(self.version)
    w:str(self.string, self.size)
end

function String:getSize()
    self.size = #self.string
    return self.size + 12
end

SectionRegistry.register(String)

-- ====== RawStruct — 非 RW 格式的纯字段结构体 (无 Section header) ======
-- 用法: BMPHeader = RawStruct:define({ { name = "fileType", type = u16 }, ... })
-- read/write 只处理 body 字段，不读写 12 字节 Section 头

RawStruct = {}
RawStruct.__index = RawStruct

function RawStruct:define(fields)
    local cls = { _fields = fields }
    cls._readBody = Engine.makeReader(fields)
    cls._writeBody = Engine.makeWriter(fields)
    cls._calcSize = Engine.makeSizeCalc(fields)

    -- 从类型标记的 .default 生成默认值
    -- 优先级: f.default > f.value > f.type.default
    local defaults = {}
    for _, f in ipairs(fields) do
        if f.default ~= nil then
            defaults[f.name] = f.default
        elseif f.value ~= nil then
            defaults[f.name] = f.value
        elseif f.type.default ~= nil then
            local d = f.type.default
            defaults[f.name] = (type(d) == "function") and d() or d
        end
    end

    function cls:new()
        local obj = setmetatable({}, cls)
        for k, v in pairs(defaults) do obj[k] = v end
        return obj
    end

    function cls:read(r)
        self:_readBody(r)
    end

    function cls:write(w)
        self:_writeBody(w)
    end

    function cls:getSize()
        return self:_calcSize()
    end

    cls.__index = cls
    return cls
end

-- ====== Dump 基础设施 ======
-- 每个 Section 都可以调用 :dump(out, lvl, limits) 将自身结构化为可读文本
-- limits: { maxVerts=N, maxFaces=N, ... } 控制截断, nil 为完整输出

local _D_INDENT = "  "

local function _dIndent(lvl)
    return string.rep(_D_INDENT, lvl)
end

local function _dFmtVec(t)
    if not t then return "nil" end
    local p = {}
    for i = 1, #t do p[i] = string.format("%.6f", t[i]) end
    return "(" .. table.concat(p, ", ") .. ")"
end

local function _dFmtRGBA(t)
    if not t then return "nil" end
    return string.format("(R=%d G=%d B=%d A=%d)", t[1] or 0, t[2] or 0, t[3] or 0, t[4] or 0)
end

local function _dFmtMat3x3(t)
    if not t then return "nil" end
    local lines = {}
    for row = 1, 3 do
        local r = t[row] or {}
        lines[row] = _dIndent(1) .. string.format("row%d: (%.6f, %.6f, %.6f)", row, r[1] or 0, r[2] or 0, r[3] or 0)
    end
    return "\n" .. table.concat(lines, "\n")
end

local function _dFmtInt(v)
    if v == math.floor(v) and v >= -2147483648 and v <= 4294967295 then
        if v >= 0 then return string.format("%.0f (0x%08X)", v, v)
        else return string.format("%d (0x%08X)", v, v) end
    end
    return string.format("%.6f (0x%08X)", v, v)
end

function _dDumpField(out, lvl, name, val, ftype, limits)
    limits = limits or {}
    local indent = _dIndent(lvl)
    if val == nil then return end

    if type(val) == "table" and val.type and val.size then
        -- 子 Section: 递归 dump
        if val.dump then
            val:dump(out, lvl, limits)
        else
            out[#out+1] = indent .. name .. ": <section 0x" .. string.format("%08X", val.type) .. ">"
        end

    elseif type(val) == "table" and ftype and ftype.marker == "mat3x3" then
        out[#out+1] = indent .. string.format("%-22s =%s", name, _dFmtMat3x3(val))

    elseif type(val) == "table" and #val > 0 and type(val[1]) == "table" then
        -- 向量/结构体数组
        local maxN = limits.maxVerts or 10
        local isVec = val[1] and #val[1] <= 4 and type(val[1][1]) == "number"
        if isVec then
            local fmtFn = (#val[1] == 3 and _dFmtVec or #val[1] == 4 and _dFmtRGBA or _dFmtVec)
            out[#out+1] = indent .. string.format("%-22s = %d total", name, #val)
            local n = math.min(#val, maxN)
            for i = 1, n do
                out[#out+1] = indent .. _D_INDENT .. string.format("[%d] %s", i, fmtFn(val[i]))
            end
            if #val > maxN then
                out[#out+1] = indent .. _D_INDENT .. string.format("... +%d more", #val - maxN)
            end
        else
            out[#out+1] = indent .. string.format("%-22s = [%d items]", name, #val)
            local n = math.min(#val, maxN)
            for i = 1, n do
                out[#out+1] = indent .. _D_INDENT .. string.format("[%d]", i)
                if type(val[i]) == "table" then
                    for k, v in pairs(val[i]) do
                        if k ~= "parent" and k ~= "@" then
                            out[#out+1] = indent .. _D_INDENT .. _D_INDENT .. string.format("%s = %s", tostring(k), tostring(v))
                        end
                    end
                end
            end
            if #val > maxN then
                out[#out+1] = indent .. _D_INDENT .. string.format("... +%d more", #val - maxN)
            end
        end

    elseif type(val) == "table" and #val > 0 then
        -- 标量数组
        local maxN = limits.maxFaces or 10
        local items = {}
        for i = 1, math.min(#val, maxN) do items[i] = tostring(val[i]) end
        local suffix = #val > maxN and (" ... +" .. (#val - maxN) .. " more") or ""
        out[#out+1] = indent .. string.format("%-22s = [%s%s]", name, table.concat(items, ", "), suffix)

    elseif type(val) == "table" then
        out[#out+1] = indent .. string.format("%-22s = {}", name)
        for k, v in pairs(val) do
            if k ~= "parent" and k ~= "@" then
                if type(v) == "number" then
                    out[#out+1] = indent .. _D_INDENT .. string.format("%s = %s", tostring(k), _dFmtInt(v))
                elseif type(v) ~= "table" then
                    out[#out+1] = indent .. _D_INDENT .. string.format("%s = %s", tostring(k), tostring(v))
                end
            end
        end

    elseif type(val) == "number" then
        out[#out+1] = indent .. string.format("%-22s = %s", name, _dFmtInt(val))
    elseif type(val) == "boolean" then
        out[#out+1] = indent .. string.format("%-22s = %s", name, tostring(val))
    elseif type(val) == "string" and #val <= 64 then
        local display = val:gsub("[%c]", "?")
        out[#out+1] = indent .. string.format("%-22s = \"%s\"", name, display)
    elseif type(val) == "string" then
        out[#out+1] = indent .. string.format("%-22s = \"%s...\" (%d bytes)", name, val:sub(1, 32):gsub("[%c]", "?"), #val)
    end
end

-- 默认 Section dump: 仅打印 header (type, @offset, size, version)
function Section:dump(out, lvl, limits)
    lvl = lvl or 0
    local indent = _dIndent(lvl)
    local typeName = self._typeName or string.format("0x%08X", self.type or 0)
    local at = self["@"] and string.format(" @0x%X", self["@"]) or ""
    out[#out+1] = indent .. "--- " .. typeName .. at .. string.format("  size=%d", self.size or 0) .. " ---"
    -- 未知类型: 展示原始二进制数据
    if self.rawData and #self.rawData > 0 then
        local maxShow = limits and limits.maxRawBytes or 64
        local hex = {}
        local n = math.min(#self.rawData, maxShow)
        for i = 1, n do
            hex[i] = string.format("%02X", self.rawData:byte(i))
        end
        local suffix = #self.rawData > maxShow and (" ... +" .. (#self.rawData - maxShow) .. " bytes") or ""
        out[#out+1] = indent .. "  " .. string.format("raw: %d bytes", #self.rawData)
        out[#out+1] = indent .. "  " .. table.concat(hex, " ") .. suffix
    end
end

-- Struct dump 同上
function Struct:dump(out, lvl, limits)
    Section.dump(self, out, lvl, limits)
end

-- Extension dump: 遍历 plugins 数组
Extension._typeName = "Extension"
function Extension:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    Section.dump(self, out, lvl, limits)
    if self.plugins and #self.plugins > 0 then
        for _, plugin in ipairs(self.plugins) do
            if plugin.dump then
                plugin:dump(out, lvl + 1, limits)
            else
                local indent = string.rep("  ", lvl + 1)
                out[#out+1] = indent .. "[plugin] 0x" .. string.format("%08X", plugin.type or 0)
            end
        end
    end
end

-- 导出辅助函数供各模块 dump 使用
Section.fmtVec = _dFmtVec
Section.fmtRGBA = _dFmtRGBA
Section.fmtMat3x3 = _dFmtMat3x3
Section.fmtInt = _dFmtInt
Section.dumpField = _dDumpField
