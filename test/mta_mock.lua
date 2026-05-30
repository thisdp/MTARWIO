-- mta_mock.lua — MTA 文件函数模拟（用于 standalone Lua 5.1 测试）

local io_open = io.open
local io_lines = io.lines

-- 文件存在检查
function fileExists(path)
    local f = io_open(path, "rb")
    if f then f:close(); return true end
    return false
end

-- 打开文件
function fileOpen(path, readonly)
    local mode = "rb"
    if readonly == false then mode = "wb" end
    return io_open(path, mode)
end

-- 读取指定字节数
function fileRead(f, count)
    if not f then return nil end
    return f:read(count)
end

-- 获取文件大小
function fileGetSize(f)
    if not f then return 0 end
    local pos = f:seek()
    local size = f:seek("end")
    f:seek("set", pos)
    return size
end

-- 关闭文件
function fileClose(f)
    if f then f:close() end
end

-- 创建文件用于写入
function fileCreate(path)
    return io_open(path, "wb")
end

-- 写入文件
function fileWrite(f, str)
    if f then f:write(str) end
end

-- 删除文件
function fileDelete(path)
    os.remove(path)
end

-- 设置文件位置
function fileSetPos(f, offset)
    if f then f:seek("set", offset) end
end

-- MTA 类型判断 (standalone 中所有 userdata 视为 Vector)
function getUserdataType(ud)
    if type(ud) == "table" then return "table" end
    return "unknown"
end

-- MTA debug 函数
function iprint(...)
    local args = {...}
    for i = 1, #args do
        io.write(tostring(args[i]))
        if i < #args then io.write("\t") end
    end
    io.write("\n")
end

print("[MTA Mock] Standard Lua I/O functions ready")
