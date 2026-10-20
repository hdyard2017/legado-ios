#!/usr/bin/env python3
"""扫描源码中 iOS 15/16/17 才可用的 API，提前发现兼容性问题。

Swift 编译器在 Xcode 批次模式下遇到第一个错误就停，CI 迭代极慢。
本脚本按「API 家族」全量扫描，一次列出所有高风险调用点。
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
    ("Section.label", r"Section\s*\(\s*\"", "15.0", "Section { } header: { }"),
    ("Material", r"\bMaterial\b|\.(ultraThin|thin|regular|thick)\b", "15.0", "ReadingMaterial"),
    ("Canvas", r"\bCanvas\s*[({]", "15.0", "ReadingCanvas"),
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
    ("View.onChange2", r"\.onChange\s*\(\s*of\s*:[^)]*\)\s*\{\s*\w+\s*,\s*\w+", "17.0", "单参数 onChange"),
    ("scrollTargetBehavior", r"\.scrollTargetBehavior\s*\(", "17.0", "自建"),
    ("scrollPosition", r"\.scrollPosition\s*\(", "17.0", "自建"),
    ("inspector", r"\.inspector\s*\(", "17.0", "自建"),
    ("symbolEffect", r"\.symbolEffect\s*\(", "17.0", "自建"),
    ("contentTransition", r"\.contentTransition\s*\(", "16.0", "自建"),
    ("bold on View", r"\.bold\s*\(\s*\)", "16.0", "Font.bold()"),
    ("fontWeight", r"\.fontWeight\s*\(", "16.0", ".font(.bold)"),
    ("monospacedDigit", r"\.monospacedDigit\s*\(\s*\)", "15.0", "Font.monospaced"),
    ("swipeActions", r"\.swipeActions\s*[({]", "15.0", "readingSwipeActions"),
    ("refreshable", r"\.refreshable\s*[({]", "15.0", "readingRefreshable"),
    ("searchable", r"\.searchable\s*\(", "15.0", "readingSearchable"),
    ("task", r"\.task\s*[({]", "15.0", "readingTask"),
    ("background.bar", r"\.background\s*\(\s*\.\w*bar\s*\)", "15.0", "readingMaterialBackground"),
    ("tint", r"\.tint\s*\(", "16.0", "readingTint"),
    ("overlay.if", r"\.overlay\s*\(\s*if\b", "15.0", "三目 + AnyView"),
    ("listRowSeparatorTint", r"\.listRowSeparatorTint\s*\(", "15.0", "自建"),
    ("TextField.format", r"TextField\s*\([^)]*format\s*:", "15.0", "ReadingNumberField"),
    ("DynamicTypeSize", r"\bDynamicTypeSize\b", "15.0", "自建"),
    ("SubmitTriggers", r"\bSubmitTriggers\b", "15.0", "自建"),
    ("EnabledTextSelectability", r"\bEnabledTextSelectability\b|\bDisabledTextSelectability\b", "15.0", "自建"),
    ("GraphicsContext", r"\bGraphicsContext\b", "15.0", "ReadingCanvas"),
    ("Alert(iOS15)", r":\s*Alert\s*\(", "15.0", "readingAlert"),
    ("Visibility", r"\bVisibility\b", "15.0", "自建枚举"),
    ("ButtonRole", r"\bButtonRole\b", "15.0", "自建枚举"),
    ("ControlSize", r"\bControlSize\b", "15.0", "自建枚举"),
    ("TextInputAutocapitalization", r"\bTextInputAutocapitalization\b", "15.0", "自建枚举"),
    ("UIScrollView.indicator", r"\.scrollIndicators\s*\(", "16.0", "自建"),
]


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

    compat = "App/Compatibility.swift"
    hits: dict[str, list[tuple[str, int, str]]] = {}

    for path in files:
        if os.path.abspath(path) == os.path.abspath(compat):
            continue  # 兼容层自身可以用新 API
        with open(path, encoding="utf-8", errors="replace") as handle:
            for lineno, line in enumerate(handle, 1):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("*"):
                    continue
                for name, pattern, ver, alt in FAMILIES:
                    if re.search(pattern, line):
                        hits.setdefault(f"{name} (iOS {ver}+)", []).append((path, lineno, alt))

    total = sum(len(v) for v in hits.values())
    if not hits:
        print("✅ 未发现 iOS 15+ API 残留")
        return 0

    for key in sorted(hits, key=lambda k: -len(hits[k])):
        items = hits[key]
        print(f"\n## {key}  → {len(items)} 处")
        alt = items[0][2]
        print(f"   建议替代：{alt}")
        for path, lineno, _ in items[:12]:
            print(f"   {path}:{lineno}")
        if len(items) > 12:
            print(f"   ... 另有 {len(items) - 12} 处")
    print(f"\n合计 {total} 处，{len(hits)} 个家族")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
