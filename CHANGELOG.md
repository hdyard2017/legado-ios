# 更新记录

## 0.1.9-ios14（2026-10-20）

- 最低支持版本降至 **iOS 14.0**，实测目标为 iOS 14.7.1。
- 新增 `App/Compatibility.swift` iOS 14 兼容层，替换以下 iOS 15+ API：
  - `AsyncImage` → `ReadingRemoteImage`（`URLSession` + `NSCache`，含磁盘缓存）
  - `TimelineView` → `ReadingPeriodicTimeline`（`Timer` 驱动，`.common` 模式避免滚动暂停）
  - `Date.formatted` / `Double.formatted` → `readingFormattedTime` / `readingFormattedMonthDay` /
    `readingFormattedFraction` / `readingFormattedPercent`
  - `.textInputAutocapitalization` / `.disableAutocorrection` → `.readingInputConfiguration`
  - `ProgressView.controlSize` → `.readingControlSize`
- 规则编辑器工具栏改用 target-action，移除 iOS 16 才有的
  `UIBarButtonItem(_:primaryAction:)` 与 `UIAction`。
- 5 处 `.background {}` 闭包重载改为 iOS 14 原生的 `.background(_:)`。
- 依赖确认：SwiftSoup 2.13.5（iOS 13+）、Kanna 6.1.0（iOS 13+）均已支持 iOS 14。

## 0.1.9（2026-10-14）

- 个人中心采用阅读静物头图、暖白圆角卡片和黑金双色图标，适配深色模式。
- 应用版本为 `0.1.9`，首次公开安装包构建号为 `13`。
- 提供未签名 IPA 和 SHA-256 校验文件，通过 GitHub Releases 下载后自行签名安装。
- 最低支持版本降至 iOS 15.0，适配导航、分享、二维码导入、阅读器及系统 API。
- 应用展示名称统一为「小浣熊阅读」，更新「我的」与「关于」页面的品牌、开发者与项目入口。
- 添加 IPA 自签安装说明、应用截图、开源许可与贡献指南。
- 提供本地无签名模拟器构建与自动测试脚本。

支持 iOS / iPadOS 15.0 及以上。暂不上架 App Store，也不提供 TestFlight。书源兼容仍在完善，复杂 JavaScript、登录、验证码和 WebView 规则可能存在平台差异。
