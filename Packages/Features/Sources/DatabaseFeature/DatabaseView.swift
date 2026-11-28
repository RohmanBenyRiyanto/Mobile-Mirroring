import AppKit
import Components
import DomainModels
import SwiftUI
import Theme
import UniformTypeIdentifiers

/// A database browser modelled on Android Studio's Database Inspector: pick an app, open its tables in tabs, sort and page them,
/// run read-only queries, and optionally watch the file for changes.
public struct DatabaseView<Source: DatabaseSource>: View {
    @ObservedObject var source: Source
    @StateObject private var model = DatabaseModel()
    @State private var chosenApp: String?

    public init(source: Source) { self.source = source }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 190, idealWidth: 220, maxWidth: 300)
                detail.frame(minWidth: 440)
            }
        }
        .frame(minWidth: 780, minHeight: 440)
        .onAppear { model.makeBackend = { [source] package in try MainActor.assumeIsolated { try source.makeDatabaseBackend(package: package) } } }
        .onChange(of: chosenApp) { _, app in
            guard let app else { return }
            Task { await model.open(package: app) }
        }
        .onDisappear { model.reset() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: Theme.Space.s3) {
            SearchPicker(selection: $chosenApp, items: source.appPickerItems, isLoading: source.isLoadingApps, placeholder: "Choose an app",
                         selectionTitle: { InstalledApps.displayName(for: $0) },
                         footer: source.frontPackage.map { front in (title: LocalizedStringKey("Use app in front"), action: { chosenApp = front }) },
                         alignment: .leading, onOpen: { await source.loadInstalledApps() })
            if model.isBusy { ProgressView().controlSize(.small).transition(.opacity) }
            Spacer()
            Toggle("Live updates", isOn: Binding(get: { model.isLive }, set: { model.setLive($0) })).toggleStyle(.switch)
                .disabled(model.databases.isEmpty)
                .help("Copy the databases again every two seconds and refresh when it changes")
        }
        .padding(.horizontal, Theme.Space.s3).padding(.vertical, Theme.Space.s2)
        .animated(value: model.isBusy)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List {
            if model.databases.isEmpty {
                Text(model.isBusy ? "" : "Choose an app to see its databases.").foregroundStyle(.secondary)
            }
            ForEach(model.databases) { database in
                Section {
                    if let error = database.error { Text(verbatim: error).font(Theme.Font.caption).foregroundStyle(.orange) }
                    if !database.isLoaded { LoadingLabel("Reading the phone") }
                    ForEach(database.tables) { table in
                        Button { Task { await model.openTable(table.name, in: database.file) } } label: {
                            HStack(spacing: Theme.Space.s2) {
                                Image(systemName: table.isView ? "eye" : "tablecells").foregroundStyle(Theme.Palette.accentText.color).frame(width: 16)
                                Text(verbatim: table.name).font(Theme.Font.mono).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                if let count = table.rowCount { Text(verbatim: count.formatted()).font(Theme.Font.monoCaption).foregroundStyle(.secondary) }
                            }
                            .opacity(table.isSystem ? 0.55 : 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fontWeight(model.selectedTab?.kind == .table(file: database.file, name: table.name) ? .semibold : .regular)
                    }
                } header: {
                    HStack {
                        Label { Text(verbatim: database.file).font(Theme.Font.monoCaption) } icon: { Image(systemName: "externaldrive") }
                        Spacer()
                        Button { model.newQuery(in: database.file) } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                            .buttonStyle(.borderless).help("New query").accessibilityLabel("New query")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animated(value: model.databases)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            if let message = model.errorMessage {
                Label(LocalizedStringKey(message), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .padding(Theme.Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            tabBar
            Divider()
            if let tab = model.selectedTab {
                TabContent(model: model, tab: tab)
            } else {
                VStack(spacing: Theme.Space.s2) {
                    Image(systemName: "externaldrive").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("No table open").font(Theme.Font.headline)
                    Text("Pick a table on the left, or start a new query.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: Theme.Space.s1) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s1) {
                    ForEach(model.tabs) { tab in
                        HStack(spacing: Theme.Space.s1) {
                            Image(systemName: tab.isQuery ? "chevron.left.forwardslash.chevron.right" : "tablecells").font(.system(size: 10))
                            Text(verbatim: tab.title).lineLimit(1)
                            Button { model.close(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                                .buttonStyle(.plain).accessibilityLabel("Close")
                        }
                        .padding(.horizontal, Theme.Space.s2).padding(.vertical, 4)
                        .background(tab.id == model.selectedTabID ? Theme.Palette.control.color : .clear, in: Capsule())
                        .foregroundStyle(tab.id == model.selectedTabID ? .primary : .secondary)
                        .contentShape(Capsule())
                        .onTapGesture { model.selectedTabID = tab.id }
                    }
                }
            }
            Button { model.newQuery() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless).help("New query").accessibilityLabel("New query")
                .disabled(model.databases.isEmpty)
        }
        .padding(.horizontal, Theme.Space.s3).padding(.vertical, Theme.Space.s2)
    }
}

// MARK: - A tab

private struct TabContent: View {
    @ObservedObject var model: DatabaseModel
    let tab: InspectorTab

    var body: some View {
        VStack(spacing: 0) {
            if tab.isQuery { queryEditor; Divider() } else { tableBar; filterBar; Divider() }
            if let error = tab.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .padding(Theme.Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            if tab.rows.isEmpty && tab.error == nil && !tab.isQuery {
                Text(tab.header.isEmpty ? "No rows" : "No rows yet. The columns are \(tab.header.joined(separator: ", ")).").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            ResultGrid(tab: tab, sort: { column in Task { await model.sort(tab.id, by: column) } }, sortable: tab.tableName != nil && !tab.showsStructure)
            }
            Divider()
            footer
        }
    }

    private var tableBar: some View {
        HStack(spacing: Theme.Space.s2) {
            let first = tab.page * SQLiteQuery.pageSize + 1
            Text(rangeText(first: first)).font(Theme.Font.monoCaption).foregroundStyle(.secondary)
            Spacer()
            Picker("View", selection: Binding(get: { tab.showsStructure }, set: { on in Task { await model.setShowsStructure(on, for: tab.id) } })) {
                Text("Data").tag(false)
                Text("Structure").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            Button { Task { await model.turnPage(tab.id, by: -1) } } label: { Image(systemName: "chevron.left") }
                .disabled(tab.page == 0).help("Previous page").accessibilityLabel("Previous page")
            Button { Task { await model.turnPage(tab.id, by: 1) } } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward(tab)).help("Next page").accessibilityLabel("Next page")
            Button { Task { await model.refresh(tab.id) } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh").accessibilityLabel("Refresh")
            Button("Export CSV", action: export).disabled(tab.result.isEmpty)
        }
        .padding(.horizontal, Theme.Space.s3).padding(.vertical, Theme.Space.s2)
    }

    /// A form instead of typing SQL: pick a column and a condition, and the table is filtered.
    @State private var filterColumn = ""
    @State private var filterOperation = TableFilter.Operation.contains
    @State private var filterValue = ""

    @ViewBuilder private var filterBar: some View {
        if !tab.showsStructure, !tab.header.isEmpty {
            HStack(spacing: Theme.Space.s2) {
                Picker("Column", selection: Binding(get: { filterColumn.isEmpty ? (tab.header.first ?? "") : filterColumn }, set: { filterColumn = $0 })) {
                    ForEach(tab.header, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .labelsHidden().frame(width: 150)
                Picker("Condition", selection: $filterOperation) {
                    ForEach(TableFilter.Operation.allCases) { Text(verbatim: $0.symbol).tag($0) }
                }
                .labelsHidden().frame(width: 120)
                if filterOperation.needsValue {
                    TextField("Value", text: $filterValue).textFieldStyle(.roundedBorder).onSubmit(applyFilter)
                } else {
                    Spacer()
                }
                Button("Filter", action: applyFilter)
                if tab.filter != nil {
                    Button("Clear") { filterValue = ""; Task { await model.setFilter(nil, for: tab.id) } }
                }
            }
            .padding(.horizontal, Theme.Space.s3).padding(.bottom, Theme.Space.s2)
        }
    }

    private func applyFilter() {
        let column = filterColumn.isEmpty ? (tab.header.first ?? "") : filterColumn
        Task { await model.setFilter(TableFilter(column: column, operation: filterOperation, value: filterValue), for: tab.id) }
    }

    private func rangeText(first: Int) -> String {
        guard !tab.rows.isEmpty else { return String(localized: "No rows") }
        let last = first + tab.rows.count - 1
        if let total = model.totalRows(of: tab) { return "\(first)–\(last) / \(total)" }
        return "\(first)–\(last)"
    }

    private var queryEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            TextEditor(text: Binding(get: { tab.sql }, set: { model.setSQL($0, for: tab.id) }))
                .font(Theme.Font.mono).frame(height: 92).scrollContentBackground(.hidden)
                .padding(Theme.Space.s2).background(Theme.Palette.control.color.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.field))
            HStack(spacing: Theme.Space.s2) {
                Button("Run") { Task { await model.refresh(tab.id) } }.prominentAction().keyboardShortcut(.return, modifiers: .command)
                    .disabled(tab.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Menu("Templates") {
                    ForEach(SQLiteQuery.templates(table: model.tables(in: tab.file).first { !$0.isSystem }?.name, columns: []), id: \.title) { template in
                        Button(LocalizedStringKey(template.title)) { model.insert(template.sql, into: tab.id, replacing: true) }
                    }
                }
                .fixedSize()
                Menu("Insert") {
                    Section("Tables") {
                        ForEach(model.tables(in: tab.file)) { table in Button(table.name) { model.insert(SQLiteQuery.quoted(table.name), into: tab.id) } }
                    }
                    if let other = model.tabs.first(where: { $0.tableName != nil && $0.file == tab.file }), !other.header.isEmpty {
                        Section("Columns of \(other.tableName ?? "")") {
                            ForEach(other.header, id: \.self) { column in Button(column) { model.insert(SQLiteQuery.quoted(column), into: tab.id) } }
                        }
                    }
                }
                .fixedSize()
                Menu("History") {
                    if model.history.isEmpty { Text("Nothing yet") }
                    ForEach(model.history, id: \.self) { sql in Button(sql.replacingOccurrences(of: "\n", with: " ")) { model.setSQL(sql, for: tab.id) } }
                }
                .fixedSize()
                Menu("Database") {
                    ForEach(model.databases) { database in Button(database.file) { model.moveQuery(tab.id, to: database.file) } }
                }
                .fixedSize()
                Spacer()
                Text("Read-only: only SELECT, WITH, EXPLAIN and table info run here.").font(Theme.Font.caption).foregroundStyle(.secondary)
                Button("Export CSV", action: export).disabled(tab.result.isEmpty)
            }
        }
        .padding(Theme.Space.s3)
    }

    private var footer: some View {
        HStack {
            Text("\(tab.rows.count) rows").font(Theme.Font.caption).foregroundStyle(.secondary)
            if tab.isTruncated { Text("Showing the first 1,000 rows.").font(Theme.Font.caption).foregroundStyle(.secondary) }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.s3).padding(.vertical, Theme.Space.s1)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(tab.title).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.csv(for: tab).write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Grid

private struct ResultGrid: View {
    let tab: InspectorTab
    let sort: (String) -> Void
    let sortable: Bool

    /// Wide enough for the longest value in a column (capped), so columns look like a table rather than equal slabs.
    private func widths() -> [CGFloat] {
        tab.header.indices.map { column in
            let longest = ([tab.header[column]] + tab.rows.prefix(60).map { $0.indices.contains(column) ? $0[column] : "" }).map(\.count).max() ?? 4
            return min(max(CGFloat(longest) * 8 + 28, 90), 320)
        }
    }

    var body: some View {
        let widths = widths()
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(Array(tab.rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 0) {
                            Text(verbatim: String(tab.page * SQLiteQuery.pageSize + index + 1)).font(Theme.Font.monoCaption).foregroundStyle(.tertiary)
                                .frame(width: 48, alignment: .trailing).padding(.trailing, Theme.Space.s2)
                            ForEach(Array(widths.enumerated()), id: \.offset) { column, width in
                                Text(verbatim: row.indices.contains(column) ? row[column] : "").font(Theme.Font.mono).lineLimit(1).truncationMode(.tail)
                                    .frame(width: width, alignment: .leading).padding(.horizontal, Theme.Space.s2).textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 3)
                        .background(index.isMultiple(of: 2) ? Color.clear : Theme.Palette.control.color.opacity(0.3))
                    }
                } header: {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 48 + Theme.Space.s2)
                        ForEach(Array(widths.enumerated()), id: \.offset) { column, width in
                            Button { sort(tab.header[column]) } label: {
                                HStack(spacing: 4) {
                                    Text(verbatim: tab.header[column]).fontWeight(.semibold).lineLimit(1)
                                    if sortable, tab.sortColumn == tab.header[column] { Image(systemName: tab.ascending ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold)) }
                                }
                                .frame(width: width, alignment: .leading).padding(.horizontal, Theme.Space.s2).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(!sortable)
                        }
                    }
                    .font(Theme.Font.monoCaption).padding(.vertical, 5).background(.bar)
                }
            }
        }
    }
}
