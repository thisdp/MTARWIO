-- dff/dffio.lua — DFF 文件顶层 I/O

DFFIO = {}

-- ====== Dump ======
function DFFIO:dump(limits)
    local out = {}
    table.insert(out, string.rep("=", 70))
    table.insert(out, "  DFF Structure Dump")
    table.insert(out, string.rep("=", 70))
    table.insert(out, string.format("DFF Version: 0x%08X (%s)",
        self.version or 0,
        self.version == EnumRWVersion.GTASA and "GTASA" or
        self.version == EnumRWVersion.GTAVC and "GTAVC" or "Unknown"))
    table.insert(out, string.format("Clump count: %d", #self.clumps))

    if self.uvAnimDict then
        self.uvAnimDict:dump(out, 0, limits)
    end
    for ci = 1, #self.clumps do
        local clump = self.clumps[ci]
        table.insert(out, "")
        table.insert(out, string.rep("=", 70))
        table.insert(out, string.format("  CLUMP [%d/%d]", ci, #self.clumps))
        table.insert(out, string.rep("=", 70))
        clump:dump(out, 0, limits)
    end
    table.insert(out, "")
    table.insert(out, string.rep("=", 70))
    table.insert(out, "  End of DFF Dump")
    table.insert(out, string.rep("=", 70))
    return table.concat(out, "\n")
end

-- ====== I/O ======
function DFFIO:new(version)
    return setmetatable({
        uvAnimDict = nil,
        clumps = {},
        others = {},
        version = version or GTASA,
    }, { __index = DFFIO })
end

-- 从文件路径或原始字符串加载
function DFFIO:load(pathOrRaw)
    local data = pathOrRaw
    if fileExists(pathOrRaw) then
        local f = fileOpen(pathOrRaw)
        if f then
            data = fileRead(f, fileGetSize(f))
            fileClose(f)
        end
    end
    local r = Reader.new(data)
    self.clumps = {}
    self.others = {}
    self.uvAnimDict = nil
    -- 循环读取顶层 Section: 按 typeID 分发
    while r.pos + 12 <= r.len do
        local ok, obj = pcall(SectionRegistry.read, r)
        if not ok then break end
        self.version = obj.version
        if obj.type == Clump.typeID then
            self.clumps[#self.clumps + 1] = obj
        elseif obj.type == UVAnimDict.typeID then
            self.uvAnimDict = obj
        else
            self.others[#self.others + 1] = obj
        end
    end
    return self
end

-- 保存为文件或返回字符串
function DFFIO:save(fileName)
    local w = Writer.new()
    if self.uvAnimDict then
        self.uvAnimDict:write(w)
    end
    for i = 1, #self.others do
        self.others[i]:write(w)
    end
    for i = 1, #self.clumps do
        self.clumps[i]:write(w)
    end
    local str = w:build()
    if fileName then
        if fileExists(fileName) then fileDelete(fileName) end
        local f = fileCreate(fileName)
        fileWrite(f, str)
        fileClose(f)
        return true
    end
    return str
end

-- 版本转换 ("GTASA" / "GTAVC") — 只需修改根节点 version，子节点自动继承
function DFFIO:convert(target)
    if type(target) ~= "string" then
        error("Bad argument @convert, expected a string got " .. type(target), 2)
    end
    local targetVer = EnumRWVersion[target:upper()]
    if not targetVer then
        error("Bad argument @convert, invalid type '" .. target .. "'", 2)
    end
    self.version = targetVer
    return true
end

-- 重新计算所有 size
function DFFIO:update()
    for i = 1, #self.clumps do
        self.clumps[i]:getSize()
    end
end

-- 创建新 Clump (已完全初始化, 无需手动设置子结构)
function DFFIO:createClump()
    local clump = Clump:new()
    clump.parent = self
    clump.version = self.version
    clump.type = Clump.typeID

    -- ClumpStruct
    clump.struct = ClumpStruct:new()
    clump.struct.parent = clump
    clump.struct:init(clump.version)
    clump.struct.cameraCount = 0

    -- FrameList
    clump.frameList = FrameList:new()
    clump.frameList.parent = clump
    clump.frameList:init(clump.version)
    clump.frameList.struct = FrameListStruct:new()
    clump.frameList.struct.parent = clump.frameList
    clump.frameList.struct:init(clump.version)
    clump.frameList.frames = {}

    -- GeometryList
    clump.geometryList = GeometryList:new()
    clump.geometryList.parent = clump
    clump.geometryList:init(clump.version)
    clump.geometryList.struct = GeometryListStruct:new()
    clump.geometryList.struct.parent = clump.geometryList
    clump.geometryList.struct:init(clump.version)
    clump.geometryList.geometries = {}

    -- Extension
    clump.extension = ClumpExtension:new()
    clump.extension.parent = clump
    clump.extension:init(clump.version)

    clump.atomics = {}
    clump.lights = {}
    clump.indexStructs = {}
    clump.size = clump:getSize() - 12
    self.clumps[#self.clumps + 1] = clump
    return clump
end
