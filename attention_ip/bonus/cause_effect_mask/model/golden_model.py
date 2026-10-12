#!/usr/bin/env python3
"""固定规模 S=8、d=4 因果 Mask Attention RTL 的位精确黄金参考模型。"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path
from typing import Any


S = 8
D = 4


def exp_lut(delta: int) -> int:
    """返回与 RTL 一致的 exp(delta) 无符号 Q1.4 编码。"""
    if delta >= 0:
        return 16
    if delta == -1:
        return 6
    if delta == -2:
        return 2
    if delta == -3:
        return 1
    return 0


def trunc_div(numerator: int, denominator: int) -> int:
    """执行向零截断的有符号整数除法，与 Verilog 行为一致。"""
    quotient = abs(numerator) // denominator
    return -quotient if numerator < 0 else quotient


def round_div(numerator: int, denominator: int) -> int:
    """实现与 attention_ip.v 中 round_div() 相同的四舍五入除法。"""
    if denominator == 0:
        return 0
    half = denominator // 2
    adjusted = numerator + half if numerator >= 0 else numerator - half
    return trunc_div(adjusted, denominator)


def validate_vector(name: str, values: list[int], length: int) -> None:
    if len(values) != length:
        raise ValueError(f"{name} 必须包含 {length} 个元素")
    for value in values:
        if not -128 <= value <= 127:
            raise ValueError(f"{name} 中的数值 {value} 超出 8 位有符号范围")


def validate_matrix(name: str, values: list[list[int]]) -> None:
    if len(values) != S:
        raise ValueError(f"{name} 必须包含 {S} 行")
    for row_index, row in enumerate(values):
        validate_vector(f"{name}[{row_index}]", row, D)


def attention_fixed(
    q: list[int],
    k: list[list[int]],
    v: list[list[int]],
    query_index: int = S - 1,
) -> dict[str, Any]:
    """执行与 RTL 完全相同的整数、定点和因果 Mask 运算。"""
    validate_vector("q", q, D)
    validate_matrix("k", k)
    validate_matrix("v", v)
    if not 0 <= query_index < S:
        raise ValueError(f"query_index 必须位于 0～{S - 1}")

    scores = [sum(q[dim] * k[token][dim] for dim in range(D)) for token in range(S)]
    masked = [token > query_index for token in range(S)]
    x_max = max(scores[: query_index + 1])
    deltas = [score - x_max for score in scores]
    weights = [
        0 if masked[token] else exp_lut(deltas[token])
        for token in range(S)
    ]
    l_sum = sum(weights)

    acc = [
        sum(weights[token] * v[token][dim] for token in range(S))
        for dim in range(D)
    ]
    output = [round_div(acc[dim], l_sum) for dim in range(D)]

    return {
        "q": q,
        "k": k,
        "v": v,
        "query_index": query_index,
        "causal_mask": masked,
        "score": scores,
        "x_max": x_max,
        "delta": deltas,
        "weight_q1_4_code": weights,
        "weight_value": [weight / 16.0 for weight in weights],
        "l_q1_4_code": l_sum,
        "acc": acc,
        "output": output,
    }


def official_example_extended() -> dict[str, Any]:
    """将官方 S=2、d=2 手算例扩展为固定 S=8、d=4 接口。"""
    q = [1, 2, 0, 0]
    k = [[0, 0, 0, 0] for _ in range(S)]
    v = [[0, 0, 0, 0] for _ in range(S)]

    k[0] = [1, 0, 0, 0]
    k[1] = [0, 1, 0, 0]
    v[0] = [4, 2, 0, 0]
    v[1] = [1, 6, 0, 0]

    for token in range(2, S):
        k[token] = [-128, -128, 0, 0]

    return {"q": q, "k": k, "v": v, "query_index": S - 1}


def random_case(rng: random.Random, full_range: bool) -> dict[str, Any]:
    if full_range:
        q_range = (-128, 127)
        k_range = (-128, 127)
        v_range = (-128, 127)
    else:
        q_range = (-4, 4)
        k_range = (-4, 4)
        v_range = (-32, 31)

    q = [rng.randint(*q_range) for _ in range(D)]
    k = [[rng.randint(*k_range) for _ in range(D)] for _ in range(S)]
    v = [[rng.randint(*v_range) for _ in range(D)] for _ in range(S)]
    return {"q": q, "k": k, "v": v}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input", type=Path, help="包含 q、k、v 的输入 JSON 文件"
    )
    parser.add_argument(
        "--output", type=Path, help="将全部计算结果写入指定 JSON 文件"
    )
    parser.add_argument(
        "--random", type=int, default=0, help="生成 N 组随机测试数据"
    )
    parser.add_argument(
        "--seed", type=int, default=0x13579BDF, help="随机数种子"
    )
    parser.add_argument(
        "--full-range", action="store_true", help="使用完整 8 位有符号范围"
    )
    parser.add_argument(
        "--query-index",
        type=int,
        help="覆盖输入文件中的 Query 位置 i，范围为 0～7",
    )
    args = parser.parse_args()

    if args.input:
        cases = [json.loads(args.input.read_text(encoding="utf-8"))]
    elif args.random:
        rng = random.Random(args.seed)
        cases = [random_case(rng, args.full_range) for _ in range(args.random)]
    else:
        cases = [official_example_extended()]

    results = []
    for case in cases:
        query_index = (
            args.query_index
            if args.query_index is not None
            else int(case.get("query_index", S - 1))
        )
        results.append(
            attention_fixed(case["q"], case["k"], case["v"], query_index)
        )
    payload: Any = results[0] if len(results) == 1 else results
    rendered = json.dumps(payload, ensure_ascii=False, indent=2)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
        print(f"黄金参考模型结果已写入：{args.output}")
    else:
        print(rendered)

    for index, result in enumerate(results, start=1):
        print(
            f"黄金参考模型用例 {index} 通过："
            f"query_index={result['query_index']}，"
            f"x_max={result['x_max']}，L={result['l_q1_4_code']}，"
            f"输出={result['output']}"
        )

    if not args.input and not args.random:
        assert results[0]["output"] == [2, 5, 0, 0]
        print("黄金参考模型自检通过：输出 = [2, 5, 0, 0]")


if __name__ == "__main__":
    main()
