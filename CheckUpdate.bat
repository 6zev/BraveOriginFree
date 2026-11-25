@echo off
title Brave Origin Free - Check for Updates
color 0B
setlocal

set "APP_DIR=%~dp0"

echo.
echo  ============================================
echo     Brave Origin Free - Update
echo  ============================================
echo.
echo   [1] Check only (no download)
echo   [2] Check and install update
echo.
choice /C 12 /N /M " Choose [1/2]: "
if errorlevel 2 goto :update
if errorlevel 1 goto :check

:check
powershell -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%src\update.ps1" -CheckOnly
echo.
pause
exit /b 0

:update
powershell -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%src\update.ps1"
echo.
pause
exit /b 0
