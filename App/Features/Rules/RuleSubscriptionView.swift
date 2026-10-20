import SwiftUI

@MainActor
final class RuleSubscriptionModel: ObservableObject {
    @Published private(set) var values: [RuleSub] = []
    @Published var errorMessage: String?
    @Published private(set) var pendingIDs = Set<Int64>()
    private let repository: SQLiteConfigurationRepository?

    init() {
        repository = (try? LegadoDatabase(url: LegadoDatabase.defaultURL())).map { SQLiteConfigurationRepository(database: $0) }
    }
    func load() async {
        guard let repository else { errorMessage = "无法打开规则订阅数据库"; return }
        do { values = try await repository.loadRuleSubs().sorted { $0.customOrder < $1.customOrder } }
        catch { errorMessage = error.localizedDescription }
    }
    func save(_ value: RuleSub) async -> Bool {
        guard !value.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "URL不能为空"; return false }
        guard !values.contains(where: { $0.id != value.id && $0.url == value.url }) else { errorMessage = "URL已存在"; return false }
        var updated = values
        if let index = updated.firstIndex(where: { $0.id == value.id }) { updated[index] = value }
        else { var item = value; item.customOrder = (updated.map(\.customOrder).max() ?? -1) + 1; updated.append(item) }
        return await persist(updated)
    }
    func remove(at offsets: IndexSet) async { _ = await persist(values.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)) }
    func move(from offsets: IndexSet, to destination: Int) async {
        var updated = values; updated.move(fromOffsets: offsets, toOffset: destination)
        for index in updated.indices { updated[index].customOrder = index + 1 }
        _ = await persist(updated)
    }
    func checkAutomaticUpdates(bookSources: SourceLibraryModel, rssSources: RSSLibraryModel, replaceRules: ReplaceRuleLibraryModel) async {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        for index in values.indices where values[index].autoUpdate && values[index].type != 1 {
            let interval = Int64(max(values[index].updateInterval, 0)) * 3_600_000
            guard values[index].update + interval <= now else { continue }
            var subscription = values[index]
            subscription.update = now
            var timestamped = values; timestamped[index] = subscription
            guard await persist(timestamped) else { continue }
            do {
                let data = try await fetch(subscription.url)
                if subscription.silentUpdate {
                    switch subscription.type {
                    case 1: try await rssSources.applySilentSubscription(data)
                    case 2: try await replaceRules.applySilentSubscription(data)
                    default: try await bookSources.applySilentSubscription(data)
                    }
                } else if try hasUpdates(data, type: subscription.type, bookSources: bookSources, rssSources: rssSources, replaceRules: replaceRules) {
                    pendingIDs.insert(subscription.id)
                }
            } catch { errorMessage = "\(subscription.name.isEmpty ? subscription.url : subscription.name)：\(error.localizedDescription)" }
        }
    }
    func clearPending(_ id: Int64) { pendingIDs.remove(id) }

    private func fetch(_ value: String) async throws -> Data {
        let withoutUA = value.hasSuffix("#requestWithoutUA")
        let raw = withoutUA ? String(value.dropLast("#requestWithoutUA".count)) : value
        guard let url = URL(string: raw) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        if withoutUA { request.setValue("", forHTTPHeaderField: "User-Agent") }
        let (data, response) = try await URLSessionHTTPTransport.shared.download(for: request)
        if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) { throw URLError(.badServerResponse) }
        return data
    }

    private func hasUpdates(_ data: Data, type: Int, bookSources: SourceLibraryModel, rssSources: RSSLibraryModel, replaceRules: ReplaceRuleLibraryModel) throws -> Bool {
        switch type {
        case 1:
            let incoming = try RSSSourceImporter().decode(data).sources
            guard incoming.first?.sourceUrl.isEmpty == false else { throw RSSSourceImportError.invalidSource }
            return incoming.contains { value in rssSources.sources.first(where: { $0.sourceUrl == value.sourceUrl }).map { $0.lastUpdateTime < value.lastUpdateTime } ?? true }
        case 2:
            let incoming = try ReplaceRuleImporter().decode(data)
            return incoming.contains { value in
                guard let old = replaceRules.rules.first(where: { $0.id == value.id }) else { return true }
                return old.pattern != value.pattern || old.replacement != value.replacement
            }
        default:
            let incoming = try BookSourceImporter().decode(data)
            guard incoming.first?.bookSourceUrl.isEmpty == false else { throw BookSourceImportError.emptyDocument }
            return incoming.contains { value in bookSources.sources.first(where: { $0.bookSourceUrl == value.bookSourceUrl }).map { $0.lastUpdateTime < value.lastUpdateTime } ?? true }
        }
    }
    private func persist(_ updated: [RuleSub]) async -> Bool {
        guard let repository else { errorMessage = "无法打开规则订阅数据库"; return false }
        do { try await repository.saveRuleSubs(updated); values = try await repository.loadRuleSubs().sorted { $0.customOrder < $1.customOrder }; return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
}

struct RuleSubscriptionView: View {
    @EnvironmentObject private var bookSources: SourceLibraryModel
    @EnvironmentObject private var replaceRules: ReplaceRuleLibraryModel
    @EnvironmentObject private var model: RuleSubscriptionModel
    @State private var editing: RuleSub?

    private var visibleValues: [RuleSub] { model.values.filter { $0.type != 1 } }

    var body: some View {
        List {
            if visibleValues.isEmpty { ReadingUnavailableView("没有规则订阅", systemImage: "link.badge.plus") }
            ForEach(visibleValues) { value in
                Button { open(value) } label: {
                    HStack(spacing: 12) {
                        Text(typeName(value.type)).font(.caption.bold()).foregroundStyle(ReadingTheme.accent).frame(width: 48)
                        VStack(alignment: .leading, spacing: 4) { Text(value.name.isEmpty ? value.url : value.name).foregroundStyle(.primary); Text(value.url).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        if value.autoUpdate { Image(systemName: value.silentUpdate ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle").foregroundStyle(.secondary) }
                        if model.pendingIDs.contains(value.id) { Text("有更新").font(.caption2).foregroundStyle(.orange) }
                    }
                }.swipeActions(edge: .leading) { Button("编辑", systemImage: "pencil") { editing = value }.tint(.blue) }
            }.onDelete { offsets in
                let ids = Set(offsets.compactMap { visibleValues.indices.contains($0) ? visibleValues[$0].id : nil })
                let sourceOffsets = IndexSet(model.values.indices.filter { ids.contains(model.values[$0].id) })
                Task { await model.remove(at: sourceOffsets) }
            }
        }
        .navigationTitle("规则订阅")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("新建", systemImage: "plus") { editing = RuleSub() } }; ToolbarItem(placement: .primaryAction) { EditButton() } }
        .task { await model.load() }
        .sheet(item: $editing) { value in RuleSubscriptionEditView(value: value) { item in await model.save(item) } }
        .alert("规则订阅", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("好") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }

    private func open(_ value: RuleSub) {
        model.clearPending(value.id)
        Task {
            switch value.type {
            case 2: await replaceRules.importRemoteURL(value.url)
            default: await bookSources.importRemoteURL(value.url)
            }
        }
    }
    private func typeName(_ type: Int) -> String { type == 2 ? "净化" : "书源" }
}

private struct RuleSubscriptionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value: RuleSub
    @State private var saving = false
    let save: (RuleSub) async -> Bool
    init(value: RuleSub, save: @escaping (RuleSub) async -> Bool) { _value = State(initialValue: value); self.save = save }
    var body: some View {
        ReadingNavigationStack {
            Form {
                Picker("类型", selection: $value.type) { Text("书源").tag(0); Text("净化规则").tag(2) }
                TextField("名称", text: $value.name)
                ReadingTextField("订阅URL", text: $value.url, axis: .vertical).readingInputConfiguration(autocapitalization: .never, disableAutocorrection: true)
                Toggle("自动更新", isOn: $value.autoUpdate)
                if value.autoUpdate {
                    Stepper("更新间隔：\(value.updateInterval) 小时", value: $value.updateInterval, in: 1...720)
                    Toggle("静默更新", isOn: $value.silentUpdate)
                }
            }.navigationTitle("规则订阅").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中…" : "保存") { saving = true; Task { if await save(value) { dismiss() }; saving = false } }.disabled(saving || value.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}
