import SwiftUI
import UIKit

struct SyntaxCodeEditor: UIViewRepresentable {
    enum Language { case json, rule, javascript, regex }
    @Binding var text: String
    var language: Language = .rule

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.backgroundColor = .secondarySystemGroupedBackground
        view.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 20, right: 12)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.accessibilityIdentifier = "syntaxCodeEditor"
        if #available(iOS 16.0, *) { view.isFindInteractionEnabled = true }
        let bar = UIToolbar()
        bar.sizeToFit()
        // iOS 14 兼容：不使用 iOS 16 才有的 UIBarButtonItem(_:primaryAction:)，
        // 改用target-action，行为与新写法一致。
        let coordinator = context.coordinator
        coordinator.textView = view
        let symbolItems = ["@", "$", "{}", "[]", "##", "\n", "\t"].map { symbol in
            coordinator.symbolItem(display: symbol == "\n" ? "↵" : symbol == "\t" ? "⇥" : symbol, symbol: symbol)
        }
        bar.items = [
            coordinator.toolbarItem(systemName: "magnifyingglass", label: "查找替换", action: #selector(Coordinator.presentFindAndReplaceFromToolbar(_:))),
            coordinator.toolbarItem(systemName: "arrow.uturn.backward", label: "撤销", action: #selector(Coordinator.undoFromToolbar(_:))),
            coordinator.toolbarItem(systemName: "arrow.uturn.forward", label: "重做", action: #selector(Coordinator.redoFromToolbar(_:))),
        ] + symbolItems + [
            UIBarButtonItem(systemItem: .flexibleSpace),
            coordinator.toolbarItem(systemName: "checkmark", label: "完成", action: #selector(Coordinator.dismissKeyboardFromToolbar(_:)))
        ]
        view.inputAccessoryView = bar
        view.text = text
        context.coordinator.highlight(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        guard view.markedTextRange == nil else { return }
        // SwiftUI can render an older binding snapshot while the next native
        // keystroke is already in the text view. Wait for acknowledgement of
        // the latest local edit instead of replacing it with that snapshot.
        if let pending = context.coordinator.pendingLocalText {
            guard text == pending else { return }
            context.coordinator.pendingLocalText = nil
        }
        if view.text != text {
            let selection = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(location: min(selection.location, view.text.utf16.count), length: 0)
        }
        context.coordinator.highlight(view)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxCodeEditor
        private var highlightedText: String?
        private var highlightedStyle: UIUserInterfaceStyle?
        private var highlightedLanguage: Language?
        var pendingLocalText: String?
        init(_ parent: SyntaxCodeEditor) { self.parent = parent }

        // MARK: 工具栏 target-action（iOS 14 兼容层）

        /// 由 makeUIView 挂载，供工具栏 action 定位当前编辑框。
        weak var textView: UITextView?

        func toolbarItem(systemName: String, label: String, action: Selector) -> UIBarButtonItem {
            let item = UIBarButtonItem(
                image: UIImage(systemName: systemName),
                style: .plain,
                target: self,
                action: action
            )
            item.accessibilityLabel = label
            return item
        }

        /// 符号按钮：标题显示的是可视字符（如「↵」），插入的是真实文本（如换行符），
        /// 因此把真实文本放在 `accessibilityIdentifier` 里，由 target-action 直接取用，
        /// 无需额外的全局映射表。
        func symbolItem(display: String, symbol: String) -> UIBarButtonItem {
            let item = UIBarButtonItem(
                title: display,
                style: .plain,
                target: self,
                action: #selector(insertSymbol(_:))
            )
            item.accessibilityIdentifier = symbol
            item.accessibilityLabel = display
            return item
        }

        @objc func insertSymbol(_ sender: UIBarButtonItem) {
            guard let symbol = sender.accessibilityIdentifier, !symbol.isEmpty else { return }
            textView?.insertText(symbol)
        }

        @objc func presentFindAndReplaceFromToolbar(_ sender: UIBarButtonItem) {
            guard let view = textView else { return }
            if #available(iOS 16.0, *) { view.findInteraction?.presentFindNavigator(showingReplace: true) }
            else { presentFindAndReplace(in: view) }
        }

        @objc func undoFromToolbar(_ sender: UIBarButtonItem) {
            textView?.undoManager?.undo()
        }

        @objc func redoFromToolbar(_ sender: UIBarButtonItem) {
            textView?.undoManager?.redo()
        }

        @objc func dismissKeyboardFromToolbar(_ sender: UIBarButtonItem) {
            textView?.resignFirstResponder()
        }

        func presentFindAndReplace(in view: UITextView) {
            guard var presenter = view.window?.rootViewController else { return }
            while let presented = presenter.presentedViewController { presenter = presented }
            let alert = UIAlertController(title: "查找与替换", message: nil, preferredStyle: .alert)
            alert.addTextField { $0.placeholder = "查找内容" }
            alert.addTextField { $0.placeholder = "替换为（可留空）" }
            alert.addAction(UIAlertAction(title: "查找下一个", style: .default) { [weak view, weak alert] _ in
                guard let view, let query = alert?.textFields?.first?.text, !query.isEmpty else { return }
                let text = (view.text ?? "") as NSString
                let start = min(NSMaxRange(view.selectedRange), text.length)
                var range = text.range(of: query, range: NSRange(location: start, length: text.length - start))
                if range.location == NSNotFound { range = text.range(of: query) }
                guard range.location != NSNotFound else { return }
                view.becomeFirstResponder()
                view.selectedRange = range
                view.scrollRangeToVisible(range)
            })
            alert.addAction(UIAlertAction(title: "全部替换", style: .default) { [weak view, weak alert] _ in
                guard let view, let fields = alert?.textFields,
                      let query = fields.first?.text, !query.isEmpty else { return }
                let original = view.text ?? ""
                let replacement = original.replacingOccurrences(of: query, with: fields.last?.text ?? "")
                guard replacement != original else { return }
                view.becomeFirstResponder()
                view.selectedRange = NSRange(location: 0, length: original.utf16.count)
                view.insertText(replacement)
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            presenter.present(alert, animated: true)
        }

        func textViewDidChange(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            pendingLocalText = view.text
            parent.text = view.text
            highlight(view)
        }

        func textViewDidEndEditing(_ view: UITextView) {
            pendingLocalText = nil
            parent.text = view.text
            highlight(view)
        }

        func highlight(_ view: UITextView) {
            guard view.markedTextRange == nil,
                  highlightedText != view.text || highlightedStyle != view.traitCollection.userInterfaceStyle || highlightedLanguage != parent.language else { return }
            highlightedText = view.text
            highlightedStyle = view.traitCollection.userInterfaceStyle
            highlightedLanguage = parent.language
            let storage = view.textStorage
            let selection = view.selectedRange
            let all = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes([.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: UIColor.label], range: all)
            if storage.length <= 500_000 {
                let tokens: [(String, UIColor)] = [
                    (#"\b(?:true|false|null|undefined|return|var|let|const|if|else|function|new|for|while|try|catch|throw|await|async)\b"#, .systemPurple),
                    (#"\b\d+(?:\.\d+)?\b"#, .systemOrange),
                    (#"@(?:css|xpath|json|js|put|get):?|\$\.|&&|\|\||%%|##|\{\{|\}\}"#, .systemPink),
                    (#"[{}\[\]()]"#, .systemTeal),
                    (#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#, .systemGreen),
                    (#""(?:\\.|[^"\\])*"(?=\s*:)"#, .systemBlue),
                ]
                for (pattern, color) in tokens {
                    guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                    regex.enumerateMatches(in: view.text, range: all) { result, _, _ in
                        if let result { storage.addAttribute(.foregroundColor, value: color, range: result.range) }
                    }
                }
                if parent.language == .regex {
                    for pattern in [#"[.*+?^$|]"#, #"\\[dDsSwWbB0-9]|\{[0-9,]+\}"#] {
                        let regex = try? NSRegularExpression(pattern: pattern)
                        regex?.enumerateMatches(in: view.text, range: all) { result, _, _ in
                            if let result { storage.addAttribute(.foregroundColor, value: UIColor.systemPink, range: result.range) }
                        }
                    }
                }
                if parent.language == .javascript {
                    let pattern = #"(?m)^\s*//.*$|/\*[\s\S]*?\*/"#
                    let regex = try? NSRegularExpression(pattern: pattern)
                    regex?.enumerateMatches(in: view.text, range: all) { result, _, _ in
                        if let result { storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: result.range) }
                    }
                }
            }
            storage.endEditing()
            view.selectedRange = selection
            view.typingAttributes = [.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: UIColor.label]
        }
    }
}

struct RuleCodeFieldView: View {
    let title: String
    let path: String
    @Binding var text: String
    var language: SyntaxCodeEditor.Language = .rule
    var help: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(path).font(.caption.monospaced()).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            if let help {
                Text(help).font(.footnote).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 10)
            }
            SyntaxCodeEditor(text: $text, language: language)
            HStack {
                Text("\(text.components(separatedBy: "\n").count) 行 · \(text.utf16.count) 字符")
                Spacer()
                if language == .rule { Text("CSS · XPath · JSONPath · JS") }
            }.font(.caption).foregroundColor(.secondary).padding(12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
