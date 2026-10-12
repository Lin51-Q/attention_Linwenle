#!/usr/bin/env python3
"""生成并验证 RTL 使用的 Q1.4 指数查找表。"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def quantize_q1_4(delta: int) -> int:
    return int(math.floor(math.exp(delta) * 16.0 + 0.5))


def rtl_lut(delta: int) -> int:
    if delta >= 0:
        return 16
    if delta == -1:
        return 6
    if delta == -2:
        return 2
    if delta == -3:
        return 1
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).with_name("exp_lut_q1_4.csv"),
        help="生成的 CSV 文件路径",
    )
    parser.add_argument(
        "--min-delta", type=int, default=-16, help="需要生成的最小 delta"
    )
    args = parser.parse_args()

    rows: list[tuple[int, float, int, int, str]] = []
    errors = 0
    for delta in range(0, args.min_delta - 1, -1):
        exact = math.exp(delta)
        generated = quantize_q1_4(delta)
        rtl = rtl_lut(delta)
        status = "通过" if generated == rtl else "不匹配"
        errors += generated != rtl
        rows.append((delta, exact, generated, rtl, status))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.writer(stream)
        writer.writerow(
            [
                "差值delta",
                "指数精确值exp(delta)",
                "生成的Q1.4编码",
                "RTL中的编码",
                "核对结果",
            ]
        )
        for delta, exact, generated, rtl, status in rows:
            writer.writerow([delta, f"{exact:.10f}", generated, rtl, status])

    for delta, exact, generated, rtl, status in rows:
        print(
            f"差值={delta:3d}，指数值={exact:.10f}，"
            f"生成编码={generated:2d}，RTL编码={rtl:2d}，{status}"
        )

    if errors:
        raise SystemExit(f"LUT 验证失败：发现 {errors} 个不匹配项")
    print(f"LUT 验证通过：共核对 {len(rows)} 个表项")


if __name__ == "__main__":
    main()
