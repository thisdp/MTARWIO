-- dff/geometry.lua — 几何体系统所有 Section (Face, Geometry, GeometryList)

-- ====== Face ======
Face = RawStruct:define({
    { name = 1, type = uint16 },
    { name = 2, type = uint16 },
    { name = 3, type = uint16 },
    { name = 4, type = uint16 },
})

Face.V1  = 2
Face.V2  = 1
Face.V3  = 4
Face.Mat = 3

function Face:getVertices()
    return { self[Face.V1], self[Face.V2], self[Face.V3] }
end

function Face:getMaterial()
    return self[Face.Mat]
end

function Face:init(v1, v2, v3, matIdx)
    self[1] = v2 or 0      -- self[1] = v2 (RW order: v2, v1, mat, v3)
    self[2] = v1 or 0      -- self[2] = v1
    self[3] = matIdx or 0  -- self[3] = mat
    self[4] = v3 or 0      -- self[4] = v3
    return self
end

-- 单个 UV 通道 (必须在 GeometryStruct 之前定义)
TexCoordChannel = RawStruct:define({
    { name = "coords", type = vec2, count = "parent.vertexCount" },
})

-- ====== GeometryStruct — 核心几何数据 ======
GeometryStruct = Struct:define({
    { name = "headerFlags", type = uint16, bits = {
        {"bTristrip", 0}, {"bPosition", 1}, {"bTextured", 2},
        {"bVertexColor", 3}, {"bNormal", 4}, {"bLight", 5},
        {"bModulateMaterialColor", 6}, {"bTextured2", 7},
    }},
    { name = "textureCount", type = uint8 },
    { name = "nativeFlag",  type = uint8, bits = {{"bNative", 0}} },

    { name = "faceCount",       type = uint32, sync = "faces" },
    { name = "vertexCount",     type = uint32, sync = "vertices" },
    { name = "morphTargetCount",type = uint32, value = 1 },

    -- GTAVC 独有光照
    { name = "ambient",  type = float32, cond = {{"version", "<", GTASA}} },
    { name = "specular", type = float32, cond = {{"version", "<", GTASA}} },
    { name = "diffuse",  type = float32, cond = {{"version", "<", GTASA}} },

    { name = "vertexColors", type = rgba, count = "vertexCount",
      cond = {{"bVertexColor", "==", true}, {"bNative", "==", false}} },

    { name = "texCoords", type = TexCoordChannel,
      count = function(self) return self:uvChannelCount() end,
      cond = {{"bNative", "==", false}} },

    { name = "faces", type = Face, count = "faceCount",
      cond = {{"bNative", "==", false}} },

    { name = "boundingSphere", type = vec4 },
    { name = "hasVertices",    type = bool32 },
    { name = "hasNormals",     type = bool32 },

    { name = "vertices", type = vec3, count = "vertexCount",
      cond = {{"hasVertices", "==", true}} },

    { name = "normals", type = vec3, count = "vertexCount",
      cond = {{"hasNormals", "==", true}} },
})

function GeometryStruct:uvChannelCount()
    if self.textureCount and self.textureCount ~= 0 then
        return self.textureCount
    end
    return (self.bTextured and 1 or 0) + (self.bTextured2 and 1 or 0)
end

-- ====== GeometryExtension ======
GeometryExtension = Extension:define({
    { name = "plugins", type = ExtensionList("GeometryExtension") },
})

-- ====== Geometry (0x0F) ======
Geometry = Section:define(0x0F, {
    { name = "struct",       type = GeometryStruct },
    { name = "materialList", type = MaterialList },
    { name = "extension",    type = GeometryExtension },
})

-- ====== Geometry:create 工厂 ======
-- config 可选字段:
--   faceCount / vertexCount / textureCount / ...  直接透传到 GeometryStruct
function Geometry:create(config)
    config = config or {}
    local version = GTASA

    local geo = Geometry:new()
    geo.type = Geometry.typeID
    geo.version = version

    -- GeometryStruct
    geo.struct = GeometryStruct:new()
    geo.struct.parent = geo
    geo.struct:init(version)

    geo.struct.headerFlags = config.headerFlags or config.header or 0
    geo.struct.textureCount = config.textureCount or 0
    geo.struct.nativeFlag = config.nativeFlag or 0
    geo.struct.faceCount = config.faceCount or 0
    geo.struct.vertexCount = config.vertexCount or 0
    geo.struct.morphTargetCount = config.morphTargetCount or 1

    if version < GTASA then
        geo.struct.ambient = config.ambient or 1.0
        geo.struct.specular = config.specular or 1.0
        geo.struct.diffuse = config.diffuse or 1.0
    end

    geo.struct.boundingSphere = config.boundingSphere or {0, 0, 0, 0}
    geo.struct.hasVertices = config.hasVertices or false
    geo.struct.hasNormals = config.hasNormals or false
    geo.struct.faces = config.faces or {}
    geo.struct.vertices = config.vertices or {}

    -- MaterialList
    geo.materialList = MaterialList:new()
    geo.materialList.parent = geo
    geo.materialList.type = MaterialList.typeID
    geo.materialList.version = version
    geo.materialList.struct = MaterialListStruct:new()
    geo.materialList.struct.parent = geo.materialList
    geo.materialList.struct:init(version)
    geo.materialList.struct.materialCount = 0
    geo.materialList.struct.materialIndices = {}
    geo.materialList.materials = {}

    -- GeometryExtension
    geo.extension = GeometryExtension:new()
    geo.extension.parent = geo
    geo.extension:init(version)

    return geo
end

-- ====== GeometryListStruct ======
GeometryListStruct = Struct:define({
    { name = "geometryCount", type = uint32, sync = function(self) return #(self.parent.geometries) end },
})

-- ====== GeometryList (0x1A) ======
GeometryList = Section:define(0x1A, {
    { name = "struct",     type = GeometryListStruct },
    { name = "geometries", type = Geometry, count = "struct.geometryCount" },
})

-- 添加预创建的 Geometry, 返回 0-indexed geometry 索引
function GeometryList:addGeometry(geo)
    geo.parent = self
    self.geometries = self.geometries or {}
    local idx = #self.geometries
    self.geometries[idx + 1] = geo
    return idx, geo
end

-- ====== mergeGeometry (手动逻辑) ======
-- target: 被合并的 Geometry
-- clone:  是否返回合并前的 self 快照 (用于回滚)
-- mergeMaterials: 是否合并相同材质 (默认 true, 相同材质去重; false 则直接追加)
function Geometry:mergeGeometry(target, clone, mergeMaterials)
    if mergeMaterials == nil then mergeMaterials = true end
    if self.struct.bTristrip ~= target.struct.bTristrip then return false end
    if self.struct.bPosition ~= target.struct.bPosition then return false end
    if self.struct.bTextured ~= target.struct.bTextured then return false end
    if self.struct.bVertexColor ~= target.struct.bVertexColor then return false end
    if self.struct.bNormal ~= target.struct.bNormal then return false end
    if self.struct.bLight ~= target.struct.bLight then return false end
    if self.struct.bModulateMaterialColor ~= target.struct.bModulateMaterialColor then return false end
    if self.struct.bTextured2 ~= target.struct.bTextured2 then return false end

    local oldSelf = clone and tableUtil.deepCopy(self, self.parent) or nil
    local ss, ts = self.struct, target.struct
    local tv, sv = ts.vertices or {}, ss.vertices or {}
    local svc, tvc = #sv, #tv

    -- 材质映射: tMatMap[tMatIdx_0based] = mergedMatIdx_0based
    local sml, tml = self.materialList, target.materialList
    local smcMat = sml.struct.materialCount or 0
    local tMatMap = {}

    if mergeMaterials then
        -- 去重: 相同材质复用已有索引
        for ti = 1, #tml.materials do
            local found = false
            for si = 1, smcMat do
                if sml.materials[si]:equals(tml.materials[ti]) then
                    tMatMap[ti - 1] = si - 1
                    found = true
                    break
                end
            end
            if not found then
                sml.materials[#sml.materials + 1] = tml.materials[ti]
                sml.struct.materialIndices[#sml.materials] = -1  -- SA 标准
                tMatMap[ti - 1] = #sml.materials - 1
            end
        end
    else
        -- 直接追加
        for ti = 1, #tml.materials do
            sml.materials[#sml.materials + 1] = tml.materials[ti]
            sml.struct.materialIndices[#sml.materials] = -1  -- SA 标准
            tMatMap[ti - 1] = #sml.materials - 1
        end
    end
    sml.struct.materialCount = #sml.materials

    if not ss.bNative then
        if ss.bVertexColor then
            ss.vertexColors = ss.vertexColors or {}
            local svc2 = #ss.vertexColors
            local tc = ts.vertexColors or {}
            for i = 1, #tc do
                ss.vertexColors[svc2 + i] = {tc[i][1], tc[i][2], tc[i][3], tc[i][4]}
            end
        end
        local uvCh = ss:uvChannelCount()
        for ch = 1, uvCh do
            local sc = ss.texCoords and ss.texCoords[ch]
            local tc = ts.texCoords and ts.texCoords[ch]
            if sc and tc then
                local si = #(sc.coords or {})
                for v = 1, #(tc.coords or {}) do
                    sc.coords[si + v] = {tc.coords[v][1], tc.coords[v][2]}
                end
            end
        end
        local sfc = #(ss.faces or {})
        local tf = ts.faces or {}
        for i = 1, #tf do
            local matIdx = tMatMap[tf[i][3]] or (tf[i][3] + smcMat)
            ss.faces[sfc + i] = {
                tf[i][1] + svc,
                tf[i][2] + svc,
                matIdx,
                tf[i][4] + svc,
            }
        end
    end

    if ss.hasVertices then
        for i = 1, tvc do sv[svc + i] = {tv[i][1], tv[i][2], tv[i][3]} end
    end
    if ss.hasNormals then
        ss.normals = ss.normals or {}
        local tn = ts.normals or {}
        for i = 1, #tn do ss.normals[#ss.normals + i] = {tn[i][1], tn[i][2], tn[i][3]} end
    end

    -- 合并 BinMeshPLG (如果双方都有)
    local sBm = self.extension and self.extension.binMeshPLG
    local tBm = target.extension and target.extension.binMeshPLG
    if sBm and tBm then
        local sfc = #(ss.faces or {})  -- 合并前 source 的面数
        local tSplits = tBm.materialSplits or {}
        for i = 1, #tSplits do
            local ts = tSplits[i]
            -- 重映射材质索引
            ts.materialIndex = tMatMap[ts.materialIndex] or (ts.materialIndex + smcMat)
            -- 偏移面索引
            for j = 1, #ts.faceList do
                ts.faceList[j] = ts.faceList[j] + sfc
            end
            -- 追加到 source
            sBm.materialSplits[#sBm.materialSplits + 1] = ts
        end
        sBm.materialSplitCount = #sBm.materialSplits
        -- 更新顶点总数
        local totalVerts = 0
        for i = 1, #sBm.materialSplits do
        local sp = sBm.materialSplits[i]
            totalVerts = totalVerts + #sp.faceList
        end
        sBm.vertexCount = totalVerts
    end

    return oldSelf
end

-- ====== Face 增删 ======

function Geometry:addFace(faceData)
    if self.struct.bNative then
        error("Cannot add face to native geometry", 2)
    end
    local face
    if getmetatable(faceData) == Face then
        face = faceData
    elseif type(faceData) == "table" then
        face = Face:new():init(faceData[1], faceData[2], faceData[3], faceData[4] or faceData.mat or 0)
    else
        error("Bad argument @addFace, expected a face table or Face object", 2)
    end
    self.struct.faces = self.struct.faces or {}
    table.insert(self.struct.faces, face)
    self.struct.faceCount = #self.struct.faces
    return face
end

function Geometry:removeFace(index)
    if not self.struct.faces or index < 1 or index > #self.struct.faces then
        return false
    end
    local removed = self.struct.faces[index]
    table.remove(self.struct.faces, index)
    self.struct.faceCount = #self.struct.faces
    return removed
end

-- ====== Vertex 增删 ======

function Geometry:addVertex(x, y, z, nx, ny, nz)
    local gs = self.struct
    gs.vertices = gs.vertices or {}
    local idx = #gs.vertices + 1
    gs.vertices[idx] = {x or 0, y or 0, z or 0}
    if gs.hasNormals then
        gs.normals = gs.normals or {}
        gs.normals[idx] = {nx or 0, ny or 0, nz or 0}
    end
    if gs.bVertexColor then
        gs.vertexColors = gs.vertexColors or {}
        gs.vertexColors[idx] = {255, 255, 255, 255}
    end
    if gs.texCoords then
        for i = 1, #gs.texCoords do
            local tc = gs.texCoords[i]
            tc.coords = tc.coords or {}
            tc.coords[idx] = {0, 0}
        end
    end
    gs.vertexCount = #gs.vertices
    return idx
end

function Geometry:removeVertex(index)
    local gs = self.struct
    if not gs.vertices or index < 1 or index > #gs.vertices then
        return false
    end
    -- 检查面引用：不允许删除被面引用的顶点
    if gs.faces then
        for fi = 1, #gs.faces do
            local face = gs.faces[fi]
            local faceKeys = {Face.V1, Face.V2, Face.V3}
            for k = 1, 3 do
                if face[faceKeys[k]] == index - 1 then
                    error(string.format("Cannot remove vertex %d: referenced by face %d", index, fi), 2)
                end
            end
        end
    end
    local removed = gs.vertices[index]
    table.remove(gs.vertices, index)
    if gs.normals and #gs.normals >= index then
        table.remove(gs.normals, index)
    end
    if gs.vertexColors and #gs.vertexColors >= index then
        table.remove(gs.vertexColors, index)
    end
    if gs.texCoords then
        for i = 1, #gs.texCoords do
            local tc = gs.texCoords[i]
            if tc.coords and #tc.coords >= index then
                table.remove(tc.coords, index)
            end
        end
    end
    -- 更新面顶点引用：索引 > 该顶点的全部 -1
    if gs.faces then
        for i = 1, #gs.faces do
            local face = gs.faces[i]
            local faceKeys = {Face.V1, Face.V2, Face.V3}
            for k = 1, 3 do
                if face[faceKeys[k]] > index - 1 then
                    face[vk] = face[vk] - 1
                end
            end
        end
    end
    gs.vertexCount = #gs.vertices
    return removed
end

-- ====== 批量增删 ======

function Geometry:addVertices(vertices)
    if type(vertices) ~= "table" then return self end
    for i = 1, #vertices do
        local v = vertices[i]
        self:addVertex(v[1], v[2], v[3], v[4], v[5], v[6])
    end
    return self
end

function Geometry:addFaces(faces)
    if type(faces) ~= "table" then return self end
    for i = 1, #faces do
        local f = faces[i]
        if type(f) == "table" then
            self:addFace(f)
        end
    end
    return self
end

-- ====== 顶点色 ======

-- 设置单个顶点色 (index 从 1 开始)
function Geometry:setVertexColor(index, r, g, b, a)
    local gs = self.struct
    gs.bVertexColor = true
    gs.vertexColors = gs.vertexColors or {}
    gs.vertexColors[index] = {r, g, b, a or 255}
    return self
end

-- 批量替换所有顶点色 (长度必须等于 vertexCount)
-- colors: {{r,g,b,a}, ...}
function Geometry:setVertexColors(colors)
    local gs = self.struct
    local n = gs.vertexCount or 0
    if #colors ~= n then
        error(string.format("Vertex color count mismatch: got %d, expected %d", #colors, n), 2)
    end
    gs.bVertexColor = true
    gs.vertexColors = {}
    for i = 1, n do
        local c = colors[i]
        gs.vertexColors[i] = {c[1], c[2], c[3], c[4] or 255}
    end
    return self
end

-- 清除顶点色
function Geometry:removeVertexColors()
    local gs = self.struct
    gs.bVertexColor = false
    gs.vertexColors = nil
    return self
end

-- ====== NightVertexColor (夜晚顶点色) ======

-- 设置单个夜晚顶点色 (index 从 1 开始)
function Geometry:setNightVertexColor(index, r, g, b, a)
    local ext = self.extension
    if not ext then return self end
    local nvc = ext.nightVertexColor
    if not nvc then
        nvc = NightVertexColor:new()
        nvc.type = NightVertexColor.typeID
        nvc.version = self.version or GTASA
        nvc.hasColor = 1
        nvc.colors = {}
        nvc.parent = ext
        ext.plugins = ext.plugins or {}
        ext.plugins[#ext.plugins + 1] = nvc
    end
    nvc.hasColor = 1
    nvc.colors = nvc.colors or {}
    nvc.colors[index] = {r, g, b, a or 255}
    return self
end

-- 批量替换所有夜晚顶点色 (长度必须等于 vertexCount)
function Geometry:setNightVertexColors(colors)
    local gs = self.struct
    local n = gs.vertexCount or 0
    if #colors ~= n then
        error(string.format("Night vertex color count mismatch: got %d, expected %d", #colors, n), 2)
    end
    local ext = self.extension
    if not ext then return self end
    local nvc = ext.nightVertexColor
    if not nvc then
        nvc = NightVertexColor:new()
        nvc.type = NightVertexColor.typeID
        nvc.version = self.version or GTASA
        nvc.parent = ext
        ext.plugins = ext.plugins or {}
        ext.plugins[#ext.plugins + 1] = nvc
    end
    nvc.hasColor = 1
    nvc.colors = {}
    for i = 1, n do
        local c = colors[i]
        nvc.colors[i] = {c[1], c[2], c[3], c[4] or 255}
    end
    return self
end

-- 清除夜晚顶点色
function Geometry:removeNightVertexColors()
    local ext = self.extension
    if not ext or not ext.plugins then return self end
    local newPlugins = {}
    for i = 1, #(ext.plugins) do
        local p = ext.plugins[i]
        if p.type ~= NightVertexColor.typeID then
            newPlugins[#newPlugins + 1] = p
        end
    end
    ext.plugins = newPlugins
    return self
end

-- ====== 工具函数 ======

-- 从原始数据创建完整 Geometry (一次调用完成 setMesh + UV + 顶点色)
-- verts:  {{x,y,z}, ...}
-- norms:  {{nx,ny,nz}, ...} (可选, 与 verts 等长)
-- triVerts: {{v1,v2,v3,material?}, ...} 三角形顶点索引 (0-based)
-- texCoords: {[1]={{u,v},...}, [2]=...} 可选
-- vertexColors: {{r,g,b,a}, ...} 可选
-- config: {textureCount, ...} 可选
function Geometry:createMesh(verts, norms, triVerts, texCoords, vertexColors, config)
    config = config or {}

    self:setMesh(verts, norms, triVerts)

    -- textureCount
    local chCount = 0
    if texCoords then
        for ch = 1, #texCoords do
            if texCoords[ch] then chCount = chCount + 1 end
        end
    end
    self.struct.textureCount = config.textureCount or chCount

    -- UV
    if texCoords then
        for ch = 1, #texCoords do
            local coords = texCoords[ch]
            if coords then
                self:setTexCoords(ch, coords)
            end
        end
    end

    -- 顶点色
    if vertexColors then
        self:setVertexColors(vertexColors)
    end

    -- 自动重建 BinMeshPLG
    self:rebuildBinMeshPLG(triVerts, config.binMeshMaterialIndex or 0)

    return self
end

-- 根据顶点位置重建 boundingSphere (自动计算中心+半径)
function Geometry:rebuildBoundingSphere()
    local verts = self.struct.vertices
    if not verts or #verts == 0 then
        self.struct.boundingSphere = {0, 0, 0, 0}
        return self
    end
    -- 计算包围盒中心
    local minX, minY, minZ = verts[1][1], verts[1][2], verts[1][3]
    local maxX, maxY, maxZ = minX, minY, minZ
    for i = 1, #verts do
        local v = verts[i]
        if v[1] < minX then minX = v[1] end
        if v[1] > maxX then maxX = v[1] end
        if v[2] < minY then minY = v[2] end
        if v[2] > maxY then maxY = v[2] end
        if v[3] < minZ then minZ = v[3] end
        if v[3] > maxZ then maxZ = v[3] end
    end
    local cx, cy, cz = (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2
    -- 计算最大距离
    local maxR2 = 0
    for i = 1, #verts do
        local v = verts[i]
        local dx, dy, dz = v[1] - cx, v[2] - cy, v[3] - cz
        local r2 = dx*dx + dy*dy + dz*dz
        if r2 > maxR2 then maxR2 = r2 end
    end
    self.struct.boundingSphere = {cx, cy, cz, math.sqrt(maxR2)}
    return self
end

-- ====== 网格替换 ======

-- 清空所有顶点/面/法线/顶点色数据
function Geometry:clearMesh()
    local gs = self.struct
    gs.vertices = {}
    gs.normals = {}
    gs.faces = {}
    gs.vertexColors = nil
    gs.bVertexColor = false
    gs.vertexCount = 0
    gs.faceCount = 0
    return self
end

-- 一次性设置网格数据 (顶点 + 法线 + 三角形)
-- verts:  {{x,y,z}, ...} 顶点位置
-- norms:  {{nx,ny,nz}, ...} 法线 (可选, 与 verts 等长)
-- triVerts: {{v1,v2,v3}, ...} 三角形顶点索引 (0-based)
-- 自动设置 bTristrip=false (triangle list 模式)
function Geometry:setMesh(verts, norms, triVerts)
    self:clearMesh()
    local gs = self.struct

    -- bit field 自动同步 headerFlags (依赖 __newindex)
    gs.bTristrip = false
    gs.bPosition = true
    gs.bNormal = (norms ~= nil and #norms > 0)
    gs.bLight = true
    gs.bModulateMaterialColor = true

    gs.hasVertices = true
    gs.hasNormals = (norms ~= nil and #norms > 0)

    -- 批量添加顶点 (法线在 addVertex 中自动初始化为 0,0,0)
    self:addVertices(verts)

    -- 覆盖法线为实际值
    if norms and #norms > 0 then
        for i = 1, math.min(#norms, #gs.normals) do
            gs.normals[i] = {norms[i][1], norms[i][2], norms[i][3]}
        end
    end

    -- 批量添加面 (格式: {v1, v2, v3, material})
    if triVerts then
        for i = 1, #triVerts do
            local tri = triVerts[i]
            self:addFace({tri[1], tri[2], tri[3], tri[4] or 0})
        end
    end

    return self
end

-- 设置 UV 坐标
-- channel: 1 或 2
-- coords: {{u,v}, ...} 与顶点一一对应
function Geometry:setTexCoords(channel, coords)
    local gs = self.struct
    if not gs.texCoords then gs.texCoords = {} end
    if not gs.texCoords[channel] then
        gs.texCoords[channel] = TexCoordChannel:new()
    end
    gs.texCoords[channel].coords = {}
    for i = 1, #coords do
        local uv = coords[i]
        gs.texCoords[channel].coords[i] = {uv[1], uv[2]}
    end
    if channel == 1 then gs.bTextured = true end
    if channel == 2 then gs.bTextured2 = true end
    return self
end

-- 重建 BinMeshPLG: 从三角形数据创建新的 BinMeshPLG (替换旧的或新建)
-- triVerts: {{v1,v2,v3}, ...} 0-based 顶点索引
-- materialIndex: 材质索引 (默认 0)
function Geometry:rebuildBinMeshPLG(triVerts, materialIndex)
    materialIndex = materialIndex or 0
    local version = self.version or GTASA
    local ext = self.extension
    if not ext then return nil end

    local newBM = BinMeshPLG:new()
    newBM.type = BinMeshPLG.typeID
    newBM.version = version
    newBM.faceType = 0           -- triangle list mode
    newBM.materialSplitCount = 1

    local split = BinMeshSplit:new()
    split.faceCount = #triVerts * 3      -- 三角形数 × 3 = 顶点索引数
    split.materialIndex = materialIndex
    split.faceList = {}
    for i = 1, #triVerts do
        local tri = triVerts[i]
        split.faceList[#split.faceList + 1] = tri[1]
        split.faceList[#split.faceList + 1] = tri[2]
        split.faceList[#split.faceList + 1] = tri[3]
    end
    split.parent = newBM
    newBM.materialSplits = {split}
    newBM.parent = ext
    newBM:getSize()

    -- 替换旧 BinMeshPLG (如果存在), 否则追加
    local newPlugins = {}
    local replaced = false
    local plugins = ext.plugins or {}
    for i = 1, #plugins do
        local p = plugins[i]
        if p.type == BinMeshPLG.typeID then
            newPlugins[#newPlugins + 1] = newBM
            replaced = true
        else
            newPlugins[#newPlugins + 1] = p
        end
    end
    if not replaced then
        newPlugins[#newPlugins + 1] = newBM
    end
    ext.plugins = newPlugins
    return newBM
end

-- ====== 材质操作 ======

-- 设置材质: 清空旧材质并用默认模板创建新材质
-- matOrConfig: config table {color, texture, ambient, specular, diffuse}
function Geometry:setMaterial(matOrConfig)
    self:clearMaterials()
    local mat = self.materialList:addMaterial(
        Material:createSimple(matOrConfig or {}))
    -- 同步 textureCount (有纹理时至少为 1)
    if mat.struct.textureCount and mat.struct.textureCount > 0 then
        self.struct.textureCount = mat.struct.textureCount
    end
    return mat
end

-- 清空所有材质
function Geometry:clearMaterials()
    local ml = self.materialList
    ml.materials = {}
    ml.struct.materialIndices = {}
    ml.struct.materialCount = 0
    return self
end

-- 添加材质 (便捷代理)
function Geometry:addMaterial(matOrConfig)
    return self.materialList:addMaterial(matOrConfig)
end

-- 移除材质 (便捷代理)
function Geometry:removeMaterial(index)
    return self.materialList:removeMaterial(index)
end

-- ====== 自动重建包围球 ======
-- 覆盖 write，在序列化前自动根据顶点数据重建 boundingSphere
local _Geometry_write = Geometry.write
function Geometry:write(w)
    self:rebuildBoundingSphere()
    return _Geometry_write(self, w)
end

-- ====== Dump ======
Geometry._typeName = "Geometry"

function Geometry:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    local idx = self._dumpIndex
    local idxStr = idx and (" [" .. idx .. "]") or ""
    Section.dump(self, out, lvl, limits)
    if self.struct then
        local gs = self.struct
        local indent = string.rep("  ", lvl + 1)
        local maxV = limits.maxVerts or 10
        local maxF = limits.maxFaces or 10
        local maxC = limits.maxVColors or 5

        local bits = {}
        if gs.bTristrip then bits[#bits+1] = "bTristrip" end
        if gs.bPosition then bits[#bits+1] = "bPosition" end
        if gs.bTextured then bits[#bits+1] = "bTextured" end
        if gs.bVertexColor then bits[#bits+1] = "bVertexColor" end
        if gs.bNormal then bits[#bits+1] = "bNormal" end
        if gs.bLight then bits[#bits+1] = "bLight" end
        if gs.bModulateMaterialColor then bits[#bits+1] = "bModulateMaterialColor" end
        if gs.bTextured2 then bits[#bits+1] = "bTextured2" end
        out[#out+1] = indent .. string.format("headerFlags  = 0x%04X  bits: %s", gs.headerFlags or 0, table.concat(bits, ", "))
        out[#out+1] = indent .. string.format("faceCount    = %d  vertexCount = %d  morphTarget = %d",
            gs.faceCount or 0, gs.vertexCount or 0, gs.morphTargetCount or 1)
        out[#out+1] = indent .. string.format("bNative      = %s  hasV=%s  hasN=%s",
            tostring(gs.bNative), tostring(gs.hasVertices), tostring(gs.hasNormals))
        if gs.boundingSphere then
            out[#out+1] = indent .. string.format("boundSphere  = %s", Section.fmtVec(gs.boundingSphere))
        end

        if gs.vertices and #gs.vertices > 0 then
            out[#out+1] = indent .. string.format("vertices     = %d total", #gs.vertices)
            local n = math.min(#gs.vertices, maxV)
            for i = 1, n do
                local v = gs.vertices[i]
                out[#out+1] = indent .. string.format("  [%d] (%.4f, %.4f, %.4f)", i, v[1] or 0, v[2] or 0, v[3] or 0)
            end
            if #gs.vertices > maxV then
                out[#out+1] = indent .. string.format("  ... +%d more", #gs.vertices - maxV)
            end
        end
        if gs.normals and #gs.normals > 0 then
            out[#out+1] = indent .. string.format("normals      = %d total", #gs.normals)
            for i = 1, math.min(#gs.normals, maxV) do
                local v = gs.normals[i]
                out[#out+1] = indent .. string.format("  [%d] (%.4f, %.4f, %.4f)", i, v[1] or 0, v[2] or 0, v[3] or 0)
            end
            if #gs.normals > maxV then
                out[#out+1] = indent .. string.format("  ... +%d more", #gs.normals - maxV)
            end
        end
        if gs.faces and #gs.faces > 0 then
            out[#out+1] = indent .. string.format("faces        = %d total (tri=%s)",
                #gs.faces, tostring(gs.bTristrip and "strip" or "list"))
            for i = 1, math.min(#gs.faces, maxF) do
                local f = gs.faces[i]
                out[#out+1] = indent .. string.format("  [%d] v1=%d v2=%d v3=%d mat=%d",
                    i, f[2] or 0, f[1] or 0, f[4] or 0, f[3] or 0)
            end
            if #gs.faces > maxF then
                out[#out+1] = indent .. string.format("  ... +%d more", #gs.faces - maxF)
            end
        end
        if gs.vertexColors and #gs.vertexColors > 0 then
            out[#out+1] = indent .. string.format("vertexColors = %d total", #gs.vertexColors)
            for i = 1, math.min(#gs.vertexColors, maxC) do
                local c = gs.vertexColors[i]
                out[#out+1] = indent .. string.format("  [%d] (R=%d G=%d B=%d A=%d)", i, c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0)
            end
            if #gs.vertexColors > maxC then
                out[#out+1] = indent .. string.format("  ... +%d more", #gs.vertexColors - maxC)
            end
        end
        if gs.texCoords and #gs.texCoords > 0 then
            for ch = 1, #gs.texCoords do
                local tc = gs.texCoords[ch]
                if tc and tc.coords then
                    out[#out+1] = indent .. string.format("texCoords[%d] = %d coords", ch, #tc.coords)
                    for i = 1, math.min(#tc.coords, maxV) do
                        local c = tc.coords[i]
                        out[#out+1] = indent .. string.format("  [%d] (%.4f, %.4f)", i, c[1] or 0, c[2] or 0)
                    end
                    if #tc.coords > maxV then
                        out[#out+1] = indent .. string.format("  ... +%d more", #tc.coords - maxV)
                    end
                end
            end
        end
    end
    if self.materialList then self.materialList:dump(out, lvl + 1, limits) end
    if self.extension then
        out[#out+1] = string.rep("  ", lvl + 1) .. "--- GeometryExtension ---"
        self.extension:dump(out, lvl + 1, limits)
    end
end

GeometryList._typeName = "GeometryList"
function GeometryList:dump(out, lvl, limits)
    lvl = lvl or 0
    limits = limits or {}
    Section.dump(self, out, lvl, limits)
    if self.struct then
        local indent = string.rep("  ", lvl + 1)
        out[#out+1] = indent .. string.format("geometryCount = %d", self.struct.geometryCount or #self.geometries)
    end
    if self.geometries then
        for i = 1, #self.geometries do
            local geo = self.geometries[i]
            geo._dumpIndex = i
            geo:dump(out, lvl + 1, limits)
        end
    end
end
