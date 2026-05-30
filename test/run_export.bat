@echo off
cd /d "%~dp0.."
echo === TXD to PNG Export ===
echo.
lua\lua5.1.exe test\test_timed_export.lua
echo.
pause
