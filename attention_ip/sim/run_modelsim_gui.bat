@echo off
setlocal

rem This batch file compiles the project, opens ModelSim GUI,
rem loads wave_gui.do, runs the simulation, and keeps the GUI open.
set "SIM_DIR=%~dp0"
set "PROJECT_DIR=%SIM_DIR%.."

pushd "%PROJECT_DIR%"

echo Starting Attention IP simulation in ModelSim GUI...
echo Close the ModelSim window when you finish checking the waveforms.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass ^
  -File "%SIM_DIR%run_sim.ps1" -Gui

set "EXIT_CODE=%ERRORLEVEL%"
popd

if not "%EXIT_CODE%"=="0" (
    echo.
    echo ModelSim launch or simulation failed. Exit code: %EXIT_CODE%
    echo Check the messages above for details.
    pause
)

exit /b %EXIT_CODE%
