@echo off
setlocal EnableExtensions
title FEDDA v12 - Run UI

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "FRONTEND_DIR=%ROOT%\frontend"

if not exist "%FRONTEND_DIR%\package.json" (
  echo  [ERROR] frontend\package.json not found.
  pause
  exit /b 1
)

pushd "%FRONTEND_DIR%" || (
  echo  [ERROR] Could not enter frontend folder.
  pause
  exit /b 1
)

call npm run dev
set "EXITCODE=%ERRORLEVEL%"
popd
exit /b %EXITCODE%
