# 开发与验证

## 环境

- macOS；支持 Swift 6 的 Xcode，当前开发环境为 Xcode 26.1。
- App 最低 iOS 14.0；核心包也可在 macOS 14+ 测试。
- Swift Package Manager 依赖由 `Package.resolved` 锁定，初次解析需要网络。
- 运行脚本需 Python 3 和 `rg`（ripgrep）。

在独立仓库根目录打开 `Legado.xcodeproj`，选择 `Legado` Scheme。真机运行需要自行设置签名团队；请勿将证书或描述文件提交到仓库。

## 代码结构

| 路径 | 用途 |
| --- | --- |
| `App/` | SwiftUI 页面、UIKit 阅读器、应用入口与资源 |
| `Sources/LegadoCore/` | 书源、规则引擎、网络、持久化、搜索、阅读及 RSS 等核心逻辑 |
| `Tests/LegadoCoreTests/` | 核心行为与书源兼容测试 |
| `Tests/LegadoAppModelsTests/` | 页面模型回归 |
| `Tests/LegadoReaderTests/` | iOS 阅读器与网页桥接测试 |
| `Tests/LegadoReaderUITests/` | 模拟器 UI 与阅读链路测试 |
| `App/Resources/` | 默认 TXT 目录规则、HTTP TTS 配置和第三方许可证 |
| `scripts/` | 自检与源码导出 |

## 验证命令

```sh
swift test --disable-sandbox
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

完整本地自检：

```sh
sh scripts/self-check.sh
```

首次运行可先在 Xcode 解析包；自检的 App 构建阶段固定使用已解析依赖。可用 `LEGADO_DERIVED_DATA_PATH` 和 `LEGADO_SOURCE_PACKAGES_PATH` 指定已有缓存。

阅读器测试在 Xcode 选择 `LegadoReaderTests` / `LegadoReaderUITests` Scheme 和具体模拟器运行。联网书源测试需要显式配置对应环境变量，默认核心回归主要采用自造响应，不能将其通过解读为所有线上书源均可用。

## 兼容性验证

最低部署版本为 iOS 14.0。`App/Compatibility.swift` 为导航、分享、照片选择、弹窗、异步图片、周期刷新、日期格式化、
文本输入与控件尺寸提供兼容实现；新增系统 API 时需保留最低版本路径。调试构建可用 `-uiLegacyCompatibility` 启动参数在新系统上执行旧版界面分支，对应回归位于 `Tests/LegadoReaderUITests/`。这些测试不能替代 iOS 14 真机或模拟器实测。

搜索调度与缓存回归见 `Tests/LegadoCoreTests/SearchPerformanceTests.swift`，包括复杂书源限流和普通书源的及时执行；这些测试验证行为，不提供真实网络速度排名。

## 演示与公开截图

模拟器启动参数 `-uiDemo` 使用演示书架；`-uiDemoReader` 打开演示阅读页，`-uiDemoTab settings` 打开「我的」，`-uiDemoAbout` 打开关于页。部分演示入口仍保留 `settings` 参数名以兼容测试脚本。

提交截图前确认没有真实账号、个人书架或第三方付费正文。公开截图放在 `docs/images/`；`artifacts/`、构建缓存和原始测试日志仅供本地验证，已加入忽略清单。

## 导出源码

在多项目父仓库中开发时，可以运行以下命令导出本项目当前源码，排除父仓库历史、构建产物及签名文件：

```sh
python3 scripts/export-open-source.py /tmp/legado-ios-open-source
```

目标目录必须尚不存在。导出后检查内容，再用独立仓库管理；`.gitignore` 不会自动清理已经跟踪的文件。
