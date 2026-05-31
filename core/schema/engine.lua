-- engine.lua — Schema 引擎
-- 根据字段定义自动生成 read / write / getSize 方法
-- Lua 5.1 兼容，使用全局变量（无 require）

Engine = {}

-- === 标量读/写调度表 ===
-- 每个 marker 对应 Reader/Writer 的方法名

local scalarReaders = {
    u8  = "u8",  u16 = "u16", u32 = "u32",
    i8  = "i8",  i16 = "i16", i32 = "i32",
    f32 = "f32",
    rgba   = "rgba",   bool32 = "bool32", bool8 = "bool8",
    vec2   = "vec2",   vec3   = "vec3",   vec4   = "vec4",
    mat3x3 = "mat3x3", mat4x4 = "mat4x4",
}

local scalarWriters = {
    u8  = "u8",  u16 = "u16", u32 = "u32",
    i8  = "i8",  i16 = "i16", i32 = "i32",
    f32 = "f32",
    rgba   = "rgba",   bool32 = "bool32", bool8 = "bool8",
    vec2   = "vec2",   vec3   = "vec3",   vec4   = "vec4",
    mat3x3 = "mat3x3", mat4x4 = "mat4x4",
}

-- === 条件检查 ===

function Engine.checkCond(self, cond)
    if not cond then return true end
    for i = 1, #cond do
        local c = cond[i]
        -- c = {pathStr, opStr, value}
        local path, op, val = c[1], c[2], c[3]
        local actual = Engine.resolvePath(self, path)
        if     op == "==" and actual ~= val then return false
        elseif op == "~=" and actual == val then return false
        elseif op == "<"  and actual >= val then return false
        elseif op == ">"  and actual <= val then return false
        elseif op == "<=" and actual >  val then return false
        elseif op == ">=" and actual <  val then return false
        end
    end
    return true
end

-- 路径解析: "parent.struct.vertexCount" → 值
function Engine.resolvePath(self, path)
    if type(path) ~= "string" then return path end
    local obj = self
    for part in path:gmatch("[^.]+") do
        if obj == nil then return nil end
        obj = obj[part]
    end
    return obj
end

-- 解析 byteSize (支持数值、路径字符串、函数)
function Engine._resolveByteSize(self, bs)
    if type(bs) == "function" then
        return bs(self)
    elseif type(bs) == "string" then
        return Engine.resolvePath(self, bs) or 0
    elseif bs ~= nil then
        return bs
    end
    return self.size or 0
end

-- === 字段解析 ===
-- 返回解析后的字段描述表: { kind, _name, ... }

function Engine.parseField(f)
    local ftype = f.type

    -- sync 字段: 自动从源数组长度派生值
    if f.sync then
        return { kind = "sync", marker = ftype.marker, byteSize = ftype.byteSize, sync = f.sync }

    -- 固定值字段: 始终写入固定值
    elseif f.value ~= nil then
        return { kind = "fixed", marker = ftype.marker, byteSize = ftype.byteSize, value = f.value }

    -- 位标志字段: 自动展开/组装
    elseif f.bits then
        return { kind = "bits", marker = ftype.marker, byteSize = ftype.byteSize, bits = f.bits }

    -- === 新语法数组: 显式 count 属性 ===
    --   { name = "faces", type = Face, count = "faceCount" }
    --   { name = "frameInfo", type = FrameInfo, count = "frameCount" }
    elseif f.count ~= nil then
        return { kind = "array", element = ftype, count = f.count, cond = f.cond, raw = f.raw }

    -- === 旧语法兼容: type = {elemType, count, ...cond...} ===
    elseif type(ftype) == "table" and #ftype >= 2 and not ftype.marker and not ftype.typeID
           and not ftype._catalogue and not ftype.__IS_EXT_LIST then
        local elemType = ftype[1]
        local count = ftype[2]
        local conds = {}
        for i = 3, #ftype do
            if type(ftype[i]) == "table" and type(ftype[i][2]) == "string" then
                conds[#conds + 1] = ftype[i]
            end
        end
        local finalCond = #conds > 0 and conds or f.cond
        if count == 1 and #conds > 0 then
            return { kind = "struct", class = elemType, cond = finalCond, optional = f.optional }
        elseif count == 1 then
            return { kind = "struct", class = elemType, cond = f.cond, optional = f.optional }
        else
            return { kind = "array", element = elemType, count = count, cond = finalCond, raw = f.raw }
        end

    -- 扩展列表标记
    elseif type(ftype) == "table" and ftype.__IS_EXT_LIST then
        return { kind = "extlist", registry = ftype._registry, cond = f.cond }

    -- catalogue 分发表: type = Effect2D.Effects
    elseif type(ftype) == "table" and ftype._catalogue then
        return { kind = "dispatch", by = ftype._dispatchBy, map = ftype, sizeFrom = ftype._sizeFrom, cond = f.cond }

    -- 标量/复合标记类型 (u32, f32, rgba, vec3, ...)
    elseif ftype.marker then
        local bs = f.byteSize or ftype.byteSize
        return { kind = "scalar", marker = ftype.marker, byteSize = bs, cond = f.cond }

    -- 结构体类 (Section 子类，有 typeID)
    elseif type(ftype) == "table" and ftype.typeID then
        return { kind = "struct", class = ftype, cond = f.cond, optional = f.optional }

    -- RawStruct 类 (无 Section 头)
    elseif type(ftype) == "table" and ftype._fields then
        return { kind = "rawstruct", class = ftype, cond = f.cond }

    else
        error("Unknown field type for '" .. (f.name or "?") .. "': " .. type(ftype))
    end
end

-- === 解析数组长度 ===

function Engine.resolveCount(self, countSpec)
    if type(countSpec) == "number" then
        return countSpec
    elseif type(countSpec) == "string" then
        return Engine.resolvePath(self, countSpec) or 0
    elseif type(countSpec) == "function" then
        return countSpec(self)
    end
    return 0
end

-- === 读取结构体字段 ===
function Engine._readStructField(self, r, p)
    local obj = Engine._readSingleStruct(r, p.class, self)
    self[p._name] = obj
end

-- 从流中读取单个结构体（内部使用，返回对象不存储）
function Engine._readSingleStruct(r, class, parent)
    local typeID = r:u32()
    local size = r:u32()
    local version = r:u32()

    local Class
    if typeID == Struct.typeID or typeID == Extension.typeID then
        Class = class
    else
        Class = SectionRegistry.byID[typeID] or class
    end

    if not Class then
        error("Unknown section type: 0x" .. string.format("%08X", typeID))
    end

    local obj = Class:new()
    obj["@"] = r.pos - 12  -- 在二进制流中的起始偏移
    obj.type = typeID
    obj.size = size
    obj.version = version
    if parent then obj.parent = parent end  -- 在 read 之前设置，供路径引用
    local expectedEnd = r.pos + size
    local ok, err = pcall(obj.read, obj, r)
    if r.pos < expectedEnd then
        local gap = expectedEnd - r.pos
        io.stderr:write(string.format("[RW] Trailing data %d bytes in struct 0x%08X at 0x%X\n",
            gap, typeID, r.pos))
        obj._trailingData = r:raw(gap)
        r.pos = expectedEnd
    elseif r.pos > expectedEnd then
        io.stderr:write(string.format("[RW] Overshoot %d bytes in struct 0x%08X at 0x%X\n",
            r.pos - expectedEnd, typeID, r.pos))
        r.pos = expectedEnd
    end
    if not ok then error(err) end  -- 重新抛出
    return obj
end

-- === 从流中读取一个结构体（委托给 SectionRegistry） ===

function Engine.readStruct(r)
    return SectionRegistry.read(r)
end

-- ====== READ ======

function Engine.makeReader(fields)
    local parsed = {}
    for _, f in ipairs(fields) do
        local p = Engine.parseField(f)
        p._name = f.name
        parsed[#parsed + 1] = p
    end
    return function(self, r)
        Engine._readParsedFields(self, r, parsed)
    end
end

function Engine._readParsedFields(self, r, parsed)
    for _, p in ipairs(parsed) do
        if Engine.checkCond(self, p.cond) then
            Engine._readField(self, r, p)
        end
    end
end

function Engine._readField(self, r, p)
    if p.kind == "scalar" then
        local method = scalarReaders[p.marker]
        if method then
            self[p._name] = r[method](r)
        elseif p.marker == "str" then
            self[p._name] = r:str(Engine._resolveByteSize(self, p.byteSize))
        elseif p.marker == "bytes" then
            self[p._name] = r:raw(Engine._resolveByteSize(self, p.byteSize))
        end

    elseif p.kind == "sync" then
        -- 读取并存储（供后续数组使用 count 值），写入时自动重新计算
        local method = scalarReaders[p.marker]
        if method then
            self[p._name] = r[method](r)
        end

    elseif p.kind == "fixed" then
        r:skip(p.byteSize)

    elseif p.kind == "bits" then
        local method = scalarReaders[p.marker]
        local raw = r[method](r)
        self[p._name] = raw
        for _, bitDef in ipairs(p.bits) do
            local bitName = bitDef[1]
            local bitPos = bitDef[2]
            local bitLen = bitDef[3] or 1
            local val = bExtract(raw, bitPos, bitLen)
            if bitLen == 1 then
                self[bitName] = (val == 1)  -- 转为 boolean 供条件检查
            else
                self[bitName] = val          -- 保持数字 (如 textureCount)
            end
        end

    elseif p.kind == "array" then
        local elem = p.element
        local count = Engine.resolveCount(self, p.count)
        self[p._name] = {}
        if type(elem) == "table" and (elem.typeID or elem._fields) then
            -- 有 typeID 就有 section header (Section / Struct(0x01))，RawStruct 没有
            local hasHeader = elem.typeID ~= nil
            if not hasHeader then
                for i = 1, count do
                    local obj = elem:new()
                    obj.parent = self
                    pcall(obj.read, obj, r)
                    self[p._name][i] = obj
                end
            else
                for i = 1, count do
                    local ok, obj = pcall(Engine._readSingleStruct, r, elem, self)
                    if ok then
                        self[p._name][i] = obj
                    end
                end
            end
        elseif type(elem) == "table" and elem.marker then
            -- 标量/复合类型数组
            if elem.marker == "str" then
                for i = 1, count do
                    self[p._name][i] = r:str(elem.byteSize)
                end
            elseif elem.marker == "bytes" then
                for i = 1, count do
                    self[p._name][i] = r:raw(elem.byteSize)
                end
            else
                local method = scalarReaders[elem.marker]
                for i = 1, count do
                    self[p._name][i] = r[method](r)
                end
            end
        elseif type(elem) == "table" then
            -- 嵌套结构数组: elem = {u8, 4} 即每个元素是4个u8
            for i = 1, count do
                self[p._name][i] = {}
                local innerF = { name = "_elem", type = elem }
                local innerP = Engine.parseField(innerF)
                innerP._name = "_elem"
                -- 用临时对象承载
                local tmp = {}
                tmp._elem = nil
                Engine._readField(tmp, r, innerP)
                self[p._name][i] = tmp._elem
            end
        end

    elseif p.kind == "rawstruct" then
        local obj = p.class:new()
        obj.parent = self
        obj:read(r)
        self[p._name] = obj

    elseif p.kind == "struct" then
        if p.optional then
            -- Peek: 如果下一个 typeID 不匹配则跳过
            local savedPos = r.pos
            local nextType = r:u32()
            if nextType == p.class.typeID then
                r.pos = savedPos
                Engine._readStructField(self, r, p)
            else
                r.pos = savedPos
            end
        else
            Engine._readStructField(self, r, p)
        end

    elseif p.kind == "dispatch" then
        local dispatchKey = Engine.resolvePath(self, p.by)
        local Class = p.map[dispatchKey]
        if not Class then
            -- 未知 dispatch 类型: 存储 raw 字节（保持可回写）
            io.stderr:write(string.format("[RW] Unknown dispatch subtype %s in catalogue at 0x%X\n",
                tostring(dispatchKey), r.pos))
            local remaining = p.sizeFrom and Engine.resolvePath(self, p.sizeFrom)
            if remaining and remaining > 0 then
                local raw = r:raw(remaining)
                self[p._name] = {
                    _raw = raw,
                    getSize = function() return #raw end,
                    write = function(_, w) w:raw(raw) end,
                }
            else
                self[p._name] = nil
            end
        else
            -- 用 sizeFrom 限制的 sub-reader 防止 schema 与文件不匹配时超读
            local readLimit = p.sizeFrom and self[p.sizeFrom]
            if readLimit and readLimit > 0 then
                local effectBody = r:raw(readLimit)
                local subR = Reader.new(effectBody)
                local obj = Class:new()
                obj:read(subR)
                if subR.pos <= #effectBody then
                    obj._trailingData = string.sub(effectBody, subR.pos)
                end
                obj.parent = self
                self[p._name] = obj
            else
                local obj = Class:new()
                obj:read(r)
                obj.parent = self
                self[p._name] = obj
            end
        end

    elseif p.kind == "extlist" then
        -- 扩展列表: 读取到 self.size 字节耗尽
        self[p._name] = {}
        local consumed = 0
        while consumed < self.size do
            local obj = SectionRegistry.read(r, self)
            self[p._name][#self[p._name] + 1] = obj
            consumed = consumed + obj.size + 12
        end
    end
end

-- ====== WRITE ======

function Engine.makeWriter(fields)
    local parsed = {}
    for _, f in ipairs(fields) do
        local p = Engine.parseField(f)
        p._name = f.name
        parsed[#parsed + 1] = p
    end
    return function(self, w)
        Engine._writeParsedFields(self, w, parsed)
    end
end

function Engine._writeParsedFields(self, w, parsed)
    for _, p in ipairs(parsed) do
        if Engine.checkCond(self, p.cond) then
            Engine._writeField(self, w, p)
        end
    end
end

function Engine._writeField(self, w, p)
    if p.kind == "scalar" then
        local method = scalarWriters[p.marker]
        local val = self[p._name]
        if method then
            w[method](w, val)
        elseif p.marker == "str" then
            -- byteSize 未指定或为路径/函数: write 取实际字符串长度
            local sz = p.byteSize
            if sz == nil or type(sz) == "string" or type(sz) == "function" then
                sz = #(val or "")
            end
            w:str(val or "", sz)
        elseif p.marker == "bytes" then
            w:raw(val or "")
        end

    elseif p.kind == "fixed" then
        w[scalarWriters[p.marker]](w, p.value)

    elseif p.kind == "sync" then
        local val = Engine.computeSyncValue(self, p.sync)
        w[scalarWriters[p.marker]](w, val)

    elseif p.kind == "bits" then
        -- 从 raw 值出发; 仅当位字段显式设置时才覆盖对应位
        local val = self[p._name] or 0
        for _, bitDef in ipairs(p.bits) do
            local bitName = bitDef[1]
            local bitPos = bitDef[2]
            local bitLen = bitDef[3] or 1
            local fieldVal = self[bitName]
            if fieldVal == nil then
                -- 未显式设置: 从 raw 值中提取, 保持原值
                fieldVal = bExtract(val, bitPos, bitLen)
            end
            if bitLen == 1 then fieldVal = fieldVal and 1 or 0 end
            local mask = bitmask(bitLen)
            -- 清除旧位: val = val - (val中该区域的旧值)
            val = val - bExtract(val, bitPos, bitLen) * (2 ^ bitPos)
            -- 设置新位
            val = val + fieldVal * (2 ^ bitPos)
        end
        w[scalarWriters[p.marker]](w, val)

    elseif p.kind == "array" then
        local arr = self[p._name] or {}
        local elem = p.element
        if type(elem) == "table" and (elem.typeID or elem._fields) then
            local hasHeader = elem.typeID and elem.typeID ~= 0x01
            if not hasHeader then
                for i = 1, #arr do arr[i]:_writeBody(w) end
            else
                for i = 1, #arr do arr[i]:write(w) end
            end
        elseif type(elem) == "table" and elem.marker then
            if elem.marker == "str" then
                for i = 1, #arr do
                    w:str(arr[i] or "", elem.byteSize)
                end
            elseif elem.marker == "bytes" then
                for i = 1, #arr do
                    w:raw(arr[i] or "")
                end
            else
                local method = scalarWriters[elem.marker]
                for i = 1, #arr do
                    w[method](w, arr[i])
                end
            end
        elseif type(elem) == "table" then
            for i = 1, #arr do
                local innerF = { name = "_elem", type = elem }
                local innerP = Engine.parseField(innerF)
                innerP._name = "_elem"
                local tmp = { _elem = arr[i] }
                Engine._writeField(tmp, w, innerP)
            end
        end

    elseif p.kind == "rawstruct" then
        local obj = self[p._name]
        if obj then obj:write(w) end

    elseif p.kind == "struct" then
        local obj = self[p._name]
        if obj then obj:write(w) end

    elseif p.kind == "dispatch" then
        local obj = self[p._name]
        if obj then obj:write(w) end

    elseif p.kind == "extlist" then
        local exts = self[p._name] or {}
        for _, ext in ipairs(exts) do
            ext:write(w)
        end
    end
end

-- ====== GETSIZE ======

function Engine.makeSizeCalc(fields)
    local parsed = {}
    for _, f in ipairs(fields) do
        local p = Engine.parseField(f)
        p._name = f.name
        parsed[#parsed + 1] = p
    end
    return function(self)
        return Engine._computeSize(self, parsed)
    end
end

function Engine._computeSize(self, parsed)
    local total = 0
    for _, p in ipairs(parsed) do
        if Engine.checkCond(self, p.cond) then
            total = total + Engine._fieldSize(self, p)
        end
    end
    return total
end

function Engine._fieldSize(self, p)
    if p.kind == "scalar" or p.kind == "sync" or p.kind == "fixed" or p.kind == "bits" then
        if p.marker == "str" then
            local bs = p.byteSize
            if bs == nil or type(bs) == "string" or type(bs) == "function" then
                local val = self[p._name]
                return #(val or "")
            end
            return bs
        end
        return p.byteSize

    elseif p.kind == "array" then
        local arr = self[p._name] or {}
        local elem = p.element
        if type(elem) == "table" and (elem.typeID or elem._fields) then
            local total = 0
            local hasHeader = elem.typeID and elem.typeID ~= 0x01
            if not hasHeader then
                for i = 1, #arr do total = total + arr[i]:_calcSize() end
            else
                for i = 1, #arr do total = total + arr[i]:getSize() end
            end
            return total
        elseif type(elem) == "table" and elem.marker then
            return #arr * elem.byteSize
        elseif type(elem) == "table" then
            local innerParsed = Engine.parseField({ name = "_e", type = elem })
            return #arr * innerParsed.byteSize
        end

    elseif p.kind == "rawstruct" then
        local obj = self[p._name]
        return obj and obj:getSize() or 0

    elseif p.kind == "struct" then
        local obj = self[p._name]
        return obj and obj:getSize() or 0

    elseif p.kind == "dispatch" then
        local obj = self[p._name]
        return obj and obj:getSize() or 0

    elseif p.kind == "extlist" then
        local total = 0
        for _, ext in ipairs(self[p._name] or {}) do
            total = total + ext:getSize()
        end
        return total
    end
    return 0
end

-- === sync 值计算 ===

-- ====== 位域双向绑定 ======
-- 安装 __newindex 使 bit 字段与 raw 值自动互相同步
--   self.bCollisionTest = true  → 自动更新 self.flags
--   self.flags = 5              → 自动更新 self.bCollisionTest / self.bRender

function Engine.installBitsSync(cls, fields)
    -- bitName → { parent, pos, len }
    local bitMap = {}
    -- parentName → { { name, pos, len }, ... }
    local parentMap = {}

    for _, f in ipairs(fields) do
        if f.bits then
            local parentName = f.name
            local children = {}
            for _, bitDef in ipairs(f.bits) do
                local bitName = bitDef[1]
                local bitPos  = bitDef[2]
                local bitLen  = bitDef[3] or 1
                bitMap[bitName] = { parent = parentName, pos = bitPos, len = bitLen }
                children[#children + 1] = { name = bitName, pos = bitPos, len = bitLen }
            end
            parentMap[parentName] = children
        end
    end

    -- 没有位域字段则无需安装
    if not next(bitMap) then return end

    -- 保存引用供 __newindex / __index 使用
    cls._bitsBitMap = bitMap
    cls._bitsParentMap = parentMap

    local existingNewindex = cls.__newindex

    cls.__newindex = function(self, key, value)
        -- 写入 bit 字段: 同步更新 raw 值
        local bf = bitMap[key]
        if bf then
            rawset(self, key, value)
            local rawVal = rawget(self, bf.parent) or 0
            local mask = bitmask(bf.len)
            rawVal = rawVal - bExtract(rawVal, bf.pos, bf.len) * (2 ^ bf.pos)
            if bf.len == 1 then value = value and 1 or 0 end
            rawVal = rawVal + value * (2 ^ bf.pos)
            rawset(self, bf.parent, rawVal)
            return
        end

        -- 写入 raw 字段: 同步展开所有 bit 子字段
        local children = parentMap[key]
        if children then
            rawset(self, key, value)
            for _, child in ipairs(children) do
                local bitVal = bExtract(value, child.pos, child.len)
                if child.len == 1 then
                    rawset(self, child.name, bitVal == 1)
                else
                    rawset(self, child.name, bitVal)
                end
            end
            return
        end

        -- 普通字段: 直写
        if existingNewindex then
            existingNewindex(self, key, value)
        else
            rawset(self, key, value)
        end
    end
end

-- === sync 值计算 ===

function Engine.computeSyncValue(self, syncSpec)
    if type(syncSpec) == "function" then
        return syncSpec(self)
    elseif type(syncSpec) == "string" then
        local target = self[syncSpec]
        if target == nil then return 0 end
        -- struct/catalogue: get body size; array: get count
        if type(target) == "table" and target.getSize then
            return target:getSize()
        end
        return #target
    elseif type(syncSpec) == "table" then
        local total = 0
        for _, src in ipairs(syncSpec) do
            local target = self[src]
            if type(target) == "table" and target.getSize then
                total = total + target:getSize()
            else
                total = total + (target and #target or 0)
            end
        end
        return total
    end
    return 0
end
