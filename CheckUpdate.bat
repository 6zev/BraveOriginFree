@echo off
title Brave Origin Free - Update
color 0B
setlocal

set "APP_DIR=%~dp0"

echo.
echo  ============================================
echo     Brave Origin Free - Update
echo  ============================================
echo.

REM One click: check and install the newest Brave Origin build automatically.
powershell -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%src\update.ps1"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo  Update finished.
) else (
    echo  Update did not complete. Exit code: %RC%
)
echo.
pause
exit /b %RC%
