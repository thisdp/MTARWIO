# MTARW DFFIO API 参考

MTARW 是基于声明式 Schema 引擎的 RenderWare 二进制格式（DFF/TXD/COL）加载器，专为 MTA:SA 设计。DFFIO 模块提供完整的 DFF 模型读写能力——从零创建、模板修改、引擎渲染。

## 快速开始

```lua
local version = GTASA
local dff = DFFIO:new()
local clump = dff:createClump(version)

-- 创建几何体
local hw, hd, hh = 2.5, 2.5, 2.5
local geo = Geometry:create(version, {
    boundingSphere = {0, 0, 0, math.sqrt(3) * hw},
    textureCount = 1,
})

-- 顶点 + 法线 + 三角形
local verts = {
    {-hw,-hd,-hh}, { hw,-hd,-hh}, { hw, hd,-hh}, {-hw, hd,-hh},
    {-hw,-hd, hh}, { hw,-hd, hh}, { hw, hd, hh}, {-hw, hd, hh},
}
local norms = {
    {-0.577,-0.577,-0.577}, {0.577,-0.577,-0.577},
    {0.577,0.577,-0.577}, {-0.577,0.577,-0.577},
    {-0.577,-0.577,0.577}, {0.577,-0.577,0.577},
    {0.577,0.577,0.577}, {-0.577,0.577,0.577},
}
local triVerts = {
    {0,1,2}, {0,2,3}, {5,4,7}, {5,7,6},
    {3,2,6}, {3,6,7}, {1,0,4}, {1,4,5},
    {1,5,6}, {1,6,2}, {0,4,7}, {0,7,3},
}

geo:setMesh(verts, norms, triVerts)
geo:setMaterial({color = {255, 80, 80, 255}, texture = "vehiclegeneric256"})

-- UV 坐标
local uvBase = {{0,1},{1,1},{1,0},{0,0}}
geo:setTexCoords(1, {uvBase[1],uvBase[2],uvBase[3],uvBase[4],
                      uvBase[1],uvBase[2],uvBase[3],uvBase[4]})

-- BinMeshPLG（材质分割）
geo:rebuildBinMeshPLG(triVerts, 0)

-- 组装
clump.geometryList:addGeometry(geo)
Frame:create(clump.frameList, {name = "box", matrixFlags = 0x00020003})
clump:addAtomic(Atomic:create(version, {}))

-- 保存
dff:update()
_MTARW_BOX_DFF_DATA = dff:save()
```

---

# 模块参考

## DFFIO — 文件级 I/O

### `DFFIO:new()`

创建空的 DFF 容器。

| Param | Type | Description |
|-------|------|-------------|
| (none) | | |

Returns: `DFFIO` 实例

```lua
local dff = DFFIO:new()
```

---

### `DFFIO:load(pathOrRaw)`

从文件路径或原始二进制字符串加载 DFF。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| pathOrRaw | string | (required) | 文件路径或 DFF 二进制字符串 |

Returns: `self` (DFFIO)

```lua
dff:load("my_model.dff")
dff:load(rawDataString)  -- 从二进制字符串加载
```

---

### `DFFIO:save(fileName?)`

序列化 DFF。若提供文件名则写入文件，否则返回二进制字符串。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| fileName | string | nil | 输出路径（可选） |

Returns: `true` (file mode) 或 `string` (raw mode)

```lua
dff:save("output.dff")
local raw = dff:save()  -- 返回二进制字符串
```

---

### `DFFIO:createClump(version)`

创建完全初始化的 Clump（含 FrameList、GeometryList、Extension）。无需手动初始化子结构。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| version | uint32 | GTASA | DFF 版本（GTASA=0x1803FFFF, GTAVC=0x0C02FFFF） |

Returns: `Clump`

```lua
local clump = dff:createClump(GTASA)
```

---

### `DFFIO:update()`

重新计算所有 Clump 的大小。在修改结构后、`save` 之前调用。

Returns: (none)

```lua
dff:update()
```

---

### `DFFIO:dump(limits?)`

生成人类可读的结构 dump 字符串。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| limits | table | {} | `{maxVerts, maxFaces, maxVColors}` 限制输出行数 |

Returns: `string`

```lua
local fd = fileCreate("dump.txt")
fileWrite(fd, dff:dump({maxVerts=20, maxFaces=20}))
fileClose(fd)
```

---

### `DFFIO:convert(target)`

版本转换所有 Clump。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| target | string | (required) | `"GTASA"` 或 `"GTAVC"` |

Returns: `true`

```lua
dff:convert("GTASA")
```

---

## Clump — 模型容器

Clump 是 DFF 顶层容器，包含 FrameList（骨骼/框架）、GeometryList（几何体）、Atomic（渲染单元）。

### `Clump:addAtomic(atomic)`

添加 Atomic 到 Clump，自动设置 frameIndex 和 geometryIndex。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| atomic | Atomic | (required) | Atomic 对象（由 `Atomic:create` 创建） |

Returns: `idx (0-based), atomic`

```lua
clump:addAtomic(Atomic:create(version, {}))
```

---

### `Clump:addComponent(comp)`

添加完整组件（Frame + Geometry + Atomic 一键）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| comp | table | (required) | `{frameInfo, frame, geometry, atomic}` |

Returns: `idx (0-based), atomic`

---

### `Clump:addEmptyComponent(config)`

自动创建 Frame + Geometry + Atomic 组件。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| config | table | {} | `{name, position, rotationMatrix, parentFrame, matrixFlags, geometry, flags}` |

Returns: `idx (0-based), atomic`

```lua
clump:addEmptyComponent({name = "part1", matrixFlags = 0x00020003})
```

---

### `Clump:getComponent(index)`

按 Atomic 索引获取组件。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| index | int | (required) | 1-based Atomic 索引 |

Returns: `{atomic, frameInfo, frame, geometry}` 或 nil

---

### `Clump:getComponentByName(name)`

按 Frame 名称查找组件。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| name | string | (required) | Frame 名称 |

Returns: `{atomic, frameInfo, frame, geometry}` 或 nil

---

### `Clump:removeComponent(index)`

删除组件（Atomic + Frame + Geometry），自动修正引用索引。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| index | int | (required) | 1-based Atomic 索引 |

Returns: `atomic` 或 `false`

```lua
clump:removeComponent(1)
```

---

## Geometry — 几何体

几何体包含顶点、面、法线、UV、材质等所有渲染数据。

### `Geometry:create(version, config)`

创建 Geometry。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| version | uint32 | GTASA | DFF 版本 |
| config | table | {} | 配置选项 |

config 字段:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| headerFlags | uint16 | 0 | 几何标志位（bits: bTristrip, bPosition, bTextured, bVertexColor, bNormal, bLight, bMMC, bTextured2） |
| textureCount | uint8 | 0 | UV 通道数（1 或 2） |
| nativeFlag | uint8 | 0 | 原生标志（bNative） |
| boundingSphere | vec4 | {0,0,0,0} | 包围球 {x, y, z, radius} |
| faceCount | uint32 | 0 | 面数（通常由 `setMesh` 管理） |
| vertexCount | uint32 | 0 | 顶点数（通常由 `setMesh` 管理） |

```lua
local geo = Geometry:create(GTASA, {textureCount = 1})
```

---

### `Geometry:setMesh(verts, norms, triVerts)`

一次性设置网格数据。自动管理 headerFlags（bPosition, bNormal, bLight, bMMC, bTristrip=false）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| verts | table | (required) | `{{x,y,z}, ...}` 顶点位置 |
| norms | table | (required) | `{{nx,ny,nz}, ...}` 法线（与 verts 等长） |
| triVerts | table | (required) | `{{v1,v2,v3,material?}, ...}` 三角形，顶点索引 0-based |

Returns: `self`

```lua
geo:setMesh(verts, norms, {
    {0,1,2}, {0,2,3},  -- 面1/面2，材质索引 0
    {5,4,7}, {5,7,6},  -- 面3/面4
    -- ...
})
```

---

### `Geometry:clearMesh()`

清空所有顶点/面/法线/顶点色数据。

Returns: `self`

---

### `Geometry:addFace(faceData)`

添加单个面。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| faceData | table | (required) | `{v1, v2, v3, material}` 或 Face 对象 |

Returns: `Face`

```lua
geo:addFace({0, 1, 2, 0})  -- v1=0, v2=1, v3=2, material=0
```

---

### `Geometry:removeFace(index)`

移除指定面。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| index | int | (required) | 1-based 面索引 |

Returns: `Face` 或 `false`

---

### `Geometry:addFaces(faces)`

批量添加面。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| faces | table | (required) | `{{v1,v2,v3,material}, ...}` |

Returns: `self`

---

### `Geometry:addVertex(x, y, z, nx?, ny?, nz?)`

添加单个顶点。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| x, y, z | float | (required) | 位置 |
| nx, ny, nz | float | 0 | 法线（可选） |

Returns: `1-based vertex index`

---

### `Geometry:removeVertex(index)`

移除顶点（需先确保无面引用）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| index | int | (required) | 1-based 顶点索引 |

Returns: `vertex` 或 `false`

---

### `Geometry:addVertices(vertices)`

批量添加顶点。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| vertices | table | (required) | `{{x,y,z,nx,ny,nz}, ...}` |

Returns: `self`

---

### `Geometry:addVertexColors(colors)`

批量设置顶点色。**长度必须等于 vertexCount。**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| colors | table | (required) | `{{r,g,b,a}, ...}` 每个分量 0-255 |

Returns: `self`

```lua
geo:addVertexColors({{255,0,0,255}, {0,255,0,255}, ...})
```

---

### `Geometry:removeVertexColors()`

清除顶点色（设 bVertexColor=false）。

Returns: `self`

---

### `Geometry:setTexCoords(channel, coords)`

设置指定 UV 通道的坐标。自动设 bTextured / bTextured2。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| channel | int | (required) | 1 或 2 |
| coords | table | (required) | `{{u,v}, ...}` 与顶点一一对应 |

Returns: `self`

```lua
geo:setTexCoords(1, {{0,1},{1,1},{1,0},{0,0}, {0,1},{1,1},{1,0},{0,0}})
```

---

### `Geometry:setMaterial(matOrConfig)`

清空旧材质并用默认模板创建新材质。自动同步 `textureCount`。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| matOrConfig | table | (required) | `{color, texture, ambient, specular, diffuse}` |

Returns: `Material`

```lua
geo:setMaterial({color = {255, 80, 80, 255}, texture = "vehiclegeneric256"})
```

---

### `Geometry:clearMaterials()`

清空所有材质。

Returns: `self`

---

### `Geometry:addMaterial(matOrConfig)`

添加材质（便捷代理 MaterialList:addMaterial）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| matOrConfig | Material 或 table | (required) | Material 对象或 config table |

Returns: `Material`

---

### `Geometry:removeMaterial(index)`

移除材质（便捷代理 MaterialList:removeMaterial）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| index | int | (required) | 1-based 材质索引 |

Returns: `Material` 或 `false`

---

### `Geometry:rebuildBinMeshPLG(triVerts, materialIndex?)`

创建/替换 BinMeshPLG（材质分割渲染优化）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| triVerts | table | (required) | `{{v1,v2,v3}, ...}` 三角形顶点索引 |
| materialIndex | int | 0 | 材质索引 |

Returns: `BinMeshPLG` 或 nil

---

### `Geometry:mergeGeometry(target, clone?, mergeMaterials?)`

合并另一个 Geometry 到当前对象。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| target | Geometry | (required) | 被合并的 Geometry |
| clone | bool | false | 是否返回合并前快照 |
| mergeMaterials | bool | true | 是否去重相同材质 |

Returns: `self`（clone=true 时返回快照）或 `false`（标志不兼容）

---

### `GeometryList:addGeometry(geo)`

添加 Geometry 到列表。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| geo | Geometry | (required) | Geometry 对象 |

Returns: `0-based index, geo`

---

## Material — 材质系统

### `Material:create(version, config)`

创建完整 Material。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| version | uint32 | GTASA | DFF 版本 |
| config | table | {} | 配置 |

config 字段:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| flags | uint32 | 0 | 材质标志 |
| color | rgba | {255,255,255,255} | 材质颜色 |
| textureCount | uint32 | 0 | 纹理数量 |
| textureName | string | "" | 纹理文件名 |
| maskName | string | "" | 遮罩文件名 |
| ambient | float | 1.0 | 环境光 |
| specular | float | 1.0 | 高光 |
| diffuse | float | 1.0 | 漫反射 |

---

### `Material:createSimple(version, config)`

快速创建材质（空 MaterialExtension，匹配 SA 标准）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| version | uint32 | GTASA | DFF 版本 |
| config | table | {} | `{color, texture, ambient, specular, diffuse}` |

config 字段:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| color | rgba | {255,255,255,255} | 材质颜色 |
| texture | string | "" | 纹理文件名（非空时 textureCount=1） |
| ambient | float | 0.3 | 环境光 |
| specular | float | 1.0 | 高光 |
| diffuse | float | 1.0 | 漫反射 |

Returns: `Material`

```lua
local mat = Material:createSimple(GTASA, {
    color = {255, 80, 80, 255},
    texture = "vehiclegeneric256",
})
```

---

### `Material:setColor(r, g, b, a)`

设置材质颜色。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| r, g, b | int | (required) | RGB 分量 0-255 |
| a | int | 255 | Alpha 分量 0-255 |

Returns: `self`

```lua
mat:setColor(255, 0, 0)        -- 红色, alpha=255
mat:setColor(255, 0, 0, 128)   -- 红色, alpha=128
```

---

### `Material:removeTexture()`

移除纹理（设 textureCount=0, texture=nil）。

Returns: `self`

---

### `Material:addReflection(coefficient?)`

添加反射插件（ReflectionMaterial）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| coefficient | float | 1.0 | 反射强度 0.0-1.0 |

Returns: `ReflectionMaterial` 或 nil

```lua
mat:addReflection(0.8)
```

---

### `Material:addSpecular(level?, texName?)`

添加高光插件（SpecularMaterial）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| level | float | 1.0 | 高光强度 0.0-1.0 |
| texName | string | "" | 高光贴图名 |

Returns: `SpecularMaterial` 或 nil

```lua
mat:addSpecular(0.5, "vehiclespecdot64")
```

---

### `Material:equals(other)`

判断两个 Material 是否相同（用于合并去重）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| other | Material | (required) | 比较对象 |

Returns: `bool`

---

### `MaterialList:addMaterial(material)`

添加材质到列表。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| material | Material 或 table | (required) | Material 对象或 config table |

Returns: `Material`

---

### `MaterialList:removeMaterial(index)`

移除材质（需先确保无面引用）。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| index | int | (required) | 1-based 材质索引 |

Returns: `Material` 或 `false`

---

### `MaterialList:findMaterialByTexName(texName)`

按纹理名查找材质。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| texName | string | (required) | 纹理文件名 |

Returns: `1-based index` 或 `false`

---

### `MaterialList:findMaterialByMaskName(maskName)`

按遮罩名查找材质。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| maskName | string | (required) | 遮罩文件名 |

Returns: `1-based index` 或 `false`

---

### `MaterialList:findMaterialByColor(r, g, b, a)`

按颜色查找材质。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| r, g, b, a | int | (required) | RGBA 分量 0-255 |

Returns: `1-based index` 或 `false`

---

### `Texture:create(version, config)`

创建纹理。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| version | uint32 | GTASA | DFF 版本 |
| config | table | {} | `{textureName, maskName}` |

```lua
local tex = Texture:create(GTASA, {textureName = "mytexture"})
```

---

## Atomic — 渲染单元

Atomic 连接 Frame（框架）和 Geometry（几何体），定义渲染行为。

### `Atomic:create(version, config)`

创建 Atomic。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| version | uint32 | GTASA | DFF 版本 |
| config | table | {} | `{flags, bCollisionTest, bRender}` |

```lua
local atomic = Atomic:create(GTASA, {flags = 5})  -- bCollisionTest + bRender
```

---

### `Atomic:getGeometry()`

获取关联的 Geometry。

Returns: `Geometry` 或 nil

---

### `Atomic:getFrame()`

获取关联的 FrameInfo 和 Frame。

Returns: `frameInfo, frame` 或 nil

---

### `Atomic:setFlags(flags)`

设置 Atomic 标志。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| flags | uint32 | (required) | Atomic 标志（bit0=bCollisionTest, bit2=bRender） |

Returns: `self`

```lua
atomic:setFlags(5)  -- 碰撞检测 + 渲染
```

---

## Frame — 框架/骨骼

### `Frame:create(parent, config)`

创建 Frame 并添加到 FrameList。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| parent | FrameList | (required) | 所属 FrameList |
| config | table | {} | 配置 |

config 字段:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | "Frame_N" | Frame 名称 |
| rotationMatrix | mat3x3 | 单位矩阵 | 3x3 旋转矩阵 |
| position | vec3 | {0,0,0} | 位置 |
| parentFrame | int | -1 | 父 Frame 索引（0-based, -1=根） |
| matrixFlags | uint32 | 0 | 矩阵标志（SA 标准: 0x00020003） |

Returns: `0-based frame index, frame`

```lua
Frame:create(clump.frameList, {name = "box", matrixFlags = 0x00020003})
```

---

### `FrameList:findFrameByName(name)`

按名称查找 Frame。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| name | string | (required) | Frame 名称 |

Returns: `0-based index` 或 `nil`

```lua
local idx = clump.frameList:findFrameByName("box")
```

---

### `Frame:setName(name)`

设置 Frame 名称。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| name | string | (required) | 新名称 |

Returns: `self`

---

## Light — 灯光

### `Light:create(parent, config)`

创建 Light 并添加到 Clump。

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| parent | Clump | (required) | 所属 Clump |
| config | table | {} | 配置 |

config 字段:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| radius | float | 10.0 | 灯光半径 |
| color | vec3 | {1,1,1} | RGB 颜色 |
| direction | float | 0.0 | 方向 |
| flags | uint16 | 0 | 灯光标志 |
| lightType | uint16 | 0x80 | 灯光类型（Point=0x80, Spot=0x81, SpotSoft=0x82, Directional=0x01, Ambient=0x02） |

Returns: `0-based light index, light`

```lua
Light:create(clump, {color = {1, 0.5, 0}, lightType = EnumLightType.Point})
```

---

# 枚举参考

## 版本

| 常量 | 值 | 说明 |
|------|-----|------|
| `GTASA` | `0x1803FFFF` | GTA San Andreas |
| `GTAVC` | `0x0C02FFFF` | GTA Vice City |

## 材质效果 (effectType)

| 常量 | 值 | 说明 |
|------|-----|------|
| `EnumMaterialEffect.None` | 0 | 无 |
| `EnumMaterialEffect.BumpMap` | 1 | 凹凸贴图 |
| `EnumMaterialEffect.EnvMap` | 2 | 环境反射 |
| `EnumMaterialEffect.BumpEnvMap` | 3 | 凹凸+环境 |
| `EnumMaterialEffect.Dual` | 4 | 双 pass |
| `EnumMaterialEffect.UVTransform` | 5 | UV 变换 |
| `EnumMaterialEffect.DualUVTransform` | 6 | 双 UV 变换 |

## 灯光类型

| 常量 | 值 | 说明 |
|------|-----|------|
| `EnumLightType.Directional` | `0x01` | 方向光 |
| `EnumLightType.Ambient` | `0x02` | 环境光 |
| `EnumLightType.Point` | `0x80` | 点光源 |
| `EnumLightType.Spot` | `0x81` | 聚光灯 |
| `EnumLightType.SpotSoft` | `0x82` | 柔化聚光灯 |
