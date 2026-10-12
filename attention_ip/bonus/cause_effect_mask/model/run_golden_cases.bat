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

call :run_case 1 "mask_case1_query0_future_max.json" "mask_case1_query0_future_max_result.json" "Query 0 masks all future keys"
if errorlevel 1 goto :failed

call :run_case 2 "mask_case2_query3_future_max.json" "mask_case2_query3_future_max_result.json" "Future maximum is excluded"
if errorlevel 1 goto :failed

call :run_case 3 "mask_case3_query3_equal_scores.json" "mask_case3_query3_equal_scores_result.json" "Equal scores with causal mask"
if errorlevel 1 goto :failed

call :run_case 4 "mask_case4_query7_compatible.json" "mask_case4_query7_compatible_result.json" "Last query matches base behavior"
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
