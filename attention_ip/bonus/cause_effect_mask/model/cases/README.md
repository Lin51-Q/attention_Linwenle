# 因果 Mask Testbench 用例 JSON

以下4个 JSON 与 `sim/tb_attention_ip.v` 中的定向测试一一对应。

目录中以 `case1_`～`case4_` 开头的4个文件是你复制基础版本时保留的原始用例，仅作对照；当前加分项脚本实际使用的是以 `mask_case` 开头的文件。

| TB编号 | Query位置 | 主要检查 | Python预期输出 |
|---:|---:|---|---|
| 1 | 0 | 未来 Key 的 Score 更大，但不能参与 MAX 或产生 Weight | `[11, -12, 13, -14]` |
| 2 | 3 | 未来四个 Score 远大于可见区间，`x_max` 仍应为3 | `[1, 2, 6, 0]` |
| 3 | 3 | 8个 Score 相同，只平均前4个 V | `[4, -4, 3, 0]` |
| 4 | 7 | 最后一个 Query 没有未来 Key，应兼容基础版本 | `[5, -5, 3, 0]` |

双击以下文件可显示4组 Golden Model 结果：

```text
model\run_golden_cases.bat
```

也可以在加分项根目录运行单个用例：

```powershell
python .\model\golden_model.py `
  --input .\model\cases\mask_case2_query3_future_max.json
```

输出包含 `query_index`、因果 Mask 标记、Score、`x_max`、delta、Weight、L、ACC 和最终输出。运行完整仿真脚本后，结果 JSON 会写入：

```text
results\logs\golden_cases\
```
