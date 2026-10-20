import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SourceManagementView: View {
    @EnvironmentObject private var library: SourceLibraryModel
    @State private var showsImporter = false
    @State private var showsNewSource = false
    @State private var showsQRImporter = false
    @State private var showsTextImporter = false
    @State private var showsGroupManager = false
    @State private var showsBatchGroups = false
    @State private var selectedGroup: String?
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedSourceIDs = Set<String>()
    @AppStorage("bookSourceSort") private var sortMode = "manual"
    @AppStorage("bookSourceSortDescending") private var sortDescending = false

    private var filteredSources: [BookSource] {
        let filtered = library.sources.filter { source in
            let matchesGroup: Bool
            if let selectedGroup {
                matchesGroup = selectedGroup.isEmpty ? source.groups.isEmpty : source.hasGroup(selectedGroup)
            } else {
                matchesGroup = true
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return matchesGroup && (query.isEmpty
                || source.bookSourceName.localizedCaseInsensitiveContains(query)
                || source.bookSourceUrl.localizedCaseInsensitiveContains(query)
                || source.groups.contains(where: { $0.localizedCaseInsensitiveContains(query) }))
        }
        guard sortMode != "manual" else { return filtered }
        return filtered.sorted { lhs, rhs in
            sortDescending ? isOrdered(rhs, before: lhs) : isOrdered(lhs, before: rhs)
        }
    }

    private func isOrdered(_ lhs: BookSource, before rhs: BookSource) -> Bool {
        switch sortMode {
        case "weight":
            return lhs.weight == rhs.weight ? lhs.bookSourceName.localizedStandardCompare(rhs.bookSourceName) == .orderedAscending : lhs.weight < rhs.weight
        case "name": return lhs.bookSourceName.localizedStandardCompare(rhs.bookSourceName) == .orderedAscending
        case "url": return lhs.bookSourceUrl.localizedStandardCompare(rhs.bookSourceUrl) == .orderedAscending
        case "update": return lhs.lastUpdateTime == rhs.lastUpdateTime ? lhs.bookSourceName < rhs.bookSourceName : lhs.lastUpdateTime > rhs.lastUpdateTime
        case "respond": return lhs.respondTime == rhs.respondTime ? lhs.bookSourceName < rhs.bookSourceName : lhs.respondTime < rhs.respondTime
        case "enabled": return lhs.enabled == rhs.enabled ? lhs.bookSourceName < rhs.bookSourceName : lhs.enabled && !rhs.enabled
        default: return lhs.customOrder < rhs.customOrder
        }
    }

    var body: some View {
        Group {
            if library.sources.isEmpty, !library.isWorking {
                ReadingUnavailableView {
                    Label("还没有书源", systemImage: "network")
                } description: {
                    Text("新建书源，或从文件、链接、JSON、二维码导入。")
                } actions: {
                    Button("导入书源") { showsImporter = true }
                        .readingButtonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        Picker("分组", selection: $selectedGroup) {
                            Text("全部").tag(String?.none)
                            Text("未分组").tag(String?.some(""))
                            ForEach(library.groups, id: \.self) { group in
                                Text(group).tag(String?.some(group))
                            }
                        }
                    }
                    Section {
                        ForEach(filteredSources) { source in
                            if isSelecting {
                                Button {
                                    if !selectedSourceIDs.insert(source.id).inserted { selectedSourceIDs.remove(source.id) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedSourceIDs.contains(source.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundColor(selectedSourceIDs.contains(source.id) ? ReadingTheme.accent : .secondary)
                                        SourceRow(source: source, showsToggle: false) { _ in }
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    SourceDetailView(source: source)
                                } label: {
                                    SourceRow(source: source) { enabled in
                                        Task { await library.setEnabled(enabled, for: source.id) }
                                    }
                                }
                                .contextMenu {
                                    NavigationLink {
                                        SearchView(fixedSource: source)
                                    } label: {
                                        Label("搜索", systemImage: "magnifyingglass")
                                    }
                                    Button(source.enabledExplore ? "停用发现" : "启用发现", systemImage: "safari") {
                                        Task { await library.setExploreEnabled(!source.enabledExplore, for: source.id) }
                                    }
                                    Button("删除", systemImage: "trash") {
                                        Task { await library.remove(sourceIDs: [source.id]) }
                                    }
                                    .readingRole(.destructive)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.compactMap { filteredSources.indices.contains($0) ? filteredSources[$0].id : nil })
                            Task { await library.remove(sourceIDs: ids) }
                        }
                    } header: {
                        Text("\(filteredSources.count) 个书源")
                    } footer: {
                        Text("共 \(library.sources.count) 个书源，\(library.sources.filter(\.enabled).count) 个已启用")
                    }
                }
                .listStyle(.insetGrouped)
                .readingScrollContentBackgroundHidden()
                .background(ReadingTheme.groupedCanvas)
                .overlay(if library.isWorking { ProgressView() })
            }
        }
        .navigationTitle("书源")
        .background(ReadingTheme.groupedCanvas)
        .searchable(text: $searchText, prompt: "名称、地址或分组")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(isSelecting ? "完成" : "选择") {
                    isSelecting.toggle()
                    if !isSelecting { selectedSourceIDs.removeAll() }
                }
                .disabled(library.sources.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("更多", systemImage: "ellipsis.circle") {
                    Button("新建书源", systemImage: "plus") { showsNewSource = true }
                    Button("二维码导入", systemImage: "qrcode.viewfinder") { showsQRImporter = true }
                    Button("从文件导入", systemImage: "doc.badge.plus") { showsImporter = true }
                    Button("URL 或粘贴 JSON", systemImage: "link.badge.plus") { showsTextImporter = true }
                    Divider()
                    NavigationLink {
                        SourceBatchTestView()
                    } label: {
                        Label("测试书源", systemImage: "checkmark.circle.badge.questionmark")
                    }
                    Button("管理分组", systemImage: "folder.badge.gearshape") { showsGroupManager = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("排序", systemImage: "arrow.up.arrow.down") {
                    Toggle("倒序", isOn: $sortDescending)
                    Picker("排序方式", selection: $sortMode) {
                        Text("手动排序").tag("manual")
                        Text("自动排序").tag("weight")
                        Text("按名称").tag("name")
                        Text("按网址").tag("url")
                        Text("按更新时间").tag("update")
                        Text("按响应时间").tag("respond")
                        Text("按启用状态").tag("enabled")
                    }
                }
            }
        }
        .readingSafeAreaInset(edge: .bottom) {
            if isSelecting {
                HStack(spacing: 18) {
                    Button(selectedSourceIDs.count == filteredSources.count ? "取消全选" : "全选") {
                        if selectedSourceIDs.count == filteredSources.count { selectedSourceIDs.removeAll() }
                        else { selectedSourceIDs = Set(filteredSources.map(\.id)) }
                    }
                    Spacer()
                    Button("分组", systemImage: "folder") { showsBatchGroups = true }
                        .disabled(selectedSourceIDs.isEmpty)
                    Button("启用", systemImage: "checkmark.circle") {
                        Task { await library.setEnabled(true, for: selectedSourceIDs) }
                    }
                    .disabled(selectedSourceIDs.isEmpty)
                    Button("停用", systemImage: "pause.circle") {
                        Task { await library.setEnabled(false, for: selectedSourceIDs) }
                    }
                    .disabled(selectedSourceIDs.isEmpty)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18).padding(.vertical, 12)
                .readingMaterialBackground(.ultraThin)
            }
        }
        .sheet(isPresented: $showsNewSource) { SourceEditorView().environmentObject(library) }
        .sheet(isPresented: $showsQRImporter) {
            QRCodeImportView { value in Task { await library.previewInput(value) } }
        }
        .sheet(isPresented: $showsTextImporter) {
            SourceTextImportView()
                .environmentObject(library)
        }
        .sheet(isPresented: $showsGroupManager) {
            SourceGroupManagerView().environmentObject(library)
        }
        .sheet(isPresented: $showsBatchGroups) {
            SourceBatchGroupView(sourceIDs: selectedSourceIDs).environmentObject(library)
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                let files = urls.filter { !$0.hasDirectoryPath }
                if files.isEmpty {
                    library.notice = .init(kind: .error, title: "无法选择文件", detail: "请选择书源 JSON 文件，而不是文件夹。")
                } else {
                    Task { await library.previewFiles(files) }
                }
            case .failure(let error):
                library.notice = .init(kind: .error, title: "无法选择文件", detail: error.localizedDescription)
            }
        }
    }
}

private struct SourceTextImportView: View {
    @Environment(\.readingDismiss) private var dismiss
    @EnvironmentObject private var library: SourceLibraryModel
    @State private var mode = 0
    @State private var value = ""

    var body: some View {
        ReadingNavigationStack {
            Form {
                Picker("导入方式", selection: $mode) {
                    Text("URL").tag(0)
                    Text("粘贴 JSON").tag(1)
                }
                .pickerStyle(.segmented)

                Section {
                    if mode == 0 {
                        TextField("https://example.com/sources.json", text: $value)
                            .readingInputConfiguration(autocapitalization: .never)
                            .keyboardType(.URL)
                    } else {
                        SyntaxCodeEditor(text: $value, language: .json)
                            .frame(minHeight: 220)
                    }
                } header: { Text(mode == 0 ? "书源 URL" : "书源 JSON") }
                Section {
                    Text("导入前可预览并选择书源。地址相同的书源将被替换。")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        let input = value
                        let selectedMode = mode
                        dismiss()
                        Task {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            if selectedMode == 0 { await library.previewRemoteURL(input) }
                            else { await library.previewText(input) }
                        }
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct SourceRow: View {
    let source: BookSource
    var showsToggle = true
    let onEnabledChanged: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: source.enabled ? "network" : "network.slash")
                .font(.system(size: 20))
                .frame(width: 28)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.bookSourceName)
                    .font(.body)
                    .foregroundColor(source.enabled ? Color.primary : .secondary)
                Text(source.groups.isEmpty ? (URL(string: source.bookSourceUrl)?.host ?? source.bookSourceUrl) : source.groups.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if showsToggle {
                Toggle("启用", isOn: Binding(
                    get: { source.enabled },
                    set: { enabled in
                        Task { @MainActor in onEnabledChanged(enabled) }
                    }
                ))
                .labelsHidden()
                .readingTint(.green)
                .accessibilityLabel("启用\(source.bookSourceName)")
            }
        }
        .padding(.vertical, 5)
    }
}

private struct SourceGroupManagerView: View {
    @Environment(\.readingDismiss) private var dismiss
    @EnvironmentObject private var library: SourceLibraryModel
    @State private var newGroup = ""
    @State private var renaming: String?
    @State private var renamedValue = ""

    var body: some View {
        ReadingNavigationStack {
            List {
                Section {
                    HStack {
                        TextField("例如：文学", text: $newGroup)
                        Button("添加") {
                            let value = newGroup
                            newGroup = ""
                            let ungrouped = Set(library.sources.filter { $0.groups.isEmpty }.map(\.id))
                            Task { await library.addGroup(value, to: ungrouped) }
                        }
                        .disabled(BookSource.parseGroups(newGroup).isEmpty)
                    }
                    Text("新分组会分配给当前未分组书源，与 Legado 的分组管理行为一致。")
                        .font(.caption).foregroundColor(.secondary)
                } header: { Text("新建分组") }
                Section {
                    ForEach(library.groups, id: \.self) { group in
                        HStack {
                            Label(group, systemImage: "folder.fill")
                            Spacer()
                            Text("\(library.sources.filter { $0.hasGroup(group) }.count)")
                                .foregroundColor(.secondary)
                            Menu {
                                Button("重命名", systemImage: "pencil") {
                                    renaming = group
                                    renamedValue = group
                                }
                                Button("删除分组", systemImage: "trash") {
                                    Task { await library.deleteGroup(group) }
                                }
                                .readingRole(.destructive)
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                } header: { Text("已有分组") }
            }
            .navigationTitle("书源分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .readingAlert("重命名分组", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("分组名称", text: $renamedValue)
                Button("取消") { renaming = nil }
                .readingRole(.cancel)
                Button("保存") {
                    if let old = renaming { Task { await library.renameGroup(old, to: renamedValue) } }
                    renaming = nil
                }
            }
        }
    }
}

private struct SourceBatchGroupView: View {
    @Environment(\.readingDismiss) private var dismiss
    @EnvironmentObject private var library: SourceLibraryModel
    let sourceIDs: Set<String>
    @State private var customGroup = ""

    var body: some View {
        ReadingNavigationStack {
            List {
                Section {
                    HStack {
                        TextField("输入新分组", text: $customGroup)
                        Button("加入") {
                            let value = customGroup
                            customGroup = ""
                            Task { await library.addGroup(value, to: sourceIDs) }
                        }
                        .disabled(BookSource.parseGroups(customGroup).isEmpty)
                    }
                } header: { Text("已选择 \(sourceIDs.count) 个书源") }
                Section {
                    ForEach(library.groups, id: \.self) { group in
                        Button { Task { await library.addGroup(group, to: sourceIDs) } } label: {
                            Label(group, systemImage: "folder.badge.plus")
                        }
                    }
                } header: { Text("加入现有分组") }
                Section {
                    ForEach(library.groups, id: \.self) { group in
                        Button {
                            Task { await library.removeGroup(group, from: sourceIDs) }
                        } label: { Label(group, systemImage: "folder.badge.minus") }
                        .readingRole(.destructive)
                    }
                } header: { Text("从分组移除") }
            }
            .navigationTitle("批量归组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct SourceDetailView: View {
    @EnvironmentObject private var library: SourceLibraryModel
    let source: BookSource
    @State private var showsEditor = false
    @State private var editedSourceID: String?
    private var current: BookSource { library.sources.first { $0.id == (editedSourceID ?? source.id) } ?? source }

    var body: some View {
        List {
            Section {
                ReadingLabeledContent("名称", value: current.bookSourceName)
                ReadingLabeledContent("地址", value: current.bookSourceUrl)
                ReadingLabeledContent("分组", value: current.bookSourceGroup ?? "未分组")
                ReadingLabeledContent("类型", value: String(current.bookSourceType))
            } header: { Text("基本信息") }
            Section {
                CapabilityRow(title: "搜索", available: current.searchUrl?.isEmpty == false)
                CapabilityRow(title: "发现", available: current.exploreUrl?.isEmpty == false)
                CapabilityRow(title: "详情", available: current.ruleBookInfo != nil)
                CapabilityRow(title: "目录", available: current.ruleToc != nil)
                CapabilityRow(title: "正文", available: current.ruleContent != nil)
            } header: { Text("能力") }
            Section {
                Toggle("启用书源", isOn: Binding(
                    get: { library.sources.first(where: { $0.id == current.id })?.enabled ?? current.enabled },
                    set: { value in Task { await library.setEnabled(value, for: current.id) } }
                ))
                Toggle("启用发现", isOn: Binding(
                    get: { library.sources.first(where: { $0.id == current.id })?.enabledExplore ?? current.enabledExplore },
                    set: { value in Task { await library.setExploreEnabled(value, for: current.id) } }
                ))
            } header: { Text("状态") }
            Section {
                NavigationLink {
                    SearchView(fixedSource: current)
                } label: {
                    Label("搜索此书源", systemImage: "magnifyingglass")
                }
                NavigationLink {
                    SourceDebugView(source: current)
                } label: {
                    Label("运行端到端调试", systemImage: "stethoscope")
                }
                Text("使用你输入的关键词，逐步验证搜索、详情、目录和正文规则。")
                    .font(.footnote).foregroundColor(.secondary)
            } header: { Text("兼容检查") }
            if current.loginUrl?.isEmpty == false {
                Section {
                    NavigationLink {
                        SourceLoginView(source: current)
                    } label: {
                        Label("登录此书源", systemImage: "person.badge.key.fill")
                    }
                    Text("登录 Cookie 与阅读请求共享；若书源提供检测脚本，会在页面载入后自动验证。")
                        .font(.footnote).foregroundColor(.secondary)
                } header: { Text("账户") }
            }
            if let comment = current.bookSourceComment, !comment.isEmpty {
                Section("说明") { Text(comment) }
            }
        }
        .navigationTitle(current.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { showsEditor = true }
            }
        }
        .sheet(isPresented: $showsEditor) {
            SourceEditorView(source: current) { editedSourceID = $0.id }.environmentObject(library)
        }
    }
}

struct SourceImportReviewView: View {
    @Environment(\.readingDismiss) private var dismiss
    @EnvironmentObject private var library: SourceLibraryModel
    let pending: SourceLibraryModel.PendingImport
    @State private var selectedIDs: Set<String>
    @State private var importError: String?
    @State private var isImporting = false
    @State private var keepOriginalName = false
    @State private var keepOriginalGroup = false
    @State private var keepOriginalEnabled = false
    @State private var showComments = false
    @State private var customGroup = ""
    @State private var addCustomGroup = true

    init(pending: SourceLibraryModel.PendingImport) {
        self.pending = pending
        _selectedIDs = State(initialValue: Set(pending.items.filter { $0.existing == nil || $0.state == "更新" }.map(\.id)))
    }

    var body: some View {
        ReadingNavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        importCountCard(
                            title: "有效",
                            count: pending.validCount,
                            color: .green,
                            systemImage: "checkmark.circle.fill"
                        )
                        importCountCard(
                            title: "失效",
                            count: pending.invalidCount,
                            color: .red,
                            systemImage: "xmark.circle.fill"
                        )
                        importCountCard(
                            title: "总计",
                            count: pending.totalCount,
                            color: .secondary,
                            systemImage: "doc.text.fill"
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                    Label("仅有效书源可被选择和导入", systemImage: "checkmark.shield.fill")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if !pending.items.isEmpty {
                    Section {
                        HStack {
                            TextField("自定义分组", text: $customGroup)
                            Toggle("追加", isOn: $addCustomGroup).labelsHidden()
                        }
                        Toggle("保留原名称", isOn: $keepOriginalName)
                        Toggle("保留原分组", isOn: $keepOriginalGroup)
                        Toggle("保留原启用状态", isOn: $keepOriginalEnabled)
                        Toggle("显示书源备注", isOn: $showComments)
                    } header: { Text("导入设置") }
                }

                Section {
                    ForEach(pending.items) { item in
                        Button {
                            if !selectedIDs.insert(item.id).inserted { selectedIDs.remove(item.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedIDs.contains(item.id) ? ReadingTheme.accent : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.source.bookSourceName).foregroundColor(.primary)
                                    HStack {
                                        Text(item.state)
                                            .font(.caption.bold())
                                            .foregroundColor(item.state == "新增" ? .green : item.state == "更新" ? .orange : .secondary)
                                        Text(item.source.bookSourceUrl)
                                            .font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    }
                                    if showComments, let comment = item.source.bookSourceComment, !comment.isEmpty {
                                        Text(comment).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: { Text("有效书源（\(pending.validCount)）") }

                if !pending.invalidItems.isEmpty {
                    Section {
                        ForEach(pending.invalidItems) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.source.bookSourceName.isEmpty ? "未命名书源" : item.source.bookSourceName)
                                        .foregroundColor(.primary)
                                    if !item.source.bookSourceUrl.isEmpty {
                                        Text(item.source.bookSourceUrl)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Text(item.issues.map(\.message).joined(separator: "；"))
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    } header: { Text("失效书源（\(pending.invalidCount)）") }
                }
            }
            .navigationTitle("书源导入预检")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        library.cancelPendingImport()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("选择") {
                        Button("全选") { selectedIDs = Set(pending.items.map(\.id)) }
                        Button("取消全选") { selectedIDs.removeAll() }
                        Button("仅选择新增") {
                            selectedIDs = Set(pending.items.filter { $0.existing == nil }.map(\.id))
                        }
                        Button("仅选择更新") {
                            selectedIDs = Set(pending.items.filter { $0.existing != nil }.map(\.id))
                        }
                    }
                    .disabled(pending.items.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        let ids = selectedIDs
                        isImporting = true
                        Task {
                            await library.commitPendingImport(
                                selectedIDs: ids,
                                keepOriginalName: keepOriginalName,
                                keepOriginalGroup: keepOriginalGroup,
                                keepOriginalEnabled: keepOriginalEnabled,
                                customGroup: customGroup.isEmpty ? nil : customGroup,
                                addCustomGroup: addCustomGroup
                            )
                            isImporting = false
                            if library.pendingImport == nil { dismiss() }
                            else {
                                let message = library.notice?.detail ?? "保存失败，请重试"
                                library.notice = nil
                                importError = message
                            }
                        }
                    }
                    .disabled(selectedIDs.isEmpty || isImporting)
                }
            }
        }
        .readingInteractiveDismissDisabled()
        .readingAlert("导入保存失败", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("好") {}
            .readingRole(.cancel)
        } message: { Text(importError ?? "") }
    }

    private func importCountCard(
        title: String,
        count: Int,
        color: Color,
        systemImage: String
    ) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            Text("\(count)")
                .font(.title2.bold())
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.1)))
    }
}

private struct CapabilityRow: View {
    let title: String
    let available: Bool

    var body: some View {
        ReadingLabeledContent(title) {
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundColor(available ? .green : .secondary)
                .accessibilityLabel(available ? "已配置" : "未配置")
        }
    }
}
