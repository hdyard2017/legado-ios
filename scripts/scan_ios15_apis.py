#!/usr/bin/env python3
"""扫描源码中 iOS 15/16/17 才可用的 API，提前发现兼容性问题。

背景
----
Swift 编译器在 Xcode 批次模式下遇到第一个错误就停，CI 迭代极慢。
本脚本按「API 家族」全量扫描，一次列出所有高风险调用点，
可在本地（无需 Xcode）提前发现不兼容写法。

用法
----
    python3 scripts/scan_ios15_apis.py [路径...]
"""

from __future__ import annotations

import os
import re
import sys

# (家族名, 正则, 最低 iOS 版本, 建议替代)
FAMILIES: list[tuple[str, str, str, str]] = [
    # --- iOS 15 ---
    ("AsyncImage", r"\bAsyncImage\s*[({]", "15.0", "ReadingRemoteImage"),
    ("TimelineView", r"\bTimelineView\s*[({]", "15.0", "ReadingPeriodicTimeline"),
    ("Date.formatted", r"\.formatted\s*\(", "15.0", "DateFormatter 兼容扩展"),
    ("foregroundStyle", r"\.foregroundStyle\s*\(", "15.0", ".foregroundColor()"),
    ("textInputAutocapitalization", r"\.textInputAutocapitalization\s*\(", "15.0", "readingInputConfiguration"),
    ("disableAutocorrection", r"\.disableAutocorrection\s*\(", "15.0", "readingInputConfiguration"),
    ("controlSize", r"\.controlSize\s*\(", "15.0", "readingControlSize"),
    ("safeAreaInset", r"\.safeAreaInset\s*\(", "15.0", "readingSafeAreaInset"),
    ("focused", r"\.focused\s*\(", "15.0", "readingFocusBinding"),
    ("submitLabel", r"\.submitLabel\s*\(", "15.0", "readingSubmitLabel"),
    ("textSelection", r"\.textSelection\s*\(", "15.0", "readingTextSelection"),
    ("dismissEnv", r"@Environment\(\\\.dismiss\)", "15.0", "\\.readingDismiss"),
    ("interactiveDismissDisabled", r"\.interactiveDismissDisabled\s*\(", "15.0", "UIKit 方案"),
    ("Button.role", r"Button\s*\(\s*role\s*:", "15.0", ".readingRole()"),
    ("buttonStyle.bordered", r"buttonStyle\s*\(\s*\.(bordered|borderedProminent)\s*\)", "15.0", "readingButtonStyle"),
    ("Section.label", r"(?<![a-zA-Z])Section\s*\(\s*\"", "15.0", "Section { } header: { }"),
    ("Canvas", r"\bCanvas\s*[({]", "15.0", "ReadingCanvas"),
    ("swipeActions", r"\.swipeActions\s*[({]", "15.0", "readingSwipeActions"),
    ("refreshable", r"\.refreshable\s*[({]", "15.0", "readingRefreshable"),
    ("searchable", r"\.searchable\s*\(", "15.0", "readingSearchable"),
    ("task", r"\.task\s*[({]", "15.0", "readingTask"),
    ("monospacedDigit", r"\.monospacedDigit\s*\(\s*\)", "15.0", "Font.monospaced"),
    ("overlay.if", r"\.overlay\s*\(\s*if\b", "15.0", "三目 + AnyView"),
    ("listRowSeparatorTint", r"\.listRowSeparatorTint\s*\(", "15.0", "自建"),
    ("TextField.format", r"TextField\s*\([^)]*format\s*:", "15.0", "ReadingNumberField"),
    # --- iOS 15 引入、且在 iOS 14 SDK 中不存在的类型 ---
    ("DynamicTypeSize", r"\bDynamicTypeSize\b", "15.0", "自建枚举"),
    ("SubmitTriggers", r"\bSubmitTriggers\b", "15.0", "自建枚举"),
    ("EnabledTextSelectability", r"\bEnabledTextSelectability\b|\bDisabledTextSelectability\b", "15.0", "自建枚举"),
    ("GraphicsContext", r"\bGraphicsContext\b", "15.0", "ReadingCanvas"),
    ("Visibility", r"\bVisibility\b", "15.0", "自建枚举"),
    ("ButtonRole", r"\bButtonRole\b", "15.0", "自建枚举"),
    ("ControlSize", r"\bControlSize\b", "15.0", "自建枚举"),
    ("TextInputAutocapitalization", r"\bTextInputAutocapitalization\b", "15.0", "自建枚举"),
    ("Alert(iOS15)", r":\s*Alert\s*\(", "15.0", "readingAlert"),
    # --- iOS 16 ---
    ("NavigationPath", r"\bNavigationPath\b", "16.0", "自建路径容器"),
    ("NavigationStack", r"\bNavigationStack\s*[({]", "16.0", "NavigationView"),
    ("Grid", r"\bGridRow\b|\bGrid\s*[({]", "16.0", "VStack/HStack"),
    ("ViewThatFits", r"\bViewThatFits\b", "16.0", "自建"),
    ("presentationDetents", r"\.presentationDetents\s*\(", "16.0", "自建"),
    ("ShareLink", r"\bShareLink\s*[({]", "16.0", "UIActivityViewController"),
    ("scrollDisabled", r"\.scrollDisabled\s*\(", "16.0", "自建"),
    ("toolbarBackground", r"\.toolbarBackground\s*\(", "16.0", "自建"),
    ("LabeledContent", r"\bLabeledContent\s*[({]", "16.0", "自建"),
    ("Gauge", r"\bGauge\s*[({]", "16.0", "ProgressView"),
    ("fontWeight", r"\.fontWeight\s*\(", "16.0", ".font(.bold)"),
    ("contentTransition", r"\.contentTransition\s*\(", "16.0", "自建"),
    ("tint", r"\.tint\s*\(", "16.0", "readingTint"),
    ("scrollIndicators", r"\.scrollIndicators\s*\(", "16.0", "自建"),
    # --- iOS 15 起 Color 才有的绘制方法 ---
    # 注意：Color.primary / Color.secondary 作为「静态成员」是 iOS 13 就有的，
    # 单独使用没问题；出问题的是链式调用（.secondary.opacity(...)）——
    # 那会让类型检查器解析到 iOS 15 的 ShapeStyle 扩展。
    ("Color.staticChained", r"(?<![.\w])\.(primary|secondary|tertiary)\s*\.\s*(opacity|blendMode|gradient)\s*\(", "15.0", "显式写成 Color.readingSecondary 等"),
    # ShapeStyle 的 iOS 15 静态成员：.background / .quaternary
    # 注意区分上下文——foregroundColor(.secondary) 是 Color? 参数（iOS13+ 合法），
    # 而 fill(.background) 是 ShapeStyle 上下文（iOS15+ 才有 .background 成员）。
    ("ShapeStyle.static", r"(\.fill|\.stroke)\s*\(\s*\.(background|quaternary)\b", "15.0", "Color(UIColor.systemBackground)"),
    ("Color.setFill", r"\.setFill\s*\(\s*\)", "15.0", "Color.readingSetFill()"),
    ("Color.setStroke", r"\.setStroke\s*\(\s*\)", "15.0", "Color.readingSetStroke()"),
    ("foregroundColor2", r"\.foregroundColor\s*\([^()]*?,[^()]*?\)", "15.0", "单色 + symbolRenderingMode"),
    ("symbolRenderingMode", r"\.symbolRenderingMode\s*\(", "15.0", "ReadingPaletteSymbol"),
    # --- iOS 17 ---
    ("scrollTargetBehavior", r"\.scrollTargetBehavior\s*\(", "17.0", "自建"),
    ("scrollPosition", r"\.scrollPosition\s*\(", "17.0", "自建"),
    ("inspector", r"\.inspector\s*\(", "17.0", "自建"),
    ("symbolEffect", r"\.symbolEffect\s*\(", "17.0", "自建"),
]

# 兼容层自建的替代类型：命中这些名字属于正常，不算残留。
ALLOWED_TYPES = {
    "ReadingRemoteImage", "ReadingPeriodicTimeline", "ReadingCanvas", "ReadingMaterial",
    "ReadingNavigationStack", "ReadingLabeledContent", "ReadingUnavailableView",
    "ReadingNumberField", "ReadingTitleVisibility", "ReadingButtonRole",
    "ReadingButtonStyle", "ReadingControlSize", "ReadingTextAutocapitalization",
    "ReadingRemoteImagePhase", "ReadingTimelineSchedule", "ReadingTimelineTicker",
    "ReadingMaterialBackground",
}

# 兼容层文件本身可以使用新 API（内部有 #available 守卫）。
COMPAT_FILES = {"App/Compatibility.swift"}


def strip_comments(line: str) -> str:
    """去掉行尾注释，避免文档注释里的 API 名造成误报。"""
    result = []
    in_string = False
    prev = ""
    for ch in line:
        if ch == '"' and prev != "\\":
            in_string = not in_string
        if not in_string and ch == "/" and not result:
            break
        result.append(ch)
        prev = ch
    return "".join(result)


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

    hits: dict[str, list[tuple[str, int, str]]] = {}

    for path in files:
        if os.path.normpath(path) in COMPAT_FILES:
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            for lineno, raw in enumerate(handle, 1):
                line = raw.strip()
                if line.startswith("//") or line.startswith("*") or line.startswith("///"):
                    continue
                code = strip_comments(raw)
                if not code.strip():
                    continue
                for name, pattern, ver, alt in FAMILIES:
                    for match in re.finditer(pattern, code):
                        token = match.group(0).strip().rstrip("(").rstrip("{").strip()
                        if token in ALLOWED_TYPES:
                            continue
                        # UIColor.setFill() / UIColor.setStroke() 是 UIKit 的，
                        # iOS 14 就有；只有 Color 的才是 iOS 15+。
                        if name in ("Color.setFill", "Color.setStroke"):
                            prefix = code[:match.start()].rstrip()
                            if prefix.endswith("UIColor") or ".withAlphaComponent(" in prefix[-40:]:
                                continue
                        hits.setdefault(f"{name} (iOS {ver}+)", []).append((path, lineno, alt))

    total = sum(len(v) for v in hits.values())
    if not hits:
        print("✅ 未发现 iOS 15+ API 残留")
        return 0

    for key in sorted(hits, key=lambda k: -len(hits[k])):
        items = hits[key]
        print(f"\n## {key}  → {len(items)} 处")
        print(f"   建议替代：{items[0][2]}")
        for path, lineno, _ in items[:12]:
            print(f"   {path}:{lineno}")
        if len(items) > 12:
            print(f"   ... 另有 {len(items) - 12} 处")
    print(f"\n合计 {total} 处，{len(hits)} 个家族")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
