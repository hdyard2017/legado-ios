import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum ReadingCompatibility {
    static var usesLegacyUI: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiLegacyCompatibility")
        #else
        false
        #endif
    }
}

struct ReadingNavigationStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            NavigationStack { content }
        } else {
            NavigationView { content }.navigationViewStyle(.stack)
        }
    }
}

struct ReadingLabeledContent<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            LabeledContent(title) { content }
        } else {
            HStack {
                Text(title)
                Spacer()
                content.foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
    }
}

extension ReadingLabeledContent where Content == Text {
    init(_ title: String, value: String) {
        self.init(title) { Text(value) }
    }
}

struct ReadingTextField: View {
    let title: String
    @Binding var text: String
    var axis: Axis

    init(_ title: String, text: Binding<String>, axis: Axis) {
        self.title = title
        _text = text
        self.axis = axis
    }

    var body: some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            TextField(title, text: $text, axis: axis)
        } else if axis == .vertical {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $text).frame(minHeight: 80).accessibilityLabel(title)
            }
        } else {
            TextField(title, text: $text)
        }
    }
}

struct ReadingShareLink<Label: View>: View {
    private let items: [Any]
    private let label: Label

    init(item: String, @ViewBuilder label: () -> Label) {
        items = [item]
        self.label = label()
    }

    init(item: URL, @ViewBuilder label: () -> Label) {
        items = [item]
        self.label = label()
    }

    var body: some View {
        Button { presentShareSheet() } label: { label }
    }

    private func presentShareSheet() {
        guard var presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !(presenter is UIActivityViewController) else { return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }
}

extension ReadingShareLink where Label == SwiftUI.Label<Text, Image> {
    init(item: URL) {
        self.init(item: item) { SwiftUI.Label("分享", systemImage: "square.and.arrow.up") }
    }
}

struct ReadingPhotoPicker<Label: View>: View {
    let onData: (Data) -> Void
    let onError: (Error) -> Void
    @ViewBuilder var label: Label
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { label }
            .sheet(isPresented: $isPresented) {
                ReadingPhotoPickerController { result in
                    isPresented = false
                    guard let result else { return }
                    switch result {
                    case .success(let data): onData(data)
                    case .failure(let error): onError(error)
                    }
                }
            }
    }
}

private struct ReadingPhotoPickerController: UIViewControllerRepresentable {
    let onResult: @MainActor (Result<Data, Error>?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onResult: @MainActor (Result<Data, Error>?) -> Void

        init(onResult: @escaping @MainActor (Result<Data, Error>?) -> Void) {
            self.onResult = onResult
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { onResult(nil); return }
            let identifier = provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .image) == true
            } ?? UTType.image.identifier
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { [weak self] data, error in
                Task { @MainActor in
                    if let data { self?.onResult(.success(data)) }
                    else { self?.onResult(.failure(error ?? CocoaError(.fileReadCorruptFile))) }
                }
            }
        }
    }
}

enum ReadingSheetDetent { case medium, large }

extension View {
    @ViewBuilder
    func readingNumericTransition() -> some View {
        if #available(iOS 16.0, *) { contentTransition(.numericText()) }
        else { self }
    }

    @ViewBuilder
    func readingNavigationDestination<Destination: View>(
        isPresented: Binding<Bool>, @ViewBuilder destination: () -> Destination
    ) -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            navigationDestination(isPresented: isPresented, destination: destination)
        } else {
            background(NavigationLink(isActive: isPresented, destination: destination) { EmptyView() }.hidden())
        }
    }

    @ViewBuilder
    func readingScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            scrollContentBackground(.hidden)
        } else {
            background(ReadingUIKitConfiguration { controller in
                func clearTables(in view: UIView) {
                    if let table = view as? UITableView { table.backgroundColor = .clear }
                    for child in view.subviews { clearTables(in: child) }
                }
                if let parent = controller.parent { clearTables(in: parent.view) }
            })
        }
    }

    @ViewBuilder
    func readingScrollDismissesKeyboard() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            scrollDismissesKeyboard(.immediately)
        } else {
            simultaneousGesture(DragGesture().onChanged { _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
        }
    }

    @ViewBuilder
    func readingTabBarBackground() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            toolbarBackground(ReadingTheme.canvas, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
        } else {
            background(ReadingUIKitConfiguration { controller in
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(ReadingTheme.canvas)
                controller.tabBarController?.tabBar.standardAppearance = appearance
                controller.tabBarController?.tabBar.scrollEdgeAppearance = appearance
            })
        }
    }

    @ViewBuilder
    func readingTabBarHidden() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            toolbar(.hidden, for: .tabBar)
        } else {
            background(ReadingHiddenTabBar())
        }
    }

    @ViewBuilder
    func readingHomeIndicatorHidden(_ hidden: Bool) -> some View {
        if #available(iOS 16.0, *) {
            persistentSystemOverlays(hidden ? .hidden : .automatic)
        } else {
            self
        }
    }

    @ViewBuilder
    func readingPresentationDetents(_ detents: [ReadingSheetDetent]) -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            presentationDetents(Set(detents.map { $0 == .medium ? PresentationDetent.medium : .large }))
        } else {
            background(ReadingUIKitConfiguration { controller in
                var current: UIViewController? = controller
                while let candidate = current {
                    if let sheet = candidate.presentationController as? UISheetPresentationController {
                        sheet.detents = detents.map { $0 == .medium ? .medium() : .large() }
                        break
                    }
                    current = candidate.parent
                }
            })
        }
    }

    @ViewBuilder
    func readingPresentationDragIndicator() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            presentationDragIndicator(.visible)
        } else {
            background(ReadingUIKitConfiguration { controller in
                var current: UIViewController? = controller
                while let candidate = current {
                    if let sheet = candidate.presentationController as? UISheetPresentationController {
                        if !sheet.prefersGrabberVisible { sheet.prefersGrabberVisible = true }
                        break
                    }
                    current = candidate.parent
                }
            })
        }
    }
}

private struct ReadingUIKitConfiguration: UIViewControllerRepresentable {
    let configure: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(configure: configure) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.configure = configure }

    final class Controller: UIViewController {
        var configure: (UIViewController) -> Void

        init(configure: @escaping (UIViewController) -> Void) {
            self.configure = configure
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); configure(self) }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); configure(self) }
    }
}

private struct ReadingHiddenTabBar: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private weak var hiddenBar: UITabBar?
        private var previouslyHidden = false

        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let bar = tabBarController?.tabBar else { return }
            hiddenBar = bar
            previouslyHidden = bar.isHidden
            bar.isHidden = true
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            hiddenBar?.isHidden = previouslyHidden
        }
    }
}

// MARK: - iOS 14 兼容层
//
// 以下实现为 iOS 14 缺失的 SwiftUI API 提供等价替代，保证在 iOS 14.0+ 上
// 与iOS 15+ 走同一套代码路径，无需在业务侧散落版本分支。

// MARK: AsyncImage（SwiftUI iOS 15+）

/// 远程图片加载结果的轻量模型，对应 `AsyncImagePhase` 中本项目实际用到的部分。
enum ReadingRemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

/// `AsyncImage` 的 iOS 14 等价实现，基于 `URLSession` 共享会话与 `NSCache` 缓存。
struct ReadingRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (ReadingRemoteImagePhase) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @StateObject private var loader = ReadingRemoteImageLoader()

    var body: some View {
        content(loader.phase)
            .onAppear { loader.load(url) }
            .onChange(of: url) { loader.load($0) }
    }
}

extension ReadingRemoteImage where Content == AnyView {
    /// `AsyncImage` 的等价签名：`content` 收到phase，`placeholder` 为加载中/失败时的占位视图。
    init(
        url: URL?,
        @ViewBuilder content: @escaping (ReadingRemoteImagePhase) -> some View,
        @ViewBuilder placeholder: @escaping () -> some View
    ) {
        self.init(
            url: url,
            content: { phase in
                AnyView(content(phase))
            },
            placeholder: placeholder
        )
    }
}

/// 远程图片加载器。
///
/// Swift 6 语言模式下，`@MainActor` 隔离的属性不能被 `URLSession` 的非隔离
/// completion closure 直接访问；且 `deinit` 中不允许触碰隔离状态。
/// 因此这里把状态更新收敛到主线程 actor，网络请求交给一个纯 Sendable 的 worker。
@MainActor
final class ReadingRemoteImageLoader: ObservableObject {
    @Published private(set) var phase: ReadingRemoteImagePhase = .empty

    private let worker = ReadingRemoteImageWorker()
    private var generation = 0

    func load(_ url: URL?) {
        generation &+= 1
        let token = generation
        worker.cancel()

        guard let url else {
            phase = .empty
            return
        }
        if let cached = ReadingRemoteImageCache.image(for: url) {
            phase = .success(cached)
            return
        }

        phase = .empty
        worker.load(url) { [weak self] result in
            // 回调已在主线程；token 防止旧请求覆盖新结果。
            guard let self, self.generation == token else { return }
            self.phase = result
        }
    }
}

/// 图片缓存，跨 actor 共享因此标记为 Sendable 包装。
private enum ReadingRemoteImageCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

/// 执行网络请求，不持有任何主线程隔离状态。
private final class ReadingRemoteImageWorker: @unchecked Sendable {
    private var task: URLSessionDataTask?

    func cancel() {
        task?.cancel()
        task = nil
    }

    func load(_ url: URL, completion: @escaping @MainActor (ReadingRemoteImagePhase) -> Void) {
        // 图片体积小、复用率高，交给 URLCache 处理。
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024
        )
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)

        let request = URLRequest(url: url)
        task = session.dataTask(with: request) { data, _, _ in
            let result: ReadingRemoteImagePhase
            if let data, let image = UIImage(data: data) {
                ReadingRemoteImageCache.store(image, for: url)
                result = .success(image)
            } else {
                result = .failure
            }
            Task { @MainActor in completion(result) }
        }
        task?.resume()
    }
}

// MARK: TimelineView（SwiftUI iOS 15+）

/// `TimelineView` 的 iOS 14 等价实现，用 `Timer` 周期驱动日期刷新。
/// 仅用于刷新时钟类展示，不参与高频动画。
struct ReadingPeriodicTimeline<Content: View>: View {
    let interval: TimeInterval
    @ViewBuilder var content: (Date) -> Content

    @StateObject private var ticker = ReadingTimelineTicker()

    var body: some View {
        content(ticker.date)
            .onAppear { ticker.start(interval: interval) }
            .onDisappear { ticker.stop() }
    }
}

/// 周期刷新的时间源。
///
/// Swift 6 语言模式下 `Timer` 的回调闭包是非隔离的，不能直接写
/// `@MainActor` 隔离的属性；`deinit` 也不允许触碰隔离状态。
/// 因此定时器句柄交给独立的 Sendable 容器管理，回调统一切回主线程。
@MainActor
final class ReadingTimelineTicker: ObservableObject {
    @Published private(set) var date = Date()

    private let holder = TimerHolder()

    func start(interval: TimeInterval) {
        stop()
        date = Date()
        holder.start(interval: interval) { [weak self] in
            self?.date = Date()
        }
    }

    func stop() {
        holder.cancel()
    }
}

/// 持有 `Timer`，避免在 `@MainActor` 类型的 `deinit` 中访问隔离状态。
private final class TimerHolder: @unchecked Sendable {
    private var timer: Timer?

    func start(interval: TimeInterval, onTick: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in onTick() }
        }
        // 注册到 .common 模式，避免滚动阅读时计时器被暂停。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

extension ReadingPeriodicTimeline where Content == AnyView {
    init(_ schedule: ReadingTimelineSchedule, @ViewBuilder content: @escaping (Date) -> some View) {
        self.init(interval: schedule.interval) { date in
            AnyView(content(date))
        }
    }
}

/// 对应 `TimelineSchedule.periodic(from:by:)`，`.now` 为起始时刻故简化为仅保留间隔。
enum ReadingTimelineSchedule {
    case periodic(TimeInterval)

    var interval: TimeInterval {
        switch self {
        case .periodic(let interval): return interval
        }
    }
}

// MARK: Date.formatted / Double.formatted（Foundation iOS 15+）

extension Date {
    /// `date.formatted(.dateTime.hour().minute())` 的 iOS 14 等价实现。
    func readingFormattedTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// `date.formatted(.dateTime.locale(_:).month().day())` 的 iOS 14 等价实现。
    func readingFormattedMonthDay(locale identifier: String = "zh_CN") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: identifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: self)
    }
}

extension BinaryFloatingPoint {
    /// `value.formatted(.number.precision(.fractionLength(n)))` 的 iOS 14 等价实现。
    func readingFormattedFraction(fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f", Double(self))
    }

    /// `value.formatted(.percent.precision(.fractionLength(n)))` 的 iOS 14 等价实现。
    func readingFormattedPercent(fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f%%", Double(self) * 100)
    }
}

// MARK: - 文本输入兼容（iOS 15+ 的 textInput* 修饰符）

/// iOS 14 上承载文本输入行为的修饰符。
///
/// `.textInputAutocapitalization(_:)` 与 `.disableAutocorrection(_:)` 由 SwiftUI 在 iOS 15 才引入，
/// 且未提供低版本重载，无法用同名方法绕过。这里的策略是：
/// - iOS 15+：原样转发系统修饰符，行为与改造前完全一致。
/// - iOS 14：`.disableAutocorrection` 落到 SwiftUI 早在 iOS 13 提供的
///   `\.autocorrectionDisabled` 环境值；自动大写无等价修饰符，退化为 UIKit 层设置。
struct ReadingInputConfiguration: ViewModifier {
    var autocapitalization: ReadingTextAutocapitalization?
    var disableAutocorrection: Bool?

    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content
                .modifier(ReadingCapitalizationModifier(autocapitalization: autocapitalization))
                .modifier(ReadingCorrectionModifier(disable: disableAutocorrection))
        } else {
            content
                .modifier(ReadingLegacyCorrectionModifier(disable: disableAutocorrection))
                .background(ReadingLegacyCapitalizationModifier(autocapitalization: autocapitalization))
        }
    }
}

@available(iOS 15.0, *)
private struct ReadingCapitalizationModifier: ViewModifier {
    var autocapitalization: ReadingTextAutocapitalization?

    func body(content: Content) -> some View {
        if let autocapitalization {
            content.textInputAutocapitalization(autocapitalization.swiftUIValue)
        } else {
            content
        }
    }
}

@available(iOS 15.0, *)
private struct ReadingCorrectionModifier: ViewModifier {
    var disable: Bool?

    func body(content: Content) -> some View {
        if let disable {
            content.disableAutocorrection(disable)
        } else {
            content
        }
    }
}

/// iOS 14 分支：用环境值关闭自动纠错（SwiftUI iOS 13+ 即可用）。
private struct ReadingLegacyCorrectionModifier: ViewModifier {
    var disable: Bool?

    func body(content: Content) -> some View {
        if disable == true {
            content.environment(\.autocorrectionDisabled, true)
        } else {
            content
        }
    }
}

/// iOS 14 分支：自动大写通过表示层设置 `autocapitalizationType`。
private struct ReadingLegacyCapitalizationModifier: UIViewRepresentable {
    var autocapitalization: ReadingTextAutocapitalization?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let autocapitalization else { return }
        // 等宿主视图完成布局后再下探，保证 TextField 已创建。
        DispatchQueue.main.async {
            guard let host = uiView.superview else { return }
            for field in host.collectReadingTextFields() {
                field.autocapitalizationType = autocapitalization.uiKitValue
            }
        }
    }
}

extension UIView {
    /// 收集视图树中的所有 `UITextField`，含 `UITextView` 内部承载输入的文本框。
    fileprivate func collectReadingTextFields() -> [UITextField] {
        var result: [UITextField] = []
        func walk(_ node: UIView) {
            if let field = node as? UITextField { result.append(field) }
            if let textView = node as? UITextView {
                for case let field as UITextField in textView.subviews { result.append(field) }
            }
            for subview in node.subviews { walk(subview) }
        }
        walk(self)
        return result
    }
}

extension View {
    /// iOS 14+ 统一的文本输入配置入口，替代 iOS 15 才提供的
    /// `.textInputAutocapitalization(_:)` 与 `.disableAutocorrection(_:)`。
    func readingInputConfiguration(
        autocapitalization: ReadingTextAutocapitalization? = nil,
        disableAutocorrection: Bool? = nil
    ) -> some View {
        modifier(ReadingInputConfiguration(
            autocapitalization: autocapitalization,
            disableAutocorrection: disableAutocorrection
        ))
    }
}

/// 自动大写策略的跨版本表示。
enum ReadingTextAutocapitalization {
    case never
    case words
    case sentences
    case characters

    var uiKitValue: UITextAutocapitalizationType {
        switch self {
        case .never: return .none
        case .words: return .words
        case .sentences: return .sentences
        case .characters: return .allCharacters
        }
    }
}

@available(iOS 15.0, *)
private extension ReadingTextAutocapitalization {
    var swiftUIValue: TextInputAutocapitalization {
        switch self {
        case .never: return .never
        case .words: return .words
        case .sentences: return .sentences
        case .characters: return .characters
        }
    }
}

// MARK: ProgressView.controlSize（SwiftUI iOS 15+）

/// `ControlSize` 的跨版本表示，避免直接引用 iOS 15 才有的类型。
enum ReadingControlSize {
    case small
    case regular
    case large

    var uiKitValue: UIActivityIndicatorView.Style {
        switch self {
        case .small, .regular: return .medium
        case .large: return .large
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.7
        case .regular: return 1.0
        case .large: return 1.4
        }
    }
}

extension View {
    /// `ProgressView` 的 iOS 14 尺寸兼容入口。
    ///
    /// iOS 15 提供 `.controlSize(_:)` 直接控制 `ProgressView` 尺寸，
    /// iOS 14 无对应 API，这里通过缩放与 UIKit 指示器样式近似还原。
    func readingControlSize(_ size: ReadingControlSize) -> some View {
        modifier(ReadingControlSizeModifier(size: size))
    }
}

private struct ReadingControlSizeModifier: ViewModifier {
    var size: ReadingControlSize

    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content.controlSize(size.swiftUIValue)
        } else {
            content.scaleEffect(size.scale)
        }
    }
}

@available(iOS 15.0, *)
private extension ReadingControlSize {
    var swiftUIValue: ControlSize {
        switch self {
        case .small: return .small
        case .regular: return .regular
        case .large: return .large
        }
    }
}
