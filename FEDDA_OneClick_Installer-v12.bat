@echo off
setlocal EnableExtensions
title FEDDA v12 - One Click Installer

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "INSTALL_SCRIPT=%ROOT%\scripts\install_base.ps1"

echo.
echo  =============================================================
echo   FEDDA v12 - One Click Installer
echo  =============================================================
echo.

where git >nul 2>nul || goto :err_git
where node >nul 2>nul || goto :err_node
where npm >nul 2>nul || goto :err_npm
if not exist "%INSTALL_SCRIPT%" goto :err_install_script

echo  [INFO] Installing base ComfyUI + base nodes...
powershell -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%"
if not "%ERRORLEVEL%"=="0" goto :err_base_install

echo  [OK] Installer finished.
echo.
echo  Next:
echo   1) Run: %ROOT%\FEDDA_run-v12.bat
echo   2) Open: http://localhost:5173
echo.
pause
exit /b 0

:err_git
echo  [ERROR] Git not found. Install: https://git-scm.com/downloads
pause
exit /b 1

:err_node
echo  [ERROR] Node.js not found. Install Node.js 18+ from https://nodejs.org/
pause
exit /b 1

:err_npm
echo  [ERROR] npm not found. Reinstall Node.js.
pause
exit /b 1

:err_install_script
echo  [ERROR] scripts\install_base.ps1 not found.
pause
exit /b 1

:err_base_install
echo  [ERROR] Base install failed.
pause
exit /b 1
