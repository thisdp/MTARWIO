-- math3d.lua — 3D 数学工具

local cos, sin, atan2 = math.cos, math.sin, math.atan2
local Rad2Deg = 57.29577951308238
local Deg2Rad = 0.0174532925199433

local M = {}

-- 3x3 矩阵乘法（修改 m1 并返回）
function M.mul(m1, m2)
    local m11 = m1[1][1] * m2[1][1] + m1[1][2] * m2[2][1] + m1[1][3] * m2[3][1]
    local m12 = m1[1][1] * m2[1][2] + m1[1][2] * m2[2][2] + m1[1][3] * m2[3][2]
    local m13 = m1[1][1] * m2[1][3] + m1[1][2] * m2[2][3] + m1[1][3] * m2[3][3]
    local m21 = m1[2][1] * m2[1][1] + m1[2][2] * m2[2][1] + m1[2][3] * m2[3][1]
    local m22 = m1[2][1] * m2[1][2] + m1[2][2] * m2[2][2] + m1[2][3] * m2[3][2]
    local m23 = m1[2][1] * m2[1][3] + m1[2][2] * m2[2][3] + m1[2][3] * m2[3][3]
    local m31 = m1[3][1] * m2[1][1] + m1[3][2] * m2[2][1] + m1[3][3] * m2[3][1]
    local m32 = m1[3][1] * m2[1][2] + m1[3][2] * m2[2][2] + m1[3][3] * m2[3][2]
    local m33 = m1[3][1] * m2[1][3] + m1[3][2] * m2[2][3] + m1[3][3] * m2[3][3]
    m1[1][1], m1[1][2], m1[1][3] = m11, m12, m13
    m1[2][1], m1[2][2], m1[2][3] = m21, m22, m23
    m1[3][1], m1[3][2], m1[3][3] = m31, m32, m33
    return m1
end

-- 欧拉角 → 旋转矩阵 (ZYX 顺序)
function M.eulerToRotationMatrix(rx, ry, rz)
    rx, ry, rz = rx * Deg2Rad, ry * Deg2Rad, rz * Deg2Rad
    local cX, sX = cos(rx), sin(rx)
    local cY, sY = cos(ry), sin(ry)
    local cZ, sZ = cos(rz), sin(rz)
    local m = {
        { cY * cZ, cZ * sX * sY - cX * sZ, cX * cZ * sY + sX * sZ },
        { cY * sZ, cX * cZ + sX * sY * sZ, -cZ * sX + cX * sY * sZ },
        { -sY, cY * sX, cX * cY },
    }
    return m
end

-- 旋转矩阵 → 欧拉角
function M.rotationMatrixToEuler(m)
    local cY = (m[1][1] * m[1][1] + m[2][1] * m[2][1]) ^ 0.5
    local x, y, z
    if cY >= 1e-6 then
        x = atan2(m[3][2], m[3][3])
        y = atan2(-m[3][1], cY)
        z = atan2(m[2][1], m[1][1])
    else
        x = atan2(-m[2][3], m[2][2])
        y = atan2(-m[3][1], cY)
        z = 0
    end
    return x * Rad2Deg, y * Rad2Deg, z * Rad2Deg
end

math3d = M
