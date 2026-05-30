# MTARW Schema 引擎手册

## 类型标记

每个类型是一个轻量表，包含 `marker`（读写标记）和 `byteSize`（字节宽）。

### 标量数值

| 类型 | marker | byteSize | default | 说明 |
|------|--------|----------|---------|------|
| `uint8` | u8 | 1 | 0 | |
| `uint16` | u16 | 2 | 0 | |
| `uint32` | u32 | 4 | 0 | |
| `int8` | i8 | 1 | 0 | |
| `int16` | i16 | 2 | 0 | |
| `int32` | i32 | 4 | 0 | |
| `float32` | f32 | 4 | 0.0 | |

### 语义复合

| 类型 | marker | byteSize | default |
|------|--------|----------|---------|
| `rgba` | rgba | 4 | `{0,0,0,0}` |
| `bool32` | bool32 | 4 | false |
| `bool8` | bool8 | 1 | false |
| `vec2` | vec2 | 8 | `{0,0}` |
| `vec3` | vec3 | 12 | `{0,0,0}` |
| `vec4` | vec4 | 16 | `{0,0,0,0}` |
| `mat3x3` | mat3x3 | 36 | `{{1,0,0},{0,1,0},{0,0,1}}` |

### 字符串

| 类型 | marker | byteSize | 说明 |
|------|--------|----------|------|
| `str` | str | nil | 变长，read 用 self.size，write/getSize 用 `#val` |
| `str8` | str | 8 | 定长8字节 |
| `str16` | str | 16 | |
| `str24` | str | 24 | |
| `str32` | str | 32 | |
| `bytes` | bytes | nil | 原始字节 |

---

## 基类体系

```lua
Section          -- 完整 RW Section (12字节头: typeID + size + version)
  ├── Struct     -- 0x01 嵌入结构体
  ├── Extension  -- 0x03 扩展列表
  └── <custom>   -- 自定义 typeID (如 0x10 = Clump, 0x14 = Atomic)
RawStruct        -- 无 Section 头的纯字段结构体 (BMP/DDS/Face)
```

### Section:define(typeID, fields)

声明式定义 RW Section。自动生成 `read`(body-only)、`write`(header+body)、`getSize`(body+12)。

```lua
Clump = Section:define(0x10, {
    { name = "struct",       type = ClumpStruct },
    { name = "frameList",    type = FrameList, count = 1 },
    { name = "geometryList", type = GeometryList, count = 1 },
    { name = "extension",    type = ClumpExtension },
})
```

typeID 不为 0x01/0x03 时自动注册到 SectionRegistry。

### Struct:define(fields)

定义嵌入结构体 (typeID=0x01)。读写 body-only，无 Section 头部。自动注册到 SectionRegistry 但按 typeID=0x01 共享分发。

```lua
GeometryStruct = Struct:define({
    { name = "faceCount",  type = uint32, sync = "faces" },
    { name = "vertexCount",type = uint32, sync = "vertices" },
    { name = "vertices",   type = vec3, count = "vertexCount", raw = true },
    { name = "faces",      type = Face, count = "faceCount", raw = true },
})
```

### RawStruct:define(fields)

非 RW 格式纯字段结构体。无 typeID，无 Section 头。`new()` 自动从类型标记填充默认值。

```lua
Face = RawStruct:define({
    { name = 1, type = uint16 },
    { name = 2, type = uint16 },
    { name = 3, type = uint16 },
    { name = 4, type = uint16 },
})
```

RawStruct 也支持嵌套 RawStruct 字段与数组（不含 Section 头），写法与普通字段一致：

```lua
Surface = RawStruct:define({
    { name = "material", type = uint8 },
    { name = "flags", type = uint8 },
})

Face = RawStruct:define({
    { name = "a", type = uint16 },
    { name = "b", type = uint16 },
    { name = "c", type = uint16 },
    { name = "surface", type = Surface },
})
```

### Extension:define(fields)

定义 Extension (0x03) 结构体。支持 `optional = true` 字段，读时 peek typeID 决定是否读取。

```lua
GeometryExtension = Extension:define({
    { name = "binMeshPLG",        type = BinMeshPLG, optional = true },
    { name = "skinPLG",           type = SkinPLG, optional = true },
    { name = "materialList",      type = MaterialList, cond = {{"size", "~=", 0}} },
    { name = "nightVertexColor",  type = NightVertexColor, optional = true },
})
```

---

## 字段属性

### name

字段名。支持字符串或数字。数字 key 存入 Lua 数组部分，内存更紧凑。

```lua
{ name = "count" }   -- self.count
{ name = 1 }          -- self[1], #self 可用, ipairs 可用
```

### type

字段类型。可以是类型标记、Struct/RawStruct 类、Section 类、或 Catalogue 分发表。

```lua
{ name = "width",  type = uint32 }              -- 标量
{ name = "color",  type = rgba }                 -- 复合
{ name = "frame",  type = Frame }                -- Section 类
{ name = "faces",  type = Face, count = "faceCount", raw = true }  -- 结构体数组
{ name = "effect", type = Effect2D.Effects }     -- Catalogue 分发
```

### count

数组长度。支持数字、字符串路径、或函数。

```lua
{ name = "vertices", type = vec3, count = "vertexCount" }  -- 路径引用
{ name = "faces",    type = Face, count = "faceCount", raw = true }
{ name = "colors",   type = rgba, count = function(self) return (self.size - 4) / 4 end }
```

### raw

数组元素跳过 Section 头部读取（body-only read/write）。用于 Struct:define 嵌入的数据数组。

```lua
{ name = "faces", type = Face, count = "faceCount", raw = true }
```

### cond

条件读取/写入。格式：`{{"fieldName", operator, value}}`。多个条件为 AND 关系。

```lua
{ name = "nodes", type = HAnimNode, count = "nodeCount",
  cond = {{"nodeCount", "~=", 0}}, raw = true }
{ name = "texture", type = Texture, cond = {{"isTextured", "==", true}} }
{ name = "_vcUnused", type = uint32, cond = {
    {"parent.parent.version", "~=", GTASA} }}
```

操作符: `==`, `~=`, `<`, `>`, `<=`, `>=`。

### sync

写时自动同步值。支持字符串路径（取 `#arr` 或 `target:getSize()`）、函数、或路径表。

```lua
-- 数组计数
{ name = "faceCount", type = uint32, sync = "faces" }

-- struct/catalogue getSize (自动识别)
{ name = "entrySize", type = uint32, sync = "effect" }

-- 函数
{ name = "vertexCount", type = uint32,
  sync = function(self) return #(self.vertices or {}) end }
```

引擎自动判断：目标有 `getSize` 方法 → 调用 `getSize()`；否则 → `#target`。

### optional

读取时 peek 下一个 typeID，匹配则读取，不匹配则跳过。

```lua
{ name = "skinPLG", type = SkinPLG, optional = true }
```

### bits

从整数字段中提取位域。`{bitName, startBit, bitLength}`。

```lua
{ name = "header", type = uint16, bits = {
    {"bTristrip", 0},           -- 1位, boolean
    {"bPosition", 1},
    {"UAddressing", 24, 4},     -- 4位, 数值
}}
```

### value

固定值字段。只写不读（跳过对应字节）。用于 reserved/magic 字段。

```lua
{ name = "magic", type = uint32, value = 0xDEADBEEF }
```

### default

覆盖类型标记的默认值。`new()` 时使用。优先级: `f.default` > `f.value` > `f.type.default`。

```lua
{ name = "color", type = rgba, default = {255, 255, 255, 255} }
{ name = "lines", type = str16, count = 4, default = {"","","",""} }
```

### byteSize

仅用于 `str`/`bytes` 类型。指定 read 时读取的字节数。不指定时 read 用 `self.size`，write/getSize 用 `#val`。

```lua
{ name = "name",     type = str }                              -- 自动
{ name = "userName", type = str, byteSize = "parent.size" }    -- 路径
{ name = "data",     type = str, byteSize = 24 }               -- 定长
```

---

## 扩展/插件系统

### registerPlugin

将 Section 子类注册到指定 Extension 容器。

```lua
SectionRegistry.registerPlugin("GeometryExtension", BinMeshPLG)
SectionRegistry.registerPlugin("MaterialExtension", ReflectionMaterial)
```

### ExtensionList

在字段定义中标记一个字段为某容器的扩展列表。读时消费 `self.size` 字节。

```lua
ClumpExtension = Extension:define({
    { name = "plugins", type = ExtensionList("GeometryExtension") },
})
```

### Catalogue / dispatch

按字段值查表分发 body 类型。用于 variant 结构（effectType → body）。

```lua
-- 定义分发表
Effect2D.Effects = Catalogue({}, "entryType", "entrySize")

-- 注册子类型
Effect2D.registerEffect(0x00, Effect2DLight)

-- 字段中使用
{ name = "effect", type = Effect2D.Effects }
```

`Catalogue(t, by, sizeFrom)`:
- `t`: 注册表 `{}`
- `by`: dispatch key 字段名
- `sizeFrom`: read 前拷贝到 `obj.size` 的字段名（供 `byteSize="size"` 的 str 字段使用）

---

## 常用模式

### 模式1: 顶层容器 (Clump, Effect2D)

```lua
Clump = Section:define(0x10, {
    { name = "struct",       type = ClumpStruct },
    { name = "frameList",    type = FrameList },
    { name = "geometryList", type = GeometryList },
    { name = "extension",    type = ClumpExtension },
})
```

### 模式2: 嵌入结构体数组 (Geometry vertices/faces)

```lua
GeometryStruct = Struct:define({
    { name = "vertexCount", type = uint32, sync = "vertices" },
    { name = "vertices",    type = vec3, count = "vertexCount", raw = true },
    { name = "faceCount",   type = uint32, sync = "faces" },
    { name = "faces",       type = Face, count = "faceCount", raw = true },
})
```

### 模式3: 条件数组 (HAnimPLG nodes)

```lua
HAnimPLG = Section:define(0x11E, {
    { name = "nodeCount", type = uint32, sync = "nodes" },
    { name = "flags",     type = uint32, cond = {{"nodeCount", "~=", 0}} },
    { name = "nodes",     type = HAnimNode, count = "nodeCount",
      cond = {{"nodeCount", "~=", 0}}, raw = true },
})
```

### 模式4: 变长 Section 体 (Frame, String)

```lua
Frame = Section:define(0x253F2FE, {
    { name = "name", type = str },  -- read 用 self.size, write/getSize 用 #name
})
```

### 模式5: 位域 (TextureStruct flags)

```lua
TextureStruct = Struct:define({
    { name = "flags", type = uint32, bits = {
        {"hasMipmaps", 19},
        {"VAddressing", 20, 4},
        {"UAddressing", 24, 4},
    }},
})
```

### 模式6: 条件结构体 (Material texture 可选)

```lua
Material = Section:define(0x07, {
    { name = "struct",  type = MaterialStruct },
    { name = "texture", type = Texture, count = 1,
      cond = {{"struct.isTextured", "==", true}} },
})
```

### 模式7: 版本相关的条件字段 (BoneMatrix VC unused)

```lua
BoneMatrix = Struct:define({
    { name = "_vcUnused", type = uint32,
      cond = {{"parent.parent.version", "~=", GTASA}} },
    { name = "m11", type = float32 }, ...
})
```

### 模式8: optional 扩展 (SkinPLG)

```lua
GeometryExtension = Extension:define({
    { name = "skinPLG", type = SkinPLG, optional = true },
})
```

### 模式9: Catalogue 分发 (Effect2D entry → body)

```lua
Effect2D.Effects = Catalogue({}, "entryType", "entrySize")

Effect2DEntry = RawStruct:define({
    { name = "position",  type = vec3 },
    { name = "entryType", type = uint32 },
    { name = "entrySize", type = uint32, sync = "effect" },
    { name = "effect",    type = Effect2D.Effects },
})

Effect2D.registerEffect(0x00, Effect2DLight)
```

### 模式10: 数字 key 数组 (Face, BoneIndices)

```lua
Face = RawStruct:define({
    { name = 1, type = uint16 },
    { name = 2, type = uint16 },
    { name = 3, type = uint16 },
    { name = 4, type = uint16 },
})
Face.V1 = 2; Face.V2 = 1; Face.V3 = 4; Face.Mat = 3
```
