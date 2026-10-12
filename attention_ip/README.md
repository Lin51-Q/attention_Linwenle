# Attention 加速器 RTL IP

## 项目状态

本目录包含题目基础版本的可综合 RTL、自检式 testbench、Python Golden Model、LUT 生成工具、ModelSim 仿真脚本、验证日志，以及加分项 A、B。


## 设计规格

| 项目 | 取值 |
|---|---|
| Batch / Head | 1 / 1 |
| Token 数量 S | 8 |
| Head 维度 d | 4 |
| Q | `[1,4]`，8位有符号整数 |
| K / V | `[8,4]`，8位有符号整数 |
| O | `[1,4]`，8位有符号整数 |
| Weight | 无符号 Q1.4，RTL编码范围0～16 |
| RTL语言 | Verilog 2001 |
| 顶层模块 | `attention_ip` |

计算流程：

```text
Score = Q · K
x_max = max(Score)
Weight = exp(Score-x_max) 的 Q1.4 LUT近似
L = ΣWeight
ACC = Σ(Weight×V)
O = round(ACC/L)
```

## 文件结构

```text
attention_ip/
├─ README.md
├─ rtl/
│  └─ attention_ip.v              单模块可综合RTL
├─ sim/
│  ├─ tb_attention_ip.v           自检式testbench
│  ├─ run_modelsim_gui.bat        双击打开ModelSim与波形
│  ├─ run.do                      ModelSim批处理命令
│  ├─ wave_gui.do                 GUI波形配置与运行命令
│  └─ run_sim.ps1                 一键编译、仿真和生成日志
├─ model/
│  ├─ golden_model.py             独立定点Golden Model
│  ├─ gen_exp_lut.py              Q1.4指数LUT生成与核对
│  ├─ show_tb_cases.py             表格显示TB对应的Golden结果
│  ├─ run_golden_cases.bat         双击运行TB对应的4组Golden Model
│  ├─ cases/                       当前TB四组输入JSON及说明
│  └─ exp_lut_q1_4.csv            运行脚本后生成的LUT表
├─ results/
│  ├─ logs/
│  │  ├─ compile.log
│  │  ├─ simulation.log
│  │  ├─ golden_cases/             当前TB四组完整阶段结果
│  │  └─ lut_generation.log                   
│  └─ screenshots/                 最终运行时保存截图的位置
├─ bonus/
│  ├─ cause_effect_mask/           加分项A因果Mask及独立测试
│  └─ parallel/                    加分项B并行优化
└─ doc/
   ├─ Attention加速器汇报.pptx
   └─ Attention加速器设计报告.docx        
```

## 工具版本

本项目已使用以下环境验证：

```text
ModelSim SE-64 10.4
Python 3.10.11
Windows PowerShell 5.1
```

RTL 与 testbench 均使用 ModelSim `vlog` 编译。

## 一键运行
直接双击：

```text
sim\run_modelsim_gui.bat
```

GUI模式会自动：

1. 编译RTL和testbench；
2. 打开ModelSim图形界面；
3. 加入接口、状态机、计数器、Score、Weight、L、ACC和输出信号；
4. 执行 `run -all`；
5. testbench执行 `$finish` 后停止仿真，但不关闭GUI；
6. 执行 `wave zoom full` 显示完整波形。

PowerShell脚本会一直等待，直到你手动关闭ModelSim GUI。

## Golden Model
双击：

```text
model\run_golden_cases.bat
```

批处理会运行与TB对应的4个输入JSON，表格显示全部阶段，并把结果保存到：

```text
results\logs\golden_cases\
```

生成并验证 LUT：

```powershell
python .\model\gen_exp_lut.py
```

`golden_model.py` 输出以下数据：

- 8个 Score；
- `x_max`；
- 8个 `score-x_max`；
- 8个 Q1.4 Weight 编码及实际值；
- L；
- 4路 ACC；
- 4个最终输出。



