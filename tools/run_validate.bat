@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo ====================================
echo   DFF Validate Test
echo   批量解析所有 DFF，验证可读性
echo ====================================
echo.
lua\lua5.1.exe tools\batch_validate.lua
echo.
echo 结果已写入 batch_result.txt
pause
