@echo off
setlocal EnableExtensions
title FEDDA v12 - Update

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "INSTALL_SCRIPT=%ROOT%\scripts\install_base.ps1"
set "BOOTSTRAP_REMOTE=https://github.com/Feddakalkun/Fedda_hub-v12.git"

where git >nul 2>nul || goto :err_git

if not exist "%ROOT%\.git" (
  echo  [WARN] No git repo found in this folder. Skipping git pull.
) else (
  pushd "%ROOT%" || goto :err_pushd
  git remote set-url origin "%BOOTSTRAP_REMOTE%" >nul 2>nul
  git fetch origin main
  if not "%ERRORLEVEL%"=="0" (
    popd
    echo  [ERROR] git fetch failed.
    pause
    exit /b 1
  )
  git checkout main
  if not "%ERRORLEVEL%"=="0" (
    popd
    echo  [ERROR] git checkout main failed.
    pause
    exit /b 1
  )
  git reset --hard origin/main
  if not "%ERRORLEVEL%"=="0" (
    popd
    echo  [ERROR] git reset --hard origin/main failed.
    pause
    exit /b 1
  )
  git clean -fd
  if not "%ERRORLEVEL%"=="0" (
    popd
    echo  [ERROR] git clean failed.
    pause
    exit /b 1
  )
  popd
)

if not exist "%INSTALL_SCRIPT%" goto :err_install_script
powershell -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%"
if not "%ERRORLEVEL%"=="0" (
  echo  [ERROR] Base update install failed.
  pause
  exit /b 1
)

echo  [OK] Update complete.
pause
exit /b 0

:err_git
echo  [ERROR] Git not found.
pause
exit /b 1

:err_install_script
echo  [ERROR] scripts\install_base.ps1 not found.
pause
exit /b 1

:err_pushd
echo  [ERROR] Could not enter target folder.
pause
exit /b 1
