import AppKit
import Components
import DomainModels
import SwiftUI
import Theme
import UniformTypeIdentifiers

public struct DatabaseView<Source: DatabaseSource>: View {
    @ObservedObject var source: Source
    @StateObject private var model = DatabaseModel()

    public init(source: Source) { self.source = source }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s2) {
                SearchPicker(selection: Binding(get: { model.package.isEmpty ? nil : model.package }, set: { model.package = $0 ?? ""; open() }),
                             items: source.appPickerItems, isLoading: source.isLoadingApps, placeholder: "Choose an app",
                             selectionTitle: { InstalledApps.displayName(for: $0) },
                             footer: source.frontPackage.map { front in (title: LocalizedStringKey("Use app in front"), action: { model.package = front; open() }) },
                             alignment: .leading, onOpen: { await source.loadInstalledApps() })
                Button("Open", action: open).disabled(model.package.isEmpty || model.isBusy)
                Spacer()
            }
            .padding(Theme.Space.s3)
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 180, idealWidth: 200, maxWidth: 280)
                content.frame(minWidth: 420)
            }
        }
        .frame(minWidth: 760, minHeight: 440)
        .onDisappear { model.reset() }
    }

    private func open() { Task { await model.openPackage(adb: source.adb, serial: source.targetSerial) } }

    private var sidebar: some View {
        List {
            Section("Databases") {
                if model.files.isEmpty && !model.isBusy { Text("Choose an app to see its databases.").foregroundStyle(.secondary) }
                ForEach(model.files, id: \.self) { file in
                    Button { Task { await model.select(file) } } label: {
                        Text(verbatim: file).font(Theme.Font.mono).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .fontWeight(file == model.selectedFile ? .semibold : .regular)
                }
            }
            if !model.tables.isEmpty {
                Section("Tables") {
                    ForEach(model.tables, id: \.self) { table in
                        Button { Task { await model.show(table: table) } } label: { Text(verbatim: table).font(Theme.Font.mono).lineLimit(1) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if let message = model.errorMessage {
                Label(LocalizedStringKey(message), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).padding(Theme.Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            HStack(spacing: Theme.Space.s2) {
                TextField("", text: $model.sql, prompt: Text(verbatim: "SELECT * FROM table LIMIT 200"))
                    .textFieldStyle(.roundedBorder).font(Theme.Font.mono)
                    .onSubmit { Task { await model.run() } }
                Button("Run") { Task { await model.run() } }.disabled(model.sql.isEmpty || model.isBusy)
                Button("Export CSV", action: export).disabled(model.result.isEmpty)
            }
            .padding(Theme.Space.s3)
            Divider()
            ResultGrid(header: model.header, rows: model.rows)
                .overlay { if model.isBusy { ProgressView().controlSize(.regular).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) } }
                .animation(.easeInOut(duration: 0.15), value: model.isBusy)
            if model.isTruncated {
                Divider()
                Text("Showing the first 1,000 rows.").font(Theme.Font.caption).foregroundStyle(.secondary).padding(Theme.Space.s2)
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(model.selectedFile ?? "query").csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct ResultGrid: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        line(row, isHeader: false).background(index.isMultiple(of: 2) ? Color.clear : Theme.Palette.control.color.opacity(0.4))
                    }
                } header: {
                    line(header, isHeader: true).background(.bar)
                }
            }
        }
    }

    private func line(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(verbatim: cell).font(Theme.Font.mono).fontWeight(isHeader ? .semibold : .regular)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: 160, alignment: .leading).padding(.horizontal, Theme.Space.s2).padding(.vertical, 4)
                    .textSelection(.enabled)
            }
        }
    }
}
