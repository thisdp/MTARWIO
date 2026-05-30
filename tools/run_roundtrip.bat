@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo ====================================
echo   DFF Round-Trip Test
echo   读取并保存所有 DFF，对比结构一致性
echo ====================================
echo.
lua\lua5.1.exe tools\roundtrip_test.lua
echo.
echo 结果已写入 roundtrip_result.txt
pause
