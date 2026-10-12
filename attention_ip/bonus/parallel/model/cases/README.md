# Testbench 用例 JSON 说明

本目录中的4个输入文件与 `sim/tb_attention_ip.v` 的4组用例逐一对应。

最简单的运行方法是双击：

```text
model\run_golden_cases.bat
```

批处理会依次运行4组用例，以分区表格显示输入矩阵、Score、delta、Weight、L、ACC和输出，并刷新 `results/logs/golden_cases/` 下的完整结果JSON。窗口最后会暂停，不会自动关闭。

| TB编号 | 输入JSON | Python预期输出 |
|---:|---|---|
| 1 | `case1_equal_scores.json` | `[5, -5, 3, 0]` |
| 2 | `case2_lut_levels.json` | `[1, 6, 2, -1]` |
| 3 | `case3_signed_extremes.json` | `[-128, 127, -1, 1]` |
| 4 | `case4_random_seed3.json` | `[-7, 3, 19, 2]` |

## 在控制台查看全部阶段

在项目根目录执行：

```powershell
python .\model\golden_model.py `
  --input .\model\cases\case1_equal_scores.json
```

不指定 `--output` 时，控制台会打印：

- Q、K、V；
- 8个 Score；
- `x_max`；
- 8个 delta；
- 8个 Weight 编码及实际定点值；
- L；
- 4路 ACC；
- 4个最终输出。

## 将全部阶段保存到 JSON

```powershell
python .\model\golden_model.py `
  --input .\model\cases\case1_equal_scores.json `
  --output .\results\logs\golden_cases\case1_equal_scores_result.json
```

指定 `--output` 后：

- 完整阶段结果写入指定JSON；
- 控制台只显示保存位置、`x_max`、L和最终输出摘要。

项目已经生成4份完整结果，位于：

```text
results/logs/golden_cases/
```

修改输入JSON后，需要重新运行 Golden Model，并将新的最终输出同步写入TB中的 `expected_output[0:3]`。
