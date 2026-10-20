import Foundation

public struct BookExploreService: Sendable {
    private let transport: any HTTPTransport
    private let urlBuilder: LegadoURLBuilder
    private let engine: RuleEngine
    private let networkPolicy: SourceNetworkPolicy
    private let webViewExecutor: (any SourceWebViewRequestExecuting)?

    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        urlBuilder: LegadoURLBuilder = .init(),
        engine: RuleEngine = .init(),
        networkPolicy: SourceNetworkPolicy = .shared,
        webViewExecutor: (any SourceWebViewRequestExecuting)? = nil
    ) {
        self.transport = transport
        self.urlBuilder = urlBuilder
        self.engine = engine
        self.networkPolicy = networkPolicy
        self.webViewExecutor = webViewExecutor
    }

    public func kinds(for source: BookSource) async -> ExploreKindsReport {
        guard let rule = source.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rule.isEmpty else { return .init() }
        var diagnostics: [RuleDiagnostic] = []
        let rendered: String
        if rule.lowercased().hasPrefix("@js:") || rule.lowercased().hasPrefix("<js>") {
            let result = await engine.evaluate(
                rule,
                in: .null,
                context: .init(source: source)
            )
            diagnostics += result.diagnostics
            rendered = result.firstString ?? ""
        } else {
            rendered = rule
        }
        do {
            return .init(kinds: try parseKinds(rendered), diagnostics: diagnostics)
        } catch let error as RuleEngineError {
            diagnostics.append(error.diagnostic)
            return .init(diagnostics: diagnostics)
        } catch {
            diagnostics.append(.init(
                severity: .error,
                code: "explore.kinds",
                message: error.localizedDescription,
                rule: rule
            ))
            return .init(diagnostics: diagnostics)
        }
    }

    public func explore(
        source: BookSource,
        kind: ExploreKind,
        page: Int = 1
    ) async -> SourceSearchOutcome {
        guard let template = kind.navigableURL else {
            return failure(source, code: "explore.url", message: "发现分类缺少 URL", rule: kind.title)
        }
        let rules = resolvedRules(source)
        guard let rules, let listRule = rules.bookList, !listRule.isEmpty else {
            return failure(source, code: "explore.configuration", message: "书源缺少发现列表规则", rule: template)
        }
        do {
            let prepared = try urlBuilder.prepare(
                template,
                context: .init(page: page, source: source),
                baseURL: URL(string: source.bookSourceUrl),
                defaultHeaders: parseHeaders(source.header)
            )
            let timeout = min(max(Double(source.respondTime) / 1_000, 5), 180)
            let response = try await networkPolicy.execute(
                prepared,
                source: source,
                transport: transport,
                timeout: timeout,
                webViewExecutor: webViewExecutor
            )
            let body = response.decodedText
            let root = response.decodedJSON
            var context = RuleExecutionContext(
                variables: response.requestVariables,
                baseURL: response.finalURL.absoluteString,
                source: source
            )
            let list = if let root {
                await engine.evaluate(listRule.trimmingListPrefix, in: root, listMode: true, context: context)
            } else {
                await engine.evaluate(
                    listRule.trimmingListPrefix,
                    inText: body,
                    baseURL: response.finalURL.absoluteString,
                    listMode: true,
                    context: context
                )
            }
            context.variables = list.variables
            var diagnostics = list.diagnostics
            var books: [SearchBook] = []
            for item in list.listItems(rule: listRule.trimmingListPrefix) {
                try Task.checkCancellation()
                let fields = await evaluateFields(
                    rules,
                    item: item,
                    isHTML: root == nil,
                    baseURL: response.finalURL.absoluteString,
                    source: source,
                    variables: context.variables
                )
                diagnostics += fields.diagnostics
                guard let name = fields.name, !name.isEmpty else { continue }
                let bookURL = resolve(fields.bookURL ?? response.finalURL.absoluteString, against: response.finalURL)
                var book = SearchBook(
                    bookURL: bookURL,
                    origin: source.bookSourceUrl,
                    originName: source.bookSourceName,
                    type: source.bookSourceType,
                    name: name,
                    author: fields.author ?? ""
                )
                book.kind = fields.kind
                book.coverURL = fields.coverURL.map { resolve($0, against: response.finalURL) }
                book.intro = MetadataTextSanitizer().clean(fields.intro)
                book.wordCount = fields.wordCount
                book.latestChapterTitle = fields.lastChapter
                book.originOrder = source.customOrder
                book.variables = fields.variables
                books.append(book)
            }
            if listRule.hasPrefix("-") { books.reverse() }
            var unique = Set<String>()
            books = books.filter { unique.insert($0.bookURL).inserted }
            return .init(sourceID: source.id, books: books, diagnostics: diagnostics)
        } catch is CancellationError {
            return failure(source, code: "explore.cancelled", message: "发现加载已取消", rule: template)
        } catch let error as RuleEngineError {
            return .init(sourceID: source.id, books: [], diagnostics: [error.diagnostic])
        } catch {
            return failure(source, code: "explore.request", message: error.localizedDescription, rule: template)
        }
    }

    private func parseKinds(_ value: String) throws -> [ExploreKind] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("[") {
            do {
                return try JSONDecoder().decode([ExploreKind].self, from: Data(trimmed.utf8))
            } catch let strictError {
                do {
                    // `.json5Allowed` 是 iOS 15 才有的 JSONSerialization 选项，
                    // iOS 14 不支持宽松 JSON5 语法，这里退化为标准 JSON 解析。
                    let options: JSONSerialization.ReadingOptions = {
                        if #available(iOS 15.0, macOS 12.0, *) {
                            return [.fragmentsAllowed, .json5Allowed]
                        }
                        return [.fragmentsAllowed]
                    }()
                    let object = try JSONSerialization.jsonObject(
                        with: Data(trimmed.utf8),
                        options: options
                    )
                    let normalized = try JSONEncoder().encode(JSONValue.bridge(object))
                    return try JSONDecoder().decode([ExploreKind].self, from: normalized)
                } catch {
                    throw RuleEngineError.malformedRule(
                        rule: value,
                        detail: "发现分类 JSON 无效：\(strictError.localizedDescription)"
                    )
                }
            }
        }
        return trimmed
            .replacingOccurrences(of: "&&", with: "\n")
            .split(whereSeparator: { $0.isNewline })
            .compactMap { line in
                let line = String(line)
                let range = line.range(of: "::")
                let title = String(range.map { line[..<$0.lowerBound] } ?? line[...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                let url = range.map { String(line[$0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
                return ExploreKind(title: title, url: url?.isEmpty == true ? nil : url)
            }
    }

    private func resolvedRules(_ source: BookSource) -> BookListRule? {
        if let rules = source.ruleExplore, rules.bookList?.isEmpty == false { return rules }
        guard let search = source.ruleSearch else { return source.ruleExplore }
        return .init(
            bookList: search.bookList,
            name: search.name,
            author: search.author,
            intro: search.intro,
            kind: search.kind,
            lastChapter: search.lastChapter,
            updateTime: search.updateTime,
            bookUrl: search.bookUrl,
            coverUrl: search.coverUrl,
            wordCount: search.wordCount
        )
    }

    private func evaluateFields(
        _ rules: BookListRule,
        item: JSONValue,
        isHTML: Bool,
        baseURL: String,
        source: BookSource,
        variables: [String: String]
    ) async -> Fields {
        var context = RuleExecutionContext(variables: variables, baseURL: baseURL, source: source, isHTMLFragment: true)
        var result = Fields()
        let name = await evaluate(rules.name, item: item, isHTML: isHTML, baseURL: baseURL, context: context)
        context.variables = name.variables
        let author = await evaluate(rules.author, item: item, isHTML: isHTML, baseURL: baseURL, context: context)
        context.variables = author.variables
        let kind = await evaluate(rules.kind, item: item, isHTML: isHTML, baseURL: baseURL, context: context)
        context.variables = kind.variables
        let bookURL = await evaluate(rules.bookUrl, item: item, isHTML: isHTML, baseURL: baseURL, context: context)
        context.variables = bookURL.variables
        let cover = await evaluate(rules.coverUrl, item: item, isHTML: isHTML, baseURL: baseURL, context: context)
        context.variables = cover.variables
        let intro = await evaluate(rules.intro, item: item, isHTML: isHTML, baseURL: baseURL, context: context)
        context.variables = intro.variables
        let wordCount = await evaluate(rules.wordCount, item: item, isHTML: isHTML, baseURL: baseURL, context: context)
        context.variables = wordCount.variables
        let lastChapter = await evaluate(rules.lastChapter, item: item, isHTML: isHTML, baseURL: baseURL, context: context)
        context.variables = lastChapter.variables
        result.name = name.joinedString
        result.author = author.joinedString
        result.kind = kind.strings.filter { !$0.isEmpty }.joined(separator: ",").nilIfEmpty
        result.bookURL = isHTML ? bookURL.leadingString : bookURL.joinedString
        result.coverURL = cover.joinedString
        result.intro = MetadataTextSanitizer().clean(intro.joinedString)
        result.wordCount = wordCount.joinedString
        result.lastChapter = lastChapter.joinedString
        result.variables = context.variables
        result.diagnostics = [name, author, kind, bookURL, cover, intro, wordCount, lastChapter].flatMap(\.diagnostics)
        return result
    }

    private func evaluate(
        _ rule: String?,
        item: JSONValue,
        isHTML: Bool,
        baseURL: String,
        context: RuleExecutionContext
    ) async -> RuleEvaluation {
        guard let rule, !rule.isEmpty else { return .init(variables: context.variables) }
        if case .string = item {
            return await engine.evaluate(rule, inText: item.stringValue, baseURL: baseURL, context: context)
        }
        return await engine.evaluate(rule, in: item, context: context)
    }

    private func resolve(_ value: String, against base: URL) -> String {
        LegadoURLBuilder.resolve(value, against: base)
    }

    private func parseHeaders(_ source: String?) -> [String: String] {
        guard let source, let value = try? JSONValue.decode(data: Data(source.utf8)),
              case .object(let object) = value else { return [:] }
        return object.mapValues(\.stringValue)
    }

    private func failure(_ source: BookSource, code: String, message: String, rule: String) -> SourceSearchOutcome {
        .init(sourceID: source.id, books: [], diagnostics: [
            .init(severity: .error, code: code, message: message, rule: rule)
        ])
    }

    private struct Fields {
        var name: String?
        var author: String?
        var kind: String?
        var bookURL: String?
        var coverURL: String?
        var intro: String?
        var wordCount: String?
        var lastChapter: String?
        var variables: [String: String] = [:]
        var diagnostics: [RuleDiagnostic] = []
    }
}

extension String {
    var trimmingListPrefix: String {
        guard hasPrefix("-") || hasPrefix("+") else { return self }
        return String(dropFirst())
    }

    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
