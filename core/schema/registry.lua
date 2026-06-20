-- registry.lua — Section 注册表
-- typeID → 构造函数映射，实现 Section 头的自动分发

SectionRegistry = {
    byID = {},
    extensions = {},  -- { containerName → { typeID → class } }
}

-- 注册普通 Section（自动记录 typeID）
function SectionRegistry.register(cls)
    SectionRegistry.byID[cls.typeID] = cls
    return cls
end

-- 注册扩展子插件到指定容器
function SectionRegistry.registerPlugin(containerName, cls)
    if not SectionRegistry.extensions[containerName] then
        SectionRegistry.extensions[containerName] = {}
    end
    SectionRegistry.extensions[containerName][cls.typeID] = cls
    return cls
end

-- 从 Reader 中读取一个完整的 Section（头 + 体）
function SectionRegistry.read(r, parent)
    local typeID = r:u32()
    local size = r:u32()
    local version = r:u32()

    local Class = SectionRegistry.byID[typeID]
    if not Class then
        -- typeID 0x00000000 + size 0 = padding/EOF, 直接终止
        if typeID == 0 and size == 0 then
            error("EOF padding")
        end
        -- 未知类型: 读取 raw 字节跳过, 不中断解析, 并记录日志
        io.stderr:write(string.format("[RW] Unknown section type 0x%08X at 0x%X, size=%d — raw bytes stored\n",
            typeID, r.pos - 12, size))
        local obj = Section:new()
        obj["@"] = r.pos - 12
        obj.type = typeID
        obj.size = size
        obj.version = version
        obj._typeName = "UNKNOWN"
        if parent then obj.parent = parent end
        obj.rawData = r:raw(size)
        obj.getSize = function(self) return #(self.rawData or "") + 12 end
        obj.write = function(self, w)
            self.size = #(self.rawData or "")
            w:u32(self.type):u32(self.size):u32(self:getVersion())
            w:raw(self.rawData or "")
        end
        return obj
    end

    local obj = Class:new()
    obj["@"] = r.pos - 12  -- section 在二进制流中的起始偏移
    obj.type = typeID
    obj.size = size
    obj.version = version
    if parent then obj.parent = parent end
    local expectedEnd = r.pos + size  -- section body 结束位置
    local ok, err = pcall(obj.read, obj, r)
    if r.pos < expectedEnd then
        -- 未读到的尾部数据: 保留用于精确回写
        local gap = expectedEnd - r.pos
        io.stderr:write(string.format("[RW] Trailing data %d bytes in section 0x%08X at 0x%X\n",
            gap, typeID, r.pos))
        obj._trailingData = r:raw(gap)
        r.pos = expectedEnd
    elseif r.pos > expectedEnd then
        io.stderr:write(string.format("[RW] Overshoot %d bytes in section 0x%08X at 0x%X\n",
            r.pos - expectedEnd, typeID, r.pos))
        r.pos = expectedEnd  -- 纠正超读
    end
    if not ok then error(err) end  -- 重新抛出
    return obj
end

-- 创建扩展列表类型标记（用于字段定义中）
-- 用法: { name = "extension", type = ExtensionList("GeometryExtension") }
function ExtensionList(containerName)
    return {
        __IS_EXT_LIST = true,
        _registry = SectionRegistry.extensions[containerName],
    }
end
