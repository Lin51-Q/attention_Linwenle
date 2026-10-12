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
    "parallel_attention_modelsim_gui"
} else {
    "parallel_attention_modelsim_batch"
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
    $compileOutput.Add("RTL: $RtlFile")
    $compileOutput.Add("TB : $TbFile")

    $vlibOutput = & $vlib work 2>&1
    $vlibExit = $LASTEXITCODE
    foreach ($line in $vlibOutput) { $compileOutput.Add([string]$line) }
    if ($vlibExit -ne 0) { throw "vlib failed with exit code $vlibExit" }

    $rtlOutput = & $vlog -work work $RtlFile 2>&1
    $rtlExit = $LASTEXITCODE
    foreach ($line in $rtlOutput) { $compileOutput.Add([string]$line) }
    if ($rtlExit -ne 0) { throw "RTL compilation failed with exit code $rtlExit" }

    $tbOutput = & $vlog -work work $TbFile 2>&1
    $tbExit = $LASTEXITCODE
    foreach ($line in $tbOutput) { $compileOutput.Add([string]$line) }
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

$cycleMatches = [regex]::Matches($simulationText, "COMPUTE_CYCLES=39")
if ($cycleMatches.Count -ne 4) {
    throw "Cycle check failed: expected four COMPUTE_CYCLES=39 records"
}
$totalCycleMatches = [regex]::Matches($simulationText, "TOTAL_CYCLES=75")
if ($totalCycleMatches.Count -ne 2) {
    throw "Cycle check failed: expected two no-stall TOTAL_CYCLES=75 records"
}

$lutLog = Join-Path $LogsDir "lut_generation.log"

& $python (Join-Path $ProjectRoot "model\gen_exp_lut.py") 2>&1 |
    Set-Content -LiteralPath $lutLog -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw "LUT generation failed" }

$GoldenDir = Join-Path $LogsDir "golden_cases"
New-Item -ItemType Directory -Force -Path $GoldenDir | Out-Null
$goldenCases = @(
    @("case1_equal_scores.json", "case1_equal_scores_result.json"),
    @("case2_lut_levels.json", "case2_lut_levels_result.json"),
    @("case3_signed_extremes.json", "case3_signed_extremes_result.json"),
    @("case4_random_seed3.json", "case4_random_seed3_result.json")
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

$cycleReport = Join-Path $LogsDir "cycle_resource_comparison.md"
@"
# 加分项 B 周期与结构资源对比

## 周期

| 项目 | 基础版 | 4路并行版 | 变化 |
|---|---:|---:|---:|
| DOT 与 NEXT | 40 | 8 | 减少 32 周期 |
| 计算阶段 | 71 | 39 | 减少 45.07% |
| start 后总周期 | 107 | 75 | 减少 29.91% |
| 总延时加速比 | 1.00 | 1.43 | 提升 1.43 倍 |

计算阶段从最后一组 K/V 被接收到 done，包括 DOT、MAX、EXP、UPDATE、NORM 和 OUTPUT。Testbench 对4组用例均实测为39周期；两组无输入空拍用例从 start 后到 done 均实测为75周期。

## 结构资源代价

| 结构 | 基础版 | 4路并行版 | 变化 |
|---|---:|---:|---:|
| Q×K 乘法器 | 1 | 4 | 增加3个 |
| RTL乘法运算符总数 | 5 | 8 | 增加3个 |
| 点积加法结构 | 1个累加器 | 3个加法器组成两级树 | 并行增加 |
| dot_acc 寄存器 | 18位 | 无 | 删除18位 |
| cnt_dim 计数器 | 2位 | 无 | 删除2位 |
| 同周期 K 读取 | 1项 | 4项 | 读带宽提高4倍 |

以上是根据 RTL 运算符和寄存器得到的结构对比，不是综合后的 LUT、寄存器、DSP、最高频率或功耗测量值。4路并行版的关键组合路径包含一个乘法器和两级加法树，最高频率需要综合与静态时序分析后确认。
"@ | Set-Content -LiteralPath $cycleReport -Encoding UTF8

# 删除 ASCII 临时运行目录，只保留提交材料。
if (Test-Path -LiteralPath $RunDir) {
    Remove-Item -LiteralPath $RunDir -Recurse -Force
}

Write-Host ""
Write-Host "Parallel Attention simulation PASS" -ForegroundColor Green
Write-Host "Compile log   : $CompileLog"
Write-Host "Simulation log: $SimulationLog"
Write-Host "Cycle report  : $cycleReport"
