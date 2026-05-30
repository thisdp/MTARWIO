-- dff/geometry.lua — 几何体系统所有 Section

-- 单个 UV 通道 (必须在 GeometryStruct 之前定义)
TexCoordChannel = Struct:define({
    { name = "coords", type = vec2, count = "parent.vertexCount" },
})

-- ====== GeometryStruct — 核心几何数据 ======
GeometryStruct = Struct:define({
    { name = "header", type = uint16, bits = {
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

    { name = "vertexColors", type = rgba, count = "vertexCount", raw = true,
      cond = {{"bVertexColor", "==", true}, {"bNative", "==", false}} },

    { name = "texCoords", type = TexCoordChannel, raw = true,
      count = function(self) return self:uvChannelCount() end,
      cond = {{"bNative", "==", false}} },

    { name = "faces", type = Face, count = "faceCount", raw = true,
      cond = {{"bNative", "==", false}} },

    { name = "boundingSphere", type = vec4 },
    { name = "hasVertices",    type = bool32 },
    { name = "hasNormals",     type = bool32 },

    { name = "vertices", type = vec3, count = "vertexCount", raw = true,
      cond = {{"hasVertices", "==", true}} },

    { name = "normals", type = vec3, count = "vertexCount", raw = true,
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

-- ====== GeometryListStruct ======
GeometryListStruct = Struct:define({
    { name = "geometryCount", type = uint32, sync = "geometries" },
})

-- ====== GeometryList (0x1A) ======
GeometryList = Section:define(0x1A, {
    { name = "struct",     type = GeometryListStruct },
    { name = "geometries", type = Geometry, count = "struct.geometryCount" },
})

-- ====== mergeGeometry (手动逻辑) ======
function Geometry:mergeGeometry(target, clone)
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

    if not ss.bNative then
        if ss.bVertexColor then
            local svc2 = #ss.vertexColors
            for i = 1, #ts.vertexColors do
                ss.vertexColors[svc2 + i] = {ts.vertexColors[i][1], ts.vertexColors[i][2], ts.vertexColors[i][3], ts.vertexColors[i][4]}
            end
        end
        local uvCh = ss:uvChannelCount()
        for ch = 1, uvCh do
            local sc, tc = ss.texCoords[ch], ts.texCoords[ch]
            if sc and tc then
                local si = #sc.coords
                for v = 1, #tc.coords do
                    sc.coords[si + v] = {tc.coords[v][1], tc.coords[v][2]}
                end
            end
        end
        local sfc = #ss.faces
        for i = 1, #ts.faces do
            ss.faces[sfc + i] = {ts.faces[i][1] + svc, ts.faces[i][2] + svc, ts.faces[i][3], ts.faces[i][4] + svc}
        end
    end

    if ss.hasVertices then
        for i = 1, tvc do sv[svc + i] = {tv[i][1], tv[i][2], tv[i][3]} end
    end
    if ss.hasNormals then
        local sn, tn = ss.normals, ts.normals or {}
        for i = 1, #tn do sn[#sn + i] = {tn[i][1], tn[i][2], tn[i][3]} end
    end

    local sml, tml = self.materialList, target.materialList
    local smc = sml.struct.materialCount
    for i = 1, #tml.materials do
        sml.materials[smc + i] = tml.materials[i]
        sml.struct.materialIndices[smc + i] = tml.struct.materialIndices[i]
    end
    sml.struct.materialCount = #sml.materials
    return oldSelf
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
        out[#out+1] = indent .. string.format("header       = 0x%04X  bits: %s", gs.header or 0, table.concat(bits, ", "))
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
                    i, f[1] or 0, f[2] or 0, f[3] or 0, f[4] or 0)
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
        for i, geo in ipairs(self.geometries) do
            geo._dumpIndex = i
            geo:dump(out, lvl + 1, limits)
        end
    end
end
