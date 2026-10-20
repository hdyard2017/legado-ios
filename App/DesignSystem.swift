import SwiftUI

struct ReadingUnavailableView<Label: View, Description: View, Actions: View>: View {
    private let label: Label
    private let description: Description
    private let actions: Actions

    init(
        @ViewBuilder label: () -> Label,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        if #available(iOS 17.0, *), !ReadingCompatibility.usesLegacyUI {
            ContentUnavailableView {
                label
            } description: {
                description
            } actions: {
                actions
            }
        } else {
            VStack(spacing: 12) {
                label.labelStyle(ReadingUnavailableLabelStyle())
                description
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                actions.padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension ReadingUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.init {
            SwiftUI.Label(title, systemImage: systemImage)
        } description: {
            description
        } actions: {
            EmptyView()
        }
    }

    @ViewBuilder
    static func search(text: String) -> some View {
        if #available(iOS 17.0, *), !ReadingCompatibility.usesLegacyUI {
            ContentUnavailableView.search(text: text)
        } else {
            ReadingUnavailableView(
                "无搜索结果",
                systemImage: "magnifyingglass",
                description: Text("没有找到与“\(text)”相关的内容，请尝试其他关键词。")
            )
        }
    }
}

private struct ReadingUnavailableLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 12) {
            configuration.icon
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            configuration.title.font(.title2.bold())
        }
    }
}

extension View {
    func readingSearchable(text: Binding<String>, isPresented: Binding<Bool>, prompt: String) -> some View {
        modifier(ReadingSearchModifier(text: text, isPresented: isPresented, prompt: prompt))
    }

    @ViewBuilder
    func readingListTopMargin(_ margin: CGFloat) -> some View {
        if #available(iOS 17.0, *), !ReadingCompatibility.usesLegacyUI {
            contentMargins(.top, margin, for: .scrollContent)
        } else {
            self
        }
    }
}

private struct ReadingSearchModifier: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: String
    /// iOS 14 没有 SwiftUI 焦点系统，这里只表示「搜索框已激活」，
    /// 用于决定是否显示取消按钮；真正的键盘焦点交给系统默认行为。
    @State private var isFocused: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), !ReadingCompatibility.usesLegacyUI {
            content.searchable(text: $text, isPresented: $isPresented, prompt: prompt)
        } else {
            content
                .readingSafeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                            TextField(prompt, text: $text)
                                .onAppear { isFocused = true }
                                .readingInputConfiguration(autocapitalization: .never, disableAutocorrection: true)
                                .readingSubmitLabel(.search)
                            if !text.isEmpty {
                                Button {
                                    text = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .accessibilityLabel("清除搜索")
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ReadingTheme.groupedCanvas))
                        if isFocused {
                            Button("取消") {
                                text = ""
                                isFocused = false
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ReadingTheme.canvas)
                }
                .onAppear { isFocused = isPresented }
                .onChange(of: isPresented) { isFocused = $0 }
                .onChange(of: isFocused) { isPresented = $0 }
        }
    }
}

enum ReadingTheme {
    static let accent = adaptive(0x171717, dark: 0xF2F2F2)
    static let accentSoft = adaptive(0xEEEEEF, dark: 0x29292C)
    static let coral = Color(red: 0.76, green: 0.48, blue: 0.27)
    static let paper = Color(red: 0.965, green: 0.945, blue: 0.895)
    static let ink = Color.primary
    static let canvas = adaptive(0xFCFCFC, dark: 0x111113)
    static let groupedCanvas = adaptive(0xF3F3F4, dark: 0x1C1C1F)
    static let surface = adaptive(0xFFFFFF, dark: 0x232326)
    static let separator = adaptive(0xE6E6E8, dark: 0x363639)
    static let onAccent = adaptive(0xFFFFFF, dark: 0x171717)

    private static func adaptive(_ light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

struct ReadingPageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundColor(ReadingTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: 10) { actions }
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 28)
    }
}

struct ReadingToolbarIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .regular))
            .foregroundColor(ReadingTheme.accent)
            .frame(width: 44, height: 44)
            .background(Circle().fill(ReadingTheme.groupedCanvas))
            .accessibilityHidden(true)
    }
}

enum BookReadingPresentation {
    static func hasStarted(_ book: Book) -> Bool {
        book.durChapterIndex > 0 || book.durChapterPos > 0 || book.durChapterTime > 0
    }

    static func progress(_ book: Book) -> Double {
        guard hasStarted(book), book.totalChapterNum > 0 else { return 0 }
        return min(1, max(0, Double(book.durChapterIndex + 1) / Double(book.totalChapterNum)))
    }

    static func position(_ book: Book) -> String {
        if let title = book.durChapterTitle, !title.isEmpty { return title }
        guard hasStarted(book) else { return "尚未阅读" }
        return book.totalChapterNum > 0
            ? "第\(book.durChapterIndex + 1)章 · 共\(book.totalChapterNum)章"
            : "已读至第\(book.durChapterIndex + 1)章"
    }

    static func progressLabel(_ book: Book) -> String {
        guard hasStarted(book) else { return "尚未阅读" }
        guard book.totalChapterNum > 0 else { return position(book) }
        return "已读\(Int((progress(book) * 100).rounded()))%"
    }
}

struct ReadingProgressLine: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(ReadingTheme.separator)
                .overlay(
                    Capsule().fill(ReadingTheme.accent)
                        .frame(width: geometry.size.width * min(1, max(0, value)))
                , alignment: .leading)
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

struct BookCoverArtwork: View {
    let title: String
    var author: String = ""
    var remoteURL: String?
    var width: CGFloat = 68
    var height: CGFloat = 96

    private var coverStyle: Int {
        switch title {
        case "长夜里的灯": 0
        case "群星沉默时": 1
        case "山海入梦来": 2
        default: title.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 3 }
        }
    }

    private var coverColor: Color {
        switch coverStyle {
        case 1: Color(red: 0.22, green: 0.35, blue: 0.44)
        case 2: Color(red: 0.71, green: 0.44, blue: 0.34)
        default: Color(red: 0.14, green: 0.15, blue: 0.16)
        }
    }

    var body: some View {
        ReadingRemoteImage(url: remoteURL.flatMap(URL.init(string:))) { phase in
            if case .success(let image) = phase {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        } placeholder: {
            placeholder
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            Rectangle().fill(.black.opacity(0.15)).frame(width: max(2, width * 0.035))
        , alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous) .strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack(alignment: .topLeading) {
            coverColor
            ReadingCanvas { context, size in
                drawArtwork(context: context, size: size)
            }
            VStack(alignment: .leading, spacing: width * 0.10) {
                Text(coverStyle == 0 ? title.map(String.init).joined(separator: "\n") : title)
                    .font(.system(size: max(9, width * (coverStyle == 0 ? 0.16 : 0.18)), weight: .medium, design: .serif))
                    .lineLimit(coverStyle == 0 ? 7 : 4)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: coverStyle == 0 ? width * 0.32 : .infinity, alignment: .leading)
                if !author.isEmpty, width >= 50 {
                    Text(author)
                        .font(.system(size: max(7, width * 0.09)))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .foregroundColor(.white.opacity(0.94))
            .padding(width * 0.15)
            .padding(.top, coverStyle == 1 ? height * 0.33 : 0)
        }
    }

    /// 书封装饰绘制。
    ///
    /// 原实现使用 SwiftUI 的 `GraphicsContext`（iOS 15+），
    /// 这里改用 CoreGraphics，可在 iOS 14 上编译并保持相同视觉效果。
    private func drawArtwork(context ctx: CGContext, size: CGSize) {
        func fillEllipse(_ rect: CGRect, _ color: UIColor) {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: rect)
        }

        if coverStyle == 0 {
            let side = size.width * 0.17
            let moon = CGRect(x: size.width * 0.68, y: size.height * 0.18,
                              width: side, height: side)
            fillEllipse(moon, UIColor(red: 0.89, green: 0.87, blue: 0.81, alpha: 1))
        } else if coverStyle == 1 {
            let normalized: [CGPoint] = [
                .init(x: 0.12, y: 0.19), .init(x: 0.39, y: 0.11), .init(x: 0.62, y: 0.22),
                .init(x: 0.88, y: 0.13), .init(x: 0.76, y: 0.42), .init(x: 0.33, y: 0.48)
            ]
            let points = normalized.map {
                CGPoint(x: $0.x * size.width, y: $0.y * size.height)
            }
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            ctx.setLineWidth(0.6)
            ctx.move(to: points[0])
            for point in points.dropFirst() { ctx.addLine(to: point) }
            ctx.strokePath()
            for point in points {
                fillEllipse(CGRect(x: point.x, y: point.y, width: 1.5, height: 1.5),
                            UIColor.white.withAlphaComponent(0.7))
            }
        } else {
            let arch = CGRect(x: size.width * 0.28, y: size.height * 0.40,
                              width: size.width * 0.58, height: size.height * 0.48)
            let path = UIBezierPath(roundedRect: arch, cornerRadius: size.width * 0.29)
            UIColor.white.withAlphaComponent(0.25).setFill()
            path.fill()
        }

        for index in 0..<3 {
            let baseline = size.height * (0.78 + CGFloat(index) * 0.065)
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.17).cgColor)
            ctx.setLineWidth(0.7)
            ctx.move(to: CGPoint(x: 0, y: baseline))
            ctx.addCurve(
                to: CGPoint(x: size.width, y: baseline + 8),
                control1: CGPoint(x: size.width * 0.3, y: baseline + 18),
                control2: CGPoint(x: size.width * 0.6, y: baseline - 20)
            )
            ctx.strokePath()
        }
    }
}

struct ReadingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ReadingTheme.groupedCanvas))
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = ReadingTheme.accent
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundColor(color)
    }
}
