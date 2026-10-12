# 加分项 B 四路并行点积

本目录在基础 Attention IP 的独立副本上实现维度方向4路并行点积，不修改 `attention_ip/rtl/attention_ip.v`。

## 优化内容

基础版使用1个 `Q×K` 乘法器和 `dot_acc`，每个 Token 需要：

```text
4 个 DOT 周期 + 1 个 NEXT 周期
```

8个 Token 共需要40周期。

并行版同时计算：

```text
Q[0]×K[token][0]
Q[1]×K[token][1]
Q[2]×K[token][2]
Q[3]×K[token][3]
```

四个乘积通过两级加法树得到 Score，每个 Token 只需要1个 DOT 周期。`NEXT` 状态编码仍保留以便对照波形，但正常数据流不再进入该状态。

## 周期对比

以下周期均假设输入连续有效，不插入空拍；总周期从 `start` 被接受后开始计算，不包含 IDLE 等待时间。

| 项目 | 基础版 | 4路并行版 | 变化 |
|---|---:|---:|---:|
| DOT 与 NEXT | 40 | 8 | 减少32周期 |
| 计算阶段 | 71 | 39 | 减少45.07% |
| start 后总周期 | 107 | 75 | 减少29.91% |
| 总延时加速比 | 1.00 | 1.43 | 提升1.43倍 |

Testbench 从最后一组 K/V 被接收后开始计数，到最后一个输出 `done` 为止。4组测试均实测 `COMPUTE_CYCLES=39`；两组不插输入空拍的测试均实测 `TOTAL_CYCLES=75`。

## 结构资源代价

| 结构 | 基础版 | 4路并行版 | 变化 |
|---|---:|---:|---:|
| Q×K 乘法器 | 1 | 4 | 增加3个 |
| RTL乘法运算符总数 | 5 | 8 | 增加3个 |
| 点积加法结构 | 1个累加器 | 3个加法器组成两级树 | 并行增加 |
| `dot_acc` | 18位寄存器 | 无 | 删除 |
| `cnt_dim` | 2位计数器 | 无 | 删除 |
| 同周期 K 读取 | 1项 | 4项 | 读带宽提高4倍 |

以上是根据 RTL 运算符和寄存器得到的结构对比，不是综合后的 LUT、寄存器、DSP、最高频率或功耗测量值。并行版的关键组合路径包含一个乘法器和两级加法树，最高频率需要综合与静态时序分析后确认。

## 独立验证

并行版继续使用基础版的4组测试：

1. 相同 Score 与正负0.5舍入；
2. 全部指数 LUT 档位；
3. 8位有符号极值；
4. 固定随机输入。

Testbench 同时检查：

- 4个最终输出与基础版期望值一致；
- 每组计算阶段均为39周期；
- RTL 与 testbench 编译错误和警告均为0。

## 运行

双击无界面自检：

```text
sim\run_sim.bat
```

双击打开 ModelSim 与并行点积波形：

```text
sim\run_modelsim_gui.bat
```

也可以在本目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_sim.ps1
```

成功时显示：

```text
TESTBENCH PASS: 4 cases, 0 errors
Parallel Attention simulation PASS
```

## 文件结构

```text
parallel/
├─ README.md                         本说明文件
├─ rtl/
│  └─ attention_ip.v                 4路并行点积 RTL
├─ sim/
│  ├─ tb_attention_ip.v              4组独立自检 testbench
│  ├─ run_sim.bat                    双击运行无界面自检仿真
│  ├─ run_modelsim_gui.bat           双击打开 ModelSim 与波形
│  ├─ run_sim.ps1                    编译、仿真及结果归档脚本
│  ├─ run.do                         ModelSim 无界面仿真命令
│  └─ wave_gui.do                    4路乘积及加法树波形配置
├─ model/
│  ├─ golden_model.py                基础 Attention 参考模型
│  ├─ gen_exp_lut.py                 指数 LUT 生成脚本
│  ├─ exp_lut_q1_4.csv               Q1.4 指数 LUT 数据
│  ├─ run_golden_cases.bat           一键运行4组 Golden Model 用例
│  ├─ show_tb_cases.py               显示与 testbench 对应的用例数据
│  └─ cases/
│     ├─ README.md                   测试用例说明
│     ├─ case1_equal_scores.json
│     ├─ case2_lut_levels.json
│     ├─ case3_signed_extremes.json
│     └─ case4_random_seed3.json
└─ results/
   ├─ logs/
   │  ├─ compile.log                 RTL 与 testbench 编译日志
   │  ├─ simulation.log              ModelSim 仿真日志
   │  ├─ lut_generation.log          指数 LUT 生成日志
   │  ├─ cycle_resource_comparison.md 周期与结构资源对比
   │  └─ golden_cases/               4组 Golden Model 结果 JSON
   └─ screenhots/                    当前目录名；保存并行 DOT 波形截图
```

`wave_gui.do` 已加入4路乘积、两组部分和与最终并行点积结果。
