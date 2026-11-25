@echo off
title Brave Origin Free - Fix Shields Filter Lists
color 0B
setlocal

set "APP_DIR=%~dp0"

echo.
echo  ============================================
echo     Brave Shields - Filter List Repair
echo  ============================================
echo.
echo   [1] Diagnose (status only)
echo   [2] Fix launcher flags + diagnose
echo   [3] Full repair (clear cache so lists re-download)
echo.
choice /C 123 /N /M " Choose [1/2/3]: "
if errorlevel 3 goto :full
if errorlevel 2 goto :flags
if errorlevel 1 goto :status

:status
powershell -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%src\fix-shields.ps1" -Status
echo.
pause
exit /b 0

:flags
powershell -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%src\fix-shields.ps1" -FixFlags
echo.
pause
exit /b 0

:full
powershell -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%src\fix-shields.ps1" -FixFlags -Force
echo.
pause
exit /b 0
