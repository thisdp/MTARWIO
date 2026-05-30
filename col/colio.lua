-- col/colio.lua — COL 碰撞文件 I/O

COLIO = {}

function COLIO:new()
    return setmetatable({
        collision = nil,
    }, { __index = COLIO })
end

function COLIO:load(pathOrRaw)
    local data = pathOrRaw
    if fileExists(pathOrRaw) then
        local f = fileOpen(pathOrRaw)
        if f then
            data = fileRead(f, fileGetSize(f))
            fileClose(f)
        end
    end
    local r = Reader.new(data)
    self.collision = Collision:new()
    self.collision:read(r)
    return self
end

function COLIO:save(fileName)
    local w = Writer.new()
    self.collision:write(w)
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

local newBounds
local newSphere
local newVertex
local newFace
local newFaceGroup

-- 从 DFF Geometry 生成碰撞
function COLIO:generateFromGeometry(colVersion, geometry, matList)
    local col = Collision:new()
    col:init(colVersion)

    -- 材质映射
    local matRef = {}
    if type(matList) == "table" then
        for k, v in pairs(matList) do
            if type(k) == "string" then
                local mID = geometry.materialList:findMaterialByTexName(k)
                if mID then matRef[mID] = v end
            elseif type(k) == "number" then
                if geometry.materialList.materials[k] then matRef[k] = v end
            elseif type(k) == "table" then
                local mID = geometry.materialList:findMaterialByColor(k[1], k[2], k[3], k[4])
                if mID then matRef[mID] = v end
            end
        end
    end

    -- 复制顶点
    local geoVerts = geometry.struct.vertices
    col.vertexCount = #geoVerts
    col.vertices = {}
    for i = 1, col.vertexCount do
        col.vertices[i] = newVertex()
        col.vertices[i][1] = geoVerts[i][1]
        col.vertices[i][2] = geoVerts[i][2]
        col.vertices[i][3] = geoVerts[i][3]
    end

    -- 复制面
    local geoFaces = geometry.struct.faces
    col.faceCount = #geoFaces
    col.faces = {}
    local faceHash = {}
    for i = 1, col.faceCount do
        col.faces[i] = newFace()
        col.faces[i].a = geoFaces[i][1]
        col.faces[i].b = geoFaces[i][2]
        col.faces[i].c = geoFaces[i][4]
        col.faces[i].material = 0
        col.faces[i].light = 0
        col.faces[i].light = 1
        col.faces[i].material = 0
        local hash = geoFaces[i][2] .. "-" .. geoFaces[i][1] .. "-" .. geoFaces[i][4]
        faceHash[hash] = i
    end

    -- 材质分配（通过 BinMeshPLG）
    local binMesh = geometry.extension and geometry.extension.binMeshPLG
    if binMesh then
        for _, split in ipairs(binMesh.materialSplits) do
            local material = matRef[split[2] + 1] or 0
            local faceList = split[3]
            for idx = 1, #faceList, 3 do
                local hash = faceList[idx] .. "-" .. faceList[idx + 1] .. "-" .. faceList[idx + 2]
                if faceHash[hash] then
                    col.faces[faceHash[hash]].material = material
                end
            end
        end
    end

    if colVersion ~= "COLL" then
        col.flags = bReplace(col.flags or 0, (col.vertexCount ~= 0) and 1 or 0, 1)
    end

    self.collision = col
    return col
end

-- ====== COL 基本结构 (RawStruct) ======
COLHeader = RawStruct:define({
    { name = "version", type = str, byteSize = 4 },
    { name = "size", type = uint32 },
    { name = "modelName", type = str, byteSize = 22 },
    { name = "modelID", type = uint16 },
})

COLSurface = RawStruct:define({
    { name = "material", type = uint8 },
    { name = "flags", type = uint8 },
    { name = "brightness", type = uint8, default = 255 },
    { name = "light", type = uint8 },
})

COLSurface.default = function()
    return COLSurface:new()
end

COLBounds = RawStruct:define({
    { name = "radius", type = float32, cond = {{"parent.version", "==", "COLL"}} },
    { name = "center", type = vec3, cond = {{"parent.version", "==", "COLL"}} },
    { name = "min", type = vec3, cond = {{"parent.version", "==", "COLL"}} },
    { name = "max", type = vec3, cond = {{"parent.version", "==", "COLL"}} },

    { name = "min", type = vec3, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "max", type = vec3, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "center", type = vec3, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "radius", type = float32, cond = {{"parent.version", "~=", "COLL"}} },
})

COLSphere = RawStruct:define({
    { name = "radius", type = float32, cond = {{"parent.version", "==", "COLL"}} },
    { name = "center", type = vec3, cond = {{"parent.version", "==", "COLL"}} },
    { name = "surface", type = COLSurface, cond = {{"parent.version", "==", "COLL"}} },

    { name = "center", type = vec3, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "radius", type = float32, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "surface", type = COLSurface, cond = {{"parent.version", "~=", "COLL"}} },
})

COLBox = RawStruct:define({
    { name = "min", type = vec3 },
    { name = "max", type = vec3 },
    { name = "surface", type = COLSurface },
})

COLVertex = RawStruct:define({
    { name = 1, type = float32, cond = {{"parent.version", "==", "COLL"}} },
    { name = 2, type = float32, cond = {{"parent.version", "==", "COLL"}} },
    { name = 3, type = float32, cond = {{"parent.version", "==", "COLL"}} },

    { name = 1, type = int16, cond = {{"parent.version", "~=", "COLL"}} },
    { name = 2, type = int16, cond = {{"parent.version", "~=", "COLL"}} },
    { name = 3, type = int16, cond = {{"parent.version", "~=", "COLL"}} },
})

COLFace = RawStruct:define({
    { name = "a", type = uint32, cond = {{"parent.version", "==", "COLL"}} },
    { name = "b", type = uint32, cond = {{"parent.version", "==", "COLL"}} },
    { name = "c", type = uint32, cond = {{"parent.version", "==", "COLL"}} },
    { name = "surface", type = COLSurface, cond = {{"parent.version", "==", "COLL"}} },

    { name = "a", type = uint16, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "b", type = uint16, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "c", type = uint16, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "material", type = uint8, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "light", type = uint8, cond = {{"parent.version", "~=", "COLL"}} },
})

COLFaceGroup = RawStruct:define({
    { name = "min", type = vec3, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "max", type = vec3, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "startFace", type = uint16, cond = {{"parent.version", "~=", "COLL"}} },
    { name = "endFace", type = uint16, cond = {{"parent.version", "~=", "COLL"}} },
})

newBounds = function()
    return COLBounds:new()
end

newSphere = function()
    return COLSphere:new()
end

newVertex = function()
    return COLVertex:new()
end

newFace = function()
    return COLFace:new()
end

newFaceGroup = function()
    return COLFaceGroup:new()
end

-- ====== Collision — 碰撞数据容器 ======
Collision = {}

function Collision:new()
    return setmetatable({
        version = nil,
        size = 0,
        modelName = "default",
        modelID = 0,
        bound = nil,
        vertexCount = 0,
        sphereCount = 0,
        boxCount = 0,
        faceGroupCount = 0,
        faceCount = 0,
        lineCount = 0,
        trianglePlaneCount = 0,
        flags = 0,
        offsetSphere = 0,
        offsetBox = 0,
        offsetLine = 0,
        offsetFaceGroup = 0,
        offsetVertex = 0,
        offsetFace = 0,
        offsetTrianglePlane = 0,
        shadowFaceCount = 0,
        shadowVertexCount = 0,
        offsetShadowVertex = 0,
        offsetShadowFace = 0,
        spheres = {},
        boxes = {},
        vertices = {},
        faces = {},
        faceGroups = {},
        shadowFaces = {},
        shadowVertices = {},
        useConeInsteadOfLine = false,
        notEmpty = false,
        hasFaceGroup = false,
        hasShadow = false,
    }, { __index = Collision })
end

function Collision:init(ver)
    self.version = ver or "COLL"
    self.size = 0
    self.bound = newBounds()
    self.bound.parent = self
    if self.version == "COL2" or self.version == "COL3" then
        self.flags = 0
        self.useConeInsteadOfLine = bExtract(self.flags, 0) == 1
        self.notEmpty = bExtract(self.flags, 1) == 1
        self.hasFaceGroup = bExtract(self.flags, 3) == 1
        self.hasShadow = bExtract(self.flags, 4) == 1
    end
    return self
end

function Collision:read(r)
    local header = COLHeader:new()
    header:read(r)
    self.version = header.version
    self.size = header.size
    self.modelName = header.modelName
    self.modelID = header.modelID

    self.bound = newBounds()
    self.bound.parent = self
    self.bound:read(r)

    if self.version == "COL2" or self.version == "COL3" then
        self.sphereCount = r:u16()
        self.boxCount = r:u16()
        self.faceCount = r:u16()
        self.lineCount = r:u8()
        self.trianglePlaneCount = r:u8()
        self.flags = r:u32()
        self.useConeInsteadOfLine = bExtract(self.flags, 0) == 1
        self.notEmpty = bExtract(self.flags, 1) == 1
        self.hasFaceGroup = bExtract(self.flags, 3) == 1
        self.hasShadow = bExtract(self.flags, 4) == 1

        self.offsetSphere = r:u32()
        self.offsetBox = r:u32()
        self.offsetLine = r:u32()
        self.offsetVertex = r:u32()
        self.offsetFace = r:u32()
        self.offsetTrianglePlane = r:u32()

        if self.version == "COL3" then
            self.shadowFaceCount = r:u32()
            self.offsetShadowVertex = r:u32()
            self.offsetShadowFace = r:u32()
        end

        if self.sphereCount > 0 then
            local saved = r.pos
            r.pos = self.offsetSphere + 5
            self.spheres = {}
            for i = 1, self.sphereCount do
                self.spheres[i] = newSphere()
                self.spheres[i].parent = self
                self.spheres[i]:read(r)
            end
            r.pos = saved
        end

        if self.boxCount > 0 then
            local saved = r.pos
            r.pos = self.offsetBox + 5
            self.boxes = {}
            for i = 1, self.boxCount do
                self.boxes[i] = COLBox:new()
                self.boxes[i].parent = self
                self.boxes[i]:read(r)
            end
            r.pos = saved
        end

        local offsetFaceGroup = nil
        if self.hasFaceGroup then
            local saved = r.pos
            r.pos = self.offsetFace + 5
            if r.pos + 3 <= r.len then
                self.faceGroupCount = r:u32()
            else
                self.faceGroupCount = 0
            end
            -- 合法性校验: faceGroupCount 应在合理范围 (≤ faceCount 且 ≤ 1000)
            if self.faceGroupCount > 0 and self.faceGroupCount <= self.faceCount and self.faceGroupCount <= 1000 then
                offsetFaceGroup = r.pos - 4 - self.faceGroupCount * 28
                if offsetFaceGroup >= 1 then
                    r.pos = offsetFaceGroup
                    self.faceGroups = {}
                    for i = 1, self.faceGroupCount do
                        self.faceGroups[i] = newFaceGroup()
                        self.faceGroups[i].parent = self
                        self.faceGroups[i]:read(r)
                    end
                end
            else
                -- faceGroupCount 非法 (实际二进制中无 faceGroup 数据), 回退
                self.faceGroupCount = 0
                offsetFaceGroup = nil
            end
            r.pos = saved
        end

        if self.faceCount > 0 then
            local saved = r.pos
            -- face 数据在 faceGroup 区域之后 (如果有合法 faceGroup 的话)
            if offsetFaceGroup then
                r.pos = self.offsetFace + 5 + 4 + self.faceGroupCount * 28
            else
                r.pos = self.offsetFace + 5
            end
            self.faces = {}
            for i = 1, self.faceCount do
                self.faces[i] = newFace()
                self.faces[i].parent = self
                self.faces[i]:read(r)
            end
            r.pos = saved
        end

        local vEnd = offsetFaceGroup or (self.offsetFace + 4)
        self.vertexCount = ((vEnd - (self.offsetVertex + 4)) / 6)
        self.vertexCount = self.vertexCount - (self.vertexCount % 1)
        self.vertices = {}
        if self.vertexCount > 0 then
            local saved = r.pos
            r.pos = self.offsetVertex + 5
            for i = 1, self.vertexCount do
                self.vertices[i] = newVertex()
                self.vertices[i].parent = self
                self.vertices[i]:read(r)
            end
            r.pos = saved
        end

        if self.hasShadow and self.version == "COL3" then
            if self.shadowFaceCount > 0 then
                local saved = r.pos
                r.pos = self.offsetShadowFace + 5
                self.shadowFaces = {}
                for i = 1, self.shadowFaceCount do
                    self.shadowFaces[i] = newFace()
                    self.shadowFaces[i].parent = self
                    self.shadowFaces[i]:read(r)
                end
                r.pos = saved
            end

            self.shadowVertexCount = ((self.offsetShadowFace + 4) - (self.offsetShadowVertex + 4)) / 6
            self.shadowVertexCount = self.shadowVertexCount - (self.shadowVertexCount % 1)
            self.shadowVertices = {}
            if self.shadowVertexCount > 0 then
                local saved = r.pos
                r.pos = self.offsetShadowVertex + 5
                for i = 1, self.shadowVertexCount do
                    self.shadowVertices[i] = newVertex()
                    self.shadowVertices[i].parent = self
                    self.shadowVertices[i]:read(r)
                end
                r.pos = saved
            end
        end
    elseif self.version == "COLL" then
        self.sphereCount = r:u32()
        self.spheres = {}
        for i = 1, self.sphereCount do
            self.spheres[i] = newSphere()
            self.spheres[i].parent = self
            self.spheres[i]:read(r)
        end
        r:u32()
        self.boxCount = r:u32()
        self.boxes = {}
        for i = 1, self.boxCount do
            self.boxes[i] = COLBox:new()
            self.boxes[i].parent = self
            self.boxes[i]:read(r)
        end
        self.vertexCount = r:u32()
        self.vertices = {}
        for i = 1, self.vertexCount do
            self.vertices[i] = newVertex()
            self.vertices[i].parent = self
            self.vertices[i]:read(r)
        end
        self.faceCount = r:u32()
        self.faces = {}
        for i = 1, self.faceCount do
            self.faces[i] = newFace()
            self.faces[i].parent = self
            self.faces[i]:read(r)
        end
    end
end

function Collision:write(w)
    w:str(self.version, 4)
    local sizeReserve = w:reserveU32()
    w:str(self.modelName or "", 22)
    w:u16(self.modelID or 0)

    local maxX, maxY, maxZ = -256, -256, -256
    local minX, minY, minZ = 256, 256, 256

    for i = 1, #(self.vertices or {}) do
        local v = self.vertices[i]
        if maxX < v[1] then maxX = v[1] end
        if maxY < v[2] then maxY = v[2] end
        if maxZ < v[3] then maxZ = v[3] end
        if minX > v[1] then minX = v[1] end
        if minY > v[2] then minY = v[2] end
        if minZ > v[3] then minZ = v[3] end
    end

    for i = 1, #(self.spheres or {}) do
        local s = self.spheres[i]
        local sMinX, sMinY, sMinZ = s.center[1] - s.radius, s.center[2] - s.radius, s.center[3] - s.radius
        local sMaxX, sMaxY, sMaxZ = s.center[1] + s.radius, s.center[2] + s.radius, s.center[3] + s.radius
        if maxX < sMaxX then maxX = sMaxX end
        if maxY < sMaxY then maxY = sMaxY end
        if maxZ < sMaxZ then maxZ = sMaxZ end
        if minX > sMinX then minX = sMinX end
        if minY > sMinY then minY = sMinY end
        if minZ > sMinZ then minZ = sMinZ end
    end

    for i = 1, #(self.boxes or {}) do
        local b = self.boxes[i]
        if maxX < b.max[1] then maxX = b.max[1] end
        if maxY < b.max[2] then maxY = b.max[2] end
        if maxZ < b.max[3] then maxZ = b.max[3] end
        if minX > b.min[1] then minX = b.min[1] end
        if minY > b.min[2] then minY = b.min[2] end
        if minZ > b.min[3] then minZ = b.min[3] end
    end

    self.bound.min = { minX, minY, minZ }
    self.bound.max = { maxX, maxY, maxZ }
    self.bound.center = { (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2 }
    self.bound.radius = ((minX - self.bound.center[1]) ^ 2
        + (minY - self.bound.center[2]) ^ 2
        + (minZ - self.bound.center[3]) ^ 2) ^ 0.5

    self.bound.parent = self
    self.bound:write(w)

    if self.version == "COL2" or self.version == "COL3" then
        self.sphereCount = #self.spheres
        self.boxCount = #self.boxes
        self.faceCount = #self.faces
        self.lineCount = 0
        self.trianglePlaneCount = 0

        w:u16(self.sphereCount)
         :u16(self.boxCount)
         :u16(self.faceCount)
         :u8(self.lineCount)
         :u8(self.trianglePlaneCount)
         :u32(self.flags or 0)

        local sphereOffset = w:reserveU32()
        local boxOffset = w:reserveU32()
        local lineOffset = w:reserveU32()
        local vertexOffset = w:reserveU32()
        local faceOffset = w:reserveU32()
        local triOffset = w:reserveU32()

        local shadowVertexOffset, shadowFaceOffset
        if self.version == "COL3" then
            w:u32(self.shadowFaceCount or 0)
            shadowVertexOffset = w:reserveU32()
            shadowFaceOffset = w:reserveU32()
        end

        if self.sphereCount ~= 0 then
            self.offsetSphere = w:position() - 4
            sphereOffset.fill(self.offsetSphere)
            for i = 1, self.sphereCount do
                self.spheres[i].parent = self
                self.spheres[i]:write(w)
            end
        end

        if self.boxCount ~= 0 then
            self.offsetBox = w:position() - 4
            boxOffset.fill(self.offsetBox)
            for i = 1, self.boxCount do
                self.boxes[i].parent = self
                self.boxes[i]:write(w)
            end
        end

        if #self.vertices ~= 0 then
            self.offsetVertex = w:position() - 4
            vertexOffset.fill(self.offsetVertex)
            for i = 1, #self.vertices do
                self.vertices[i].parent = self
                self.vertices[i]:write(w)
            end
            if (w:position() - self.offsetVertex) % 4 ~= 0 then
                w:u16(0)
            end
        end

        if self.hasFaceGroup then
            self.faceGroupCount = #self.faceGroups
            for i = 1, self.faceGroupCount do
                self.faceGroups[i].parent = self
                self.faceGroups[i]:write(w)
            end
            w:u32(self.faceGroupCount)
        end

        if self.faceCount ~= 0 then
            self.offsetFace = w:position() - 4
            faceOffset.fill(self.offsetFace)
            for i = 1, self.faceCount do
                self.faces[i].parent = self
                self.faces[i]:write(w)
            end
        end

        if self.version == "COL3" and self.hasShadow then
            if self.shadowVertexCount ~= 0 then
                self.offsetShadowVertex = w:position() - 4
                shadowVertexOffset.fill(self.offsetShadowVertex)
                for i = 1, self.shadowVertexCount do
                    self.shadowVertices[i].parent = self
                    self.shadowVertices[i]:write(w)
                end
                if (w:position() - self.offsetShadowVertex) % 4 ~= 0 then
                    w:u16(0)
                end
            end
            if self.shadowFaceCount ~= 0 then
                self.offsetShadowFace = w:position() - 4
                shadowFaceOffset.fill(self.offsetShadowFace)
                for i = 1, self.shadowFaceCount do
                    self.shadowFaces[i].parent = self
                    self.shadowFaces[i]:write(w)
                end
            end
        end

        lineOffset.fill(self.offsetLine or 0)
        triOffset.fill(self.offsetTrianglePlane or 0)
    elseif self.version == "COLL" then
        self.sphereCount = #self.spheres
        w:u32(self.sphereCount)
        for i = 1, self.sphereCount do
            self.spheres[i].parent = self
            self.spheres[i]:write(w)
        end
        w:u32(0)
        self.boxCount = #self.boxes
        w:u32(self.boxCount)
        for i = 1, self.boxCount do
            self.boxes[i].parent = self
            self.boxes[i]:write(w)
        end
        self.vertexCount = #self.vertices
        w:u32(self.vertexCount)
        for i = 1, self.vertexCount do
            self.vertices[i].parent = self
            self.vertices[i]:write(w)
        end
        self.faceCount = #self.faces
        w:u32(self.faceCount)
        for i = 1, self.faceCount do
            self.faces[i].parent = self
            self.faces[i]:write(w)
        end
    end

    sizeReserve.fill(w:position())
end

function Collision:getSize()
    return self.size
end

-- ====== Dump ======
function Collision:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    local indent = string.rep("  ", lvl)
    local maxV = limits.maxVerts or 10
    local maxF = limits.maxFaces or 10
    local maxS = limits.maxVColors or 5

    out[#out+1] = indent .. "--- Collision ---"
    out[#out+1] = indent .. string.format("version    = \"%s\"", self.version or "?")
    out[#out+1] = indent .. string.format("modelName  = \"%s\"", self.modelName or "")
    out[#out+1] = indent .. string.format("modelID    = %d", self.modelID or 0)

    if self.bound then
        local b = self.bound
        out[#out+1] = indent .. "bound:"
        out[#out+1] = indent .. string.format("  radius   = %.4f", b.radius or 0)
        out[#out+1] = indent .. "  center   = " .. Section.fmtVec(b.center)
        out[#out+1] = indent .. "  min      = " .. Section.fmtVec(b.min)
        out[#out+1] = indent .. "  max      = " .. Section.fmtVec(b.max)
    end

    out[#out+1] = indent .. string.format("spheres   = %d  boxes = %d", self.sphereCount or #self.spheres or 0, self.boxCount or #self.boxes or 0)
    out[#out+1] = indent .. string.format("vertices  = %d  faces = %d", self.vertexCount or #self.vertices or 0, self.faceCount or #self.faces or 0)
    if self.hasFaceGroup then
        out[#out+1] = indent .. string.format("faceGroups= %d", self.faceGroupCount or #self.faceGroups or 0)
    end

    if self.spheres and #self.spheres > 0 then
        out[#out+1] = indent .. "spheres:"
        for i = 1, math.min(#self.spheres, maxS) do
            local s = self.spheres[i]
            out[#out+1] = indent .. string.format("  [%d] center=%s radius=%.4f", i, Section.fmtVec(s.center), s.radius or 0)
        end
        if #self.spheres > maxS then
            out[#out+1] = indent .. string.format("  ... +%d more", #self.spheres - maxS)
        end
    end

    if self.boxes and #self.boxes > 0 then
        out[#out+1] = indent .. "boxes:"
        for i = 1, math.min(#self.boxes, maxS) do
            local b = self.boxes[i]
            out[#out+1] = indent .. string.format("  [%d] min=%s max=%s", i, Section.fmtVec(b.min), Section.fmtVec(b.max))
        end
        if #self.boxes > maxS then
            out[#out+1] = indent .. string.format("  ... +%d more", #self.boxes - maxS)
        end
    end

    if self.vertices and #self.vertices > 0 then
        out[#out+1] = indent .. string.format("vertices = %d total", #self.vertices)
        for i = 1, math.min(#self.vertices, maxV) do
            out[#out+1] = indent .. string.format("  [%d] %s", i, Section.fmtVec(self.vertices[i]))
        end
        if #self.vertices > maxV then
            out[#out+1] = indent .. string.format("  ... +%d more", #self.vertices - maxV)
        end
    end

    if self.faces and #self.faces > 0 then
        out[#out+1] = indent .. string.format("faces = %d total", #self.faces)
        for i = 1, math.min(#self.faces, maxF) do
            local f = self.faces[i]
            out[#out+1] = indent .. string.format("  [%d] a=%d b=%d c=%d mat=%d",
                i, f.a or 0, f.b or 0, f.c or 0, f.material or 0)
        end
        if #self.faces > maxF then
            out[#out+1] = indent .. string.format("  ... +%d more", #self.faces - maxF)
        end
    end

    if self.faceGroups and #self.faceGroups > 0 then
        out[#out+1] = indent .. string.format("faceGroups = %d total", #self.faceGroups)
        for i = 1, math.min(#self.faceGroups, maxS) do
            local fg = self.faceGroups[i]
            out[#out+1] = indent .. string.format("  [%d] min=%s max=%s start=%d end=%d",
                i, Section.fmtVec(fg.min), Section.fmtVec(fg.max), fg.startFace or 0, fg.endFace or 0)
        end
        if #self.faceGroups > maxS then
            out[#out+1] = indent .. string.format("  ... +%d more", #self.faceGroups - maxS)
        end
    end
end

function COLIO:dump(limits)
    local out = {}
    table.insert(out, string.rep("=", 70))
    table.insert(out, "  COL Structure Dump")
    table.insert(out, string.rep("=", 70))
    if self.collision then
        self.collision:dump(out, 0, limits)
    end
    table.insert(out, string.rep("=", 70))
    table.insert(out, "  End of COL Dump")
    table.insert(out, string.rep("=", 70))
    return table.concat(out, "\n")
end
