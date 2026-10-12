# 加分项 A 因果 Mask Attention

本目录在基础 Attention IP 的独立副本上实现因果 Mask。
## 功能定义

新增输入端口：

```verilog
input [2:0] query_index;
```

`query_index` 表示当前 Query 在长度为8的序列中的位置 `i`。当 Key 下标 `j>i` 时，该 Key 被屏蔽：

```text
j <= i：正常参与 x_max、指数权重、L 和 ACC
j >  i：不参与 x_max，Weight 强制为 0
```

模块在 `IDLE` 状态接受 `start` 时锁存 `query_index`，因此任务运行期间输入端口可以变化而不会影响本次计算。

## 为什么同时修改 MAX 和 EXP

只在 EXP 阶段将未来 Weight 清零并不正确。如果被屏蔽 Key 的 Score 更大，它仍会成为 `x_max`，使允许区间的 `score-x_max` 过小并量化为0。

本实现采用两层保护：

1. MAX 阶段只比较 `score_buf[0:query_index]`；
2. EXP 阶段对 `cnt_exp>query_index` 的 Weight 强制写0。

这等价于在 Softmax 前把未来位置的 Score 设为负无穷，但避免在定点 RTL 中构造特殊的负无穷编码。

## 独立测试

`sim/tb_attention_ip.v` 包含4组定向测试：

1. `i=0`，未来 Key 的 Score 全部更大，检查未来项不参与 MAX；
2. `i=3`，未来四项是全局最大 Score，检查 `x_max` 仍来自可见区间；
3. `i=3` 且全部 Score 相同，检查只平均前4个 V；
4. `i=7`，没有未来 Key，检查与基础版本行为兼容。

Testbench 除比较4个最终输出外，还直接检查：

- `x_max` 是否来自允许区间；
- 所有 `j>i` 的 `weight_buf[j]` 是否为0。

## 一键仿真

双击 `sim/run_modelsim_gui.bat` 可以打开 GUI。

双击 `run_golden_cases.bat` 可以进行Golden model层面的验证

## 文件结构

```text
cause_effect_mask/
├─ README.md                         本说明文件
├─ rtl/
│  └─ attention_ip.v                 因果 Mask RTL
├─ sim/
│  ├─ tb_attention_ip.v              4组 Mask 独立自检 testbench
│  ├─ run_sim.bat                    双击运行无界面自检仿真
│  ├─ run_modelsim_gui.bat           双击打开 ModelSim 与波形
│  ├─ run_sim.ps1                    编译、仿真及结果归档脚本
│  ├─ run.do                         ModelSim 无界面仿真命令
│  └─ wave_gui.do                    ModelSim GUI 波形配置
├─ model/
│  ├─ golden_model.py                支持 query_index 的参考模型
│  ├─ gen_exp_lut.py                 指数 LUT 生成脚本
│  ├─ exp_lut_q1_4.csv               Q1.4 指数 LUT 数据
│  ├─ run_golden_cases.bat           一键运行4组 Golden Model 用例
│  ├─ show_tb_cases.py               显示与 testbench 对应的用例数据
│  └─ cases/
│     ├─ README.md                   测试用例说明
│     ├─ mask_case1_query0_future_max.json
│     ├─ mask_case2_query3_future_max.json
│     ├─ mask_case3_query3_equal_scores.json
│     └─ mask_case4_query7_compatible.json
└─ results/
   ├─ logs/
   │  ├─ compile.log                 RTL 与 testbench 编译日志
   │  ├─ simulation.log              ModelSim 仿真日志
   │  ├─ lut_generation.log          指数 LUT 生成日志
   │  └─ golden_cases/               4组 Golden Model 结果 JSON
   └─ screenshots/                   各状态波形及验证结果截图
```

