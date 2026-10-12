@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "SIM_DIR=%~dp0"
set "PROJECT_DIR=%SIM_DIR%.."
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%PS_EXE%" (
    echo [ERROR] Windows PowerShell was not found.
    pause
    exit /b 1
)

pushd "%PROJECT_DIR%" || (
    echo [ERROR] Cannot enter project directory: %PROJECT_DIR%
    pause
    exit /b 1
)

echo Running Parallel Attention batch simulation...
echo.

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SIM_DIR%run_sim.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

popd
echo.
if "%EXIT_CODE%"=="0" (
    echo Simulation completed successfully.
) else (
    echo [ERROR] Simulation failed with exit code %EXIT_CODE%.
)

pause
exit /b %EXIT_CODE%
