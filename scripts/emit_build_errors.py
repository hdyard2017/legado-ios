#!/usr/bin/env python3
"""把 xcodebuild 日志中的全部编译错误导出为 GitHub Actions annotation。

背景
----
fork 仓库没有 admin 权限，无法通过 API 读取 job 日志与 artifact，
唯一免鉴权可读的公开接口是 check-runs annotations。
但旧实现只导出第一条 `error:` 行，于是每轮 CI 只能暴露一个错误类别，
迭代速度极慢（已跑了 20+ 轮）。

本脚本一次性导出**全部**错误行：
  1. 逐条 `::error` annotation（最多 60 条），便于精确定位；
  2. 额外输出一条聚合 annotation，把所有错误拼成多行 message，
     即使 GitHub 对单步 annotation 数量有限制，也不会丢信息。

用法
----
    python3 scripts/emit_build_errors.py <log> <step_summary> <github_output>
"""

from __future__ import annotations

import os
import re
import sys

MAX_ANNOTATIONS = 60
MAX_AGGREGATE = 60
REPO_MARKERS = ("/work/", "/actions/")

# 形如：/path/to/File.swift:552:22: error: message
ERR_RE = re.compile(r"^(?P<file>[^\s:][^:]*\.swift):(?P<line>\d+)(?::(?P<col>\d+))?:\s*error:\s*(?P<msg>.*)$")
# 形如：.../File.swift: error: message（无位置）
BARE_RE = re.compile(r"^(?P<file>[^\s:][^:]*\.swift):\s*error:\s*(?P<msg>.*)$")
# 形如：error: message
GENERIC_RE = re.compile(r"^\s*(?:/[^:]+:)?\s*error:\s*(?P<msg>.+)$")

# 噪音：编译器自身的连带报错，不是真正需要修的根因。
NOISE = (
    "emit-module command failed due to signal",
    "Command SwiftCompile failed due to signal",
    "while building module",
    "failed to produce diagnostic",
)


def escape_property(value: str) -> str:
    """转义 GitHub workflow command 的属性值。"""
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_data(value: str) -> str:
    """转义 GitHub workflow command 的 message 部分（保留换行语义）。"""
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def relative_path(path: str) -> str:
    """把 runner 的绝对路径转成仓库相对路径，便于 GitHub 生成跳转链接。

    runner 上的路径形如：
        /Users/runner/work/<owner>/<repo>/App/Foo.swift
    需要剥掉 <owner>/<repo> 两段，只保留仓库内相对路径。
    """
    for marker in REPO_MARKERS:
        idx = path.find(marker)
        if idx >= 0:
            tail = path[idx + len(marker):]
            parts = tail.split("/")
            # parts[0] = owner, parts[1] = repo
            if len(parts) > 2:
                return "/".join(parts[2:])
            if len(parts) == 2:
                return parts[1]
            return parts[0]
    return path


def collect(log_path: str) -> list[tuple[str, str, str]]:
    """返回 (file, line, message) 列表，已去重且过滤噪音。"""
    if not os.path.exists(log_path):
        return []

    seen: set[tuple[str, str, str]] = set()
    errors: list[tuple[str, str, str]] = []

    with open(log_path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if "error:" not in line:
                continue
            stripped = line.strip()

            match = ERR_RE.match(stripped) or BARE_RE.match(stripped)
            if match:
                file_path = relative_path(match.group("file"))
                line_no = match.groupdict().get("line") or ""
                message = match.group("msg").strip()
            else:
                generic = GENERIC_RE.match(stripped)
                if not generic:
                    continue
                file_path, line_no = "", ""
                message = generic.group("msg").strip()

            if not message or any(marker in message for marker in NOISE):
                continue

            key = (file_path, line_no, message)
            if key in seen:
                continue
            seen.add(key)
            errors.append((file_path, line_no, message))

    return errors


def format_error(entry: tuple[str, str, str]) -> str:
    file_path, line_no, message = entry
    if file_path and line_no:
        return f"{file_path}:{line_no}: {message}"
    if file_path:
        return f"{file_path}: {message}"
    return message


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: emit_build_errors.py <log> <step_summary> <github_output>", file=sys.stderr)
        return 2

    log_path, summary_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]
    errors = collect(log_path)

    # 1) 逐条 annotation。
    for file_path, line_no, message in errors[:MAX_ANNOTATIONS]:
        attrs = []
        if file_path:
            attrs.append(f"file={escape_property(file_path)}")
        if line_no:
            attrs.append(f"line={escape_property(line_no)}")
        attrs.append("title=编译失败")
        print(f"::error {','.join(attrs)}::{escape_data(message)}")

    # 2) 聚合 annotation：把所有错误拼成多行 message，防止数量限制导致丢信息。
    if errors:
        aggregate = "\n".join(format_error(entry) for entry in errors[:MAX_AGGREGATE])
        print(f"::error title=编译失败-汇总::{escape_data(aggregate)}")

    # 写 step summary。
    try:
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.write("### 编译错误摘要\n\n")
            if errors:
                summary.write(f"共 {len(errors)} 条错误，导出 {min(len(errors), MAX_ANNOTATIONS)} 条 annotation。\n\n")
                summary.write("```\n")
                for entry in errors[:MAX_AGGREGATE]:
                    summary.write(format_error(entry) + "\n")
                summary.write("```\n")
            else:
                summary.write("未在日志中匹配到 `error:` 行。\n")
            summary.write("\n### 失败阶段\n\n```\n")
    except OSError:
        pass

    try:
        with open(log_path, encoding="utf-8", errors="replace") as handle:
            tail = handle.read()[-400000:]
        marker = "The following build commands failed"
        chunk = tail[tail.find(marker):][:1500] if marker in tail else "（无该段落）"
    except OSError:
        chunk = "（无法读取日志）"

    try:
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.write(chunk)
            summary.write("\n```\n")
    except OSError:
        pass

    first_line = format_error(errors[0]) if errors else ""
    try:
        with open(output_path, "a", encoding="utf-8") as output:
            output.write("first_error<<EOF\n")
            output.write(first_line + "\n")
            output.write("EOF\n")
            output.write(f"error_count={len(errors)}\n")
    except OSError:
        pass

    print(f"共导出 {min(len(errors), MAX_ANNOTATIONS)} 条 error annotation（总错误 {len(errors)} 条）。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
