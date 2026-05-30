-- tableutil.lua — 表工具（深拷贝等）

tableUtil = {}

-- 深拷贝（处理 parent 引用循环）
function tableUtil.deepCopy(obj, newParent)
    local function copy(o)
        if type(o) ~= "table" then return o end
        local t = {}
        for k, v in pairs(o) do
            if k == "parent" then
                t[k] = newParent
            else
                t[copy(k)] = copy(v)
            end
        end
        return setmetatable(t, getmetatable(o))
    end
    return copy(obj)
end

-- 浅拷贝
function tableUtil.shallowCopy(t)
    local r = {}
    for k, v in pairs(t) do r[k] = v end
    return r
end

-- 合并表 (t2 → t1, 排除某些键)
function tableUtil.assimilate(t1, t2, except)
    if not t1 or not t2 then return end
    local ex = {}
    if type(except) == "table" then
        for i = 1, #except do ex[except[i]] = true end
    end
    for k, v in pairs(t2) do
        if not ex[k] then t1[k] = v end
    end
end
