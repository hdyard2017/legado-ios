#!/usr/bin/env python3
"""把 readingAlert / readingConfirmationDialog 尾随闭包之后的
`message:` 参数改写为前置的 `message: <字符串表达式>`。

为什么需要
----------
1. Swift **不允许尾随闭包之后再有实参**：
       f("t") { ... } message: x     // ❌ consecutive statements on a line
       f("t", message: x) { ... }     // ✅
2. iOS 14 的 UIKit 弹窗需要确定的**字符串**正文，
   而 SwiftUI 的 `Text` 没有公开的取值接口。

本项目所有弹窗正文都是 `Text(<字符串表达式>)` 形式，
因此统一提取成字符串表达式最直接：
       message: { Text(model.errorMessage ?? "") }
   →   message: model.errorMessage ?? ""

脚本按**花括号配对**定位闭包边界（跳过字符串字面量与转义），
只做这一种确定性改写，不触碰其他内容。

用法
----
    python3 scripts/reorder_alert_args.py [路径...]
"""

from __future__ import annotations

import os
import re
import sys

# `}` 之后紧跟 `message:` 的形式
TRAILING_RE = re.compile(r"\}\s+message\s*:")


def skip_string(text: str, i: int) -> int:
    """跳过字符串字面量（含转义），返回结束后的下标。"""
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\\":
            i += 2
            continue
        if ch == '"':
            return i + 1
        i += 1
    return i


def find_top_level(text: str, start: int, stops: str) -> int:
    """从 start 起扫描，返回第一个不在括号内的 stop 字符下标。"""
    depth = 0
    i = start
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            i = skip_string(text, i)
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0 and ch in stops:
                return i
            depth -= 1
            if depth < 0:
                return -1
        elif depth == 0 and ch in stops:
            return i
        i += 1
    return -1


def match_brace_forward(text: str, start: int) -> int:
    """从 start（应在 `{` 之后）起找到与之配对的 `}` 的下标。"""
    depth = 1
    i = start
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            i = skip_string(text, i)
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def match_brace(text: str, close: int) -> int:
    """给定 `}` 的下标，向前找到与之配对的 `{` 的下标。"""
    depth = 0
    i = close
    while i >= 0:
        ch = text[i]
        if ch == '"':
            j = i - 1
            while j >= 0:
                if text[j] == '"' and (j == 0 or text[j - 1] != "\\"):
                    break
                j -= 1
            i = j - 1
            continue
        if ch == "}":
            depth += 1
        elif ch == "{":
            depth -= 1
            if depth == 0:
                return i
        i -= 1
    return -1


def extract_text_expression(segment: str) -> tuple[str, str | None] | None:
    """从 message 闭包中提取 (参数名, 表达式)。

    支持三种形态：
        { Text(X) }          → (None, "X")
        { _ in Text(X) }     → ("_", "X")
        { file in Text(X) }  → ("file", "X")
    不是上述形态则返回 None。
    """
    s = segment.strip()
    if not s.startswith("{") or not s.endswith("}"):
        return None
    inner = s[1:-1].strip()
    # 去掉可选的闭包参数
    param: str | None = None
    m = re.match(r"^(\w+)\s+in\s+(.*)$", inner, re.S)
    if m:
        param = m.group(1)
        inner = m.group(2).strip()
    if not inner.startswith("Text(") or not inner.endswith(")"):
        return None
    expr = inner[len("Text("):-1].strip()
    if not expr:
        return None
    if expr.count("(") != expr.count(")"):
        return None
    return param, expr


def process(text: str) -> tuple[str, int]:
    count = 0
    while True:
        done = True
        for match in TRAILING_RE.finditer(text):
            close = match.start()
            seg_start = match.end()
            # message 闭包的结束位置：配对的 `}`
            seg_end = match_brace_forward(text, seg_start)
            if seg_end < 0:
                continue
            segment = text[seg_start:seg_end]
            parsed = extract_text_expression(segment)
            if parsed is None:
                continue
            param, expr = parsed
            call_kw = None
            for kw in ("readingConfirmationDialog", "readingAlert"):
                idx = text.rfind(kw, max(0, seg_start - 600), seg_start)
                if idx >= 0 and (call_kw is None or idx > call_kw):
                    call_kw = idx
            if call_kw is None:
                continue
            call_open = text.find("(", call_kw)
            if call_open < 0 or call_open > seg_start:
                continue
            # 尾随闭包的 `{`：在 call_open 与 message 闭包之间，
            # 找到与 message 闭包之前那个 `}` 配对的 `{`
            close = text.rfind("}", call_open, seg_start)
            if close < 0:
                continue
            open_brace = match_brace(text, close)
            if open_brace < 0 or open_brace < call_open:
                continue
            insert_at = find_top_level(text, call_open + 1, ",")
            if insert_at < 0:
                continue
            # 生成新的 message 实参
            if param is None:
                # 纯文本正文：iOS 14 分支直接用它，避开从 Text 反推字符串
                new_arg = f"messageText: {expr}"
            else:
                # 带数据参数：用 messageView 承载视图，iOS 14 用 messageText
                new_arg = f"messageText: {{ {param} in {expr} }}"
            # 删除尾随段（含其前面的空白），保留尾随闭包的 `}`
            tail_keep = text[close:close + 1]
            new_text = (
                text[:insert_at]
                + ", " + new_arg
                + text[insert_at:close]
                + tail_keep
                + text[seg_end:]
            )
            text = new_text
            count += 1
            done = False
            break
        if done:
            break
    return text, count


def main() -> int:
    roots = sys.argv[1:] or ["App"]
    files: list[str] = []
    for root in roots:
        if os.path.isfile(root):
            files.append(root)
            continue
        for dp, _dn, fn in os.walk(root):
            for f in fn:
                if f.endswith(".swift"):
                    files.append(os.path.join(dp, f))
    files.sort()

    total = 0
    for path in files:
        if path.endswith("Compatibility.swift"):
            continue
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        if "message:" not in text:
            continue
        new_text, count = process(text)
        if count:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(new_text)
            print(f"OK({count}) {path}")
            total += count
    print(f"共改写 {total} 处")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
