@echo off
setlocal

chcp 65001 >nul
set "PYTHONIOENCODING=utf-8"

set "MODEL_DIR=%~dp0"
for %%I in ("%MODEL_DIR%..") do set "PROJECT_DIR=%%~fI"
set "RESULT_DIR=%PROJECT_DIR%\results\logs\golden_cases"

where python.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] python.exe was not found in PATH.
    if not defined NO_PAUSE pause
    exit /b 1
)

if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%"

call :run_case 1 "case1_equal_scores.json" "case1_equal_scores_result.json" "Equal scores"
if errorlevel 1 goto :failed

call :run_case 2 "case2_lut_levels.json" "case2_lut_levels_result.json" "All LUT levels"
if errorlevel 1 goto :failed

call :run_case 3 "case3_signed_extremes.json" "case3_signed_extremes_result.json" "Signed extremes"
if errorlevel 1 goto :failed

call :run_case 4 "case4_random_seed3.json" "case4_random_seed3_result.json" "Fixed random seed 3"
if errorlevel 1 goto :failed

echo.
echo ============================================================
echo All 4 Golden Model cases completed successfully.
echo Result JSON directory: %RESULT_DIR%
echo ============================================================
echo.
if not defined NO_PAUSE pause
exit /b 0

:run_case
set "CASE_ID=%~1"
set "INPUT_FILE=%MODEL_DIR%cases\%~2"
set "OUTPUT_FILE=%RESULT_DIR%\%~3"
set "CASE_NAME=%~4"

python.exe "%MODEL_DIR%show_tb_cases.py" ^
  --case-id "%CASE_ID%" ^
  --input "%INPUT_FILE%" ^
  --output "%OUTPUT_FILE%"

if errorlevel 1 exit /b 1
exit /b 0

:failed
echo.
echo [ERROR] Golden Model execution failed.
if not defined NO_PAUSE pause
exit /b 1
