#!/usr/bin/env python3
"""以易读表格显示与 Testbench 对应的 Golden Model 结果。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from golden_model import attention_fixed


CASE_NAMES = {
    1: "序列首位屏蔽全部未来 Key",
    2: "未来高 Score 不参与 MAX",
    3: "相同 Score 只平均可见 Token",
    4: "序列末位与基础版本兼容",
}


def format_vector(values: list[int], width: int = 4) -> str:
    return "[" + ", ".join(f"{value:{width}d}" for value in values) + "]"


def print_title(case_id: int) -> None:
    line = "=" * 88
    print()
    print(line)
    print(f"TB 用例 {case_id}：{CASE_NAMES.get(case_id, '未命名用例')}")
    print(line)


def print_input_table(result: dict) -> None:
    print("\n一  输入数据")
    print(f"Q = {format_vector(result['q'])}")
    print(f"Query 位置 i = {result['query_index']}")
    print()
    print("Token | K 向量                    | V 向量")
    print("------|---------------------------|---------------------------")
    for token, (k_row, v_row) in enumerate(zip(result["k"], result["v"])):
        print(
            f"  {token:>2d}  | {format_vector(k_row):<25s} | "
            f"{format_vector(v_row)}"
        )


def print_softmax_table(result: dict) -> None:
    print("\n二  Score 与 Softmax 定点结果")
    print(f"x_max = {result['x_max']}")
    print()
    print("Token | Mask |    Score |    delta | Weight编码 | Weight实际值")
    print("------|------|----------|----------|------------|-------------")
    for token in range(8):
        print(
            f"  {token:>2d}  | "
            f"{'是' if result['causal_mask'][token] else '否':>4s} | "
            f"{result['score'][token]:>8d} | "
            f"{result['delta'][token]:>8d} | "
            f"{result['weight_q1_4_code'][token]:>10d} | "
            f"{result['weight_value'][token]:>11.4f}"
        )


def print_result_summary(result: dict, output_path: Path) -> None:
    print("\n三  加权累加与最终输出")
    print(f"L 的 Q1.4 编码 = {result['l_q1_4_code']}")
    print(f"ACC             = {format_vector(result['acc'], 6)}")
    print(f"最终输出 O      = {format_vector(result['output'], 4)}")
    print()
    print(f"完整结果 JSON：{output_path}")
    print("-" * 88)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case-id", type=int, required=True, help="TB 用例编号")
    parser.add_argument("--input", type=Path, required=True, help="输入 JSON")
    parser.add_argument("--output", type=Path, required=True, help="结果 JSON")
    args = parser.parse_args()

    source = json.loads(args.input.read_text(encoding="utf-8"))
    result = attention_fixed(
        source["q"],
        source["k"],
        source["v"],
        int(source["query_index"]),
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print_title(args.case_id)
    print_input_table(result)
    print_softmax_table(result)
    print_result_summary(result, args.output)


if __name__ == "__main__":
    main()
