param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Gui
)

$ErrorActionPreference = "Stop"
$env:PYTHONIOENCODING = "utf-8"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$SimDir = Join-Path $ProjectRoot "sim"
$RtlFile = Join-Path $ProjectRoot "rtl\attention_ip.v"
$TbFile = Join-Path $SimDir "tb_attention_ip.v"
$WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $ProjectRoot)
$RunName = if ($Gui) {
    "causal_mask_modelsim_gui"
} else {
    "causal_mask_modelsim_batch"
}
$RunDir = Join-Path $WorkspaceRoot "tmp\$RunName"
$WorkDir = Join-Path $RunDir "work"
$ResultsDir = Join-Path $ProjectRoot "results"
$LogsDir = Join-Path $ResultsDir "logs"
$CompileLog = Join-Path $LogsDir "compile.log"
$SimulationLog = Join-Path $LogsDir "simulation.log"

foreach ($path in @($LogsDir)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

if (Test-Path -LiteralPath $RunDir) {
    $resolvedRun = [System.IO.Path]::GetFullPath($RunDir)
    $resolvedTmp = [System.IO.Path]::GetFullPath(
        (Join-Path $WorkspaceRoot "tmp")
    ) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedRun.StartsWith(
        $resolvedTmp,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove ModelSim run directory: $resolvedRun"
    }
    Remove-Item -LiteralPath $resolvedRun -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
Copy-Item -LiteralPath (Join-Path $SimDir "run.do") `
    -Destination (Join-Path $RunDir "run.do") -Force
Copy-Item -LiteralPath (Join-Path $SimDir "wave_gui.do") `
    -Destination (Join-Path $RunDir "wave_gui.do") -Force

$vlib = (Get-Command vlib.exe -ErrorAction Stop).Source
$vlog = (Get-Command vlog.exe -ErrorAction Stop).Source
$vsim = (Get-Command vsim.exe -ErrorAction Stop).Source
$python = (Get-Command python.exe -ErrorAction Stop).Source

Push-Location $RunDir
try {
    $compileOutput = New-Object System.Collections.Generic.List[string]

    $compileOutput.Add("ModelSim compile started: $(Get-Date -Format o)")
    $compileOutput.Add("RTL: rtl\attention_ip.v")
    $compileOutput.Add("TB : sim\tb_attention_ip.v")

    $vlibOutput = & $vlib work 2>&1
    $vlibExit = $LASTEXITCODE
    foreach ($line in $vlibOutput) { $compileOutput.Add([string]$line) }
    if ($vlibExit -ne 0) { throw "vlib failed with exit code $vlibExit" }

    $rtlOutput = & $vlog -work work $RtlFile 2>&1
    $rtlExit = $LASTEXITCODE
    foreach ($line in $rtlOutput) {
        $logLine = [string]$line
        if ($logLine -match '^vlog\s+-work\s+work\s+') {
            $logLine = "vlog -work work rtl\attention_ip.v"
        }
        $compileOutput.Add($logLine)
    }
    if ($rtlExit -ne 0) { throw "RTL compilation failed with exit code $rtlExit" }

    $tbOutput = & $vlog -work work $TbFile 2>&1
    $tbExit = $LASTEXITCODE
    foreach ($line in $tbOutput) {
        $logLine = [string]$line
        if ($logLine -match '^vlog\s+-work\s+work\s+') {
            $logLine = "vlog -work work sim\tb_attention_ip.v"
        }
        $compileOutput.Add($logLine)
    }
    if ($tbExit -ne 0) { throw "TB compilation failed with exit code $tbExit" }

    $compileOutput | Set-Content -LiteralPath $CompileLog -Encoding UTF8

    if ($Gui) {
        Write-Host "正在打开 ModelSim GUI。关闭GUI后脚本才会结束。" `
            -ForegroundColor Cyan
        & $vsim -gui -voptargs=+acc work.tb_attention_ip `
            -do "do wave_gui.do"
    }
    else {
        & $vsim -c -voptargs=+acc work.tb_attention_ip -do "do run.do"
    }
    $simulationExit = $LASTEXITCODE
    if ($simulationExit -ne 0) {
        throw "Simulation failed with exit code $simulationExit"
    }
}
finally {
    Pop-Location
}

if ($Gui) {
    if (Test-Path -LiteralPath $RunDir) {
        Remove-Item -LiteralPath $RunDir -Recurse -Force
    }
    Write-Host "ModelSim GUI 已关闭。" -ForegroundColor Cyan
    return
}

Copy-Item -LiteralPath (Join-Path $RunDir "simulation.log") `
    -Destination $SimulationLog -Force

if (-not (Test-Path -LiteralPath $SimulationLog)) {
    throw "Simulation log was not generated: $SimulationLog"
}

$simulationText = Get-Content -Raw -LiteralPath $SimulationLog
if ($simulationText -notmatch "TESTBENCH PASS: [0-9]+ cases, 0 errors") {
    throw "Self-checking testbench did not report PASS"
}

$lutLog = Join-Path $LogsDir "lut_generation.log"

& $python (Join-Path $ProjectRoot "model\gen_exp_lut.py") 2>&1 |
    Set-Content -LiteralPath $lutLog -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw "LUT generation failed" }

$GoldenDir = Join-Path $LogsDir "golden_cases"
New-Item -ItemType Directory -Force -Path $GoldenDir | Out-Null
$goldenCases = @(
    @("mask_case1_query0_future_max.json", "mask_case1_query0_future_max_result.json"),
    @("mask_case2_query3_future_max.json", "mask_case2_query3_future_max_result.json"),
    @("mask_case3_query3_equal_scores.json", "mask_case3_query3_equal_scores_result.json"),
    @("mask_case4_query7_compatible.json", "mask_case4_query7_compatible_result.json")
)
foreach ($case in $goldenCases) {
    $caseInput = Join-Path $ProjectRoot ("model\cases\" + $case[0])
    $caseOutput = Join-Path $GoldenDir $case[1]
    & $python (Join-Path $ProjectRoot "model\golden_model.py") `
        --input $caseInput --output $caseOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Golden Model failed: $($case[0])"
    }
}

# 删除 ASCII 临时运行目录，只保留提交材料。
if (Test-Path -LiteralPath $RunDir) {
    Remove-Item -LiteralPath $RunDir -Recurse -Force
}

Write-Host ""
Write-Host "Causal Mask Attention simulation PASS" -ForegroundColor Green
Write-Host "Compile log   : $CompileLog"
Write-Host "Simulation log: $SimulationLog"
