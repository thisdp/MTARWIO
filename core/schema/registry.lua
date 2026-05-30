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
function SectionRegistry.read(r)
    local typeID = r:u32()
    local size = r:u32()
    local version = r:u32()

    local Class = SectionRegistry.byID[typeID]
    if not Class then
        error("Unknown RW section type: 0x" .. string.format("%08X", typeID))
    end

    local obj = Class:new()
    obj["@"] = r.pos - 12  -- section 在二进制流中的起始偏移
    obj.type = typeID
    obj.size = size
    obj.version = version
    obj:read(r)
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
