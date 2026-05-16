@echo off
setlocal EnableExtensions
title FEDDA v12 - One Click Installer

set "REPO_URL=https://github.com/Feddakalkun/Fedda_hub-v12.git"
set "REPO_BRANCH=main"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "BOOTSTRAP_DIR=%ROOT%\_fedda_hub_v12_repo"
set "INSTALL_ROOT=%ROOT%\comfyuifeddafront"
set "INSTALL_SCRIPT=%BOOTSTRAP_DIR%\scripts\install_base.ps1"
set "UPDATE_BAT=%ROOT%\FEDDA_Update-v12.bat"
set "RUN_BAT=%ROOT%\FEDDA_run-v12.bat"

echo.
echo  =============================================================
echo   FEDDA v12 - One Click Installer
echo   (Single-file share bootstrap)
echo  =============================================================
echo.
echo   Install folder: %INSTALL_ROOT%
echo   Bootstrap repo: %BOOTSTRAP_DIR%
echo.

where git >nul 2>nul || goto :err_git
where node >nul 2>nul || goto :err_node
where npm >nul 2>nul || goto :err_npm

if exist "%BOOTSTRAP_DIR%\.git" (
  echo  [INFO] Updating bootstrap repo...
  pushd "%BOOTSTRAP_DIR%" || goto :err_pushd
  git fetch origin %REPO_BRANCH% || goto :err_bootstrap_update
  git checkout %REPO_BRANCH% || goto :err_bootstrap_update
  git pull --ff-only origin %REPO_BRANCH% || goto :err_bootstrap_update
  popd
) else (
  echo  [INFO] Cloning bootstrap repo...
  git clone --branch %REPO_BRANCH% %REPO_URL% "%BOOTSTRAP_DIR%" || goto :err_bootstrap_clone
)

attrib +h "%BOOTSTRAP_DIR%" >nul 2>nul

if not exist "%INSTALL_SCRIPT%" goto :err_install_script

echo  [INFO] Running base installer (ComfyUI + base nodes + embedded Python)...
powershell -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%" -InstallRoot "%INSTALL_ROOT%"
if not "%ERRORLEVEL%"=="0" goto :err_base_install

echo  [INFO] Creating run/update launchers...
(
echo @echo off
echo setlocal EnableExtensions
echo set "ROOT_DIR=%%~dp0"
echo if "%%ROOT_DIR:~-1%%"=="\" set "ROOT_DIR=%%ROOT_DIR:~0,-1%%"
echo set "BOOTSTRAP_DIR=%%ROOT_DIR%%\_fedda_hub_v12_repo"
echo set "INSTALL_SCRIPT=%%BOOTSTRAP_DIR%%\scripts\install_base.ps1"
echo set "INSTALL_ROOT=%%ROOT_DIR%%\comfyuifeddafront"
echo if not exist "%%INSTALL_SCRIPT%%" ^(
echo   echo [ERROR] Missing bootstrap installer script:
echo   echo         %%INSTALL_SCRIPT%%
echo   pause
echo   exit /b 1
echo ^)
echo powershell -ExecutionPolicy Bypass -File "%%INSTALL_SCRIPT%%" -InstallRoot "%%INSTALL_ROOT%%"
echo exit /b %%ERRORLEVEL%%
) > "%UPDATE_BAT%"

(
echo @echo off
echo setlocal EnableExtensions
echo set "ROOT_DIR=%%~dp0"
echo if "%%ROOT_DIR:~-1%%"=="\" set "ROOT_DIR=%%ROOT_DIR:~0,-1%%"
echo set "FRONTEND_DIR=%%ROOT_DIR%%\_fedda_hub_v12_repo\frontend"
echo if not exist "%%FRONTEND_DIR%%\package.json" ^(
echo   echo [ERROR] Missing frontend package.json at:
echo   echo         %%FRONTEND_DIR%%
echo   pause
echo   exit /b 1
echo ^)
echo pushd "%%FRONTEND_DIR%%" ^|^| ^(
echo   echo [ERROR] Could not enter frontend folder.
echo   pause
echo   exit /b 1
echo ^)
echo call npm run dev
echo set "EXITCODE=%%ERRORLEVEL%%"
echo popd
echo exit /b %%EXITCODE%%
) > "%RUN_BAT%"

echo.
echo  [OK] Installer finished successfully.
echo.
echo  Next:
echo   1^) Run: %RUN_BAT%
echo   2^) Open: http://localhost:5173
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

:err_pushd
echo  [ERROR] Could not enter bootstrap repo folder.
pause
exit /b 1

:err_bootstrap_update
echo  [ERROR] Failed to update bootstrap repo.
popd
pause
exit /b 1

:err_bootstrap_clone
echo  [ERROR] Failed to clone bootstrap repo.
pause
exit /b 1

:err_install_script
echo  [ERROR] Missing installer script:
echo          %INSTALL_SCRIPT%
pause
exit /b 1

:err_base_install
echo  [ERROR] Base install failed.
pause
exit /b 1
