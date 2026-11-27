import AppKit
import DomainModels
import SwiftUI
import Theme

/// The docked inspector: the element tree with a filter, and the details of the chosen element.
public struct InspectorPanel: View {
    public static let width: CGFloat = 320
    @ObservedObject public var inspector: InspectorModel
    public let densityScale: Double?
    @State private var query = ""

    public init(inspector: InspectorModel, densityScale: Double?) {
        self.inspector = inspector
        self.densityScale = densityScale
    }

    private var nodes: [UINode] { inspector.hierarchy?.filtered(by: query) ?? [] }
    private var shown: UINode? { inspector.hovered ?? inspector.selected }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s2) {
                TextField("Filter", text: $query).textFieldStyle(.roundedBorder)
                Button { inspector.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh").accessibilityLabel("Refresh")
                Button { inspector.copyAll() } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy All").accessibilityLabel("Copy All").disabled(inspector.hierarchy == nil)
            }
            .padding(Theme.Space.s3)
            Divider()
            content
            Divider()
            details.frame(height: 150)
        }
        .frame(width: Self.width)
    }

    @ViewBuilder private var content: some View {
        switch inspector.status {
        case .off: Spacer()
        case .reading where inspector.hierarchy == nil: ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message): Text(LocalizedStringKey(message)).foregroundStyle(.secondary).padding(Theme.Space.s3).frame(maxHeight: .infinity, alignment: .top)
        default:
            if !inspector.hasDetail {
                Text("This screen shows no elements (games usually draw everything themselves).").foregroundStyle(.secondary).padding(Theme.Space.s3).frame(maxHeight: .infinity, alignment: .top)
            } else {
                List(nodes) { node in
                    Button { inspector.select(node) } label: { row(node) }
                        .buttonStyle(.plain)
                        .listRowBackground(node == inspector.selected ? Theme.Palette.accentText.color.opacity(0.18) : Color.clear)
                }
                .listStyle(.plain)
            }
        }
    }

    private func row(_ node: UINode) -> some View {
        HStack(spacing: Theme.Space.s1) {
            Text(verbatim: node.shortClassName).font(Theme.Font.mono).lineLimit(1)
            if !node.resourceID.isEmpty { Text(verbatim: "#" + node.shortResourceID).font(Theme.Font.monoCaption).foregroundStyle(.secondary).lineLimit(1) }
            if !node.text.isEmpty { Text(verbatim: "“\(node.text)”").font(Theme.Font.monoCaption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.leading, CGFloat(min(node.depth, 12)) * 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var details: some View {
        if let node = shown {
            let measurements = NodeMeasurements(node: node, densityScale: densityScale)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: node.className).font(Theme.Font.monoCaption).textSelection(.enabled)
                    detail("id", node.resourceID)
                    detail("text", node.text)
                    detail("desc", node.contentDescription)
                    detail("size", measurements.pixelText)
                    if let dp = measurements.dpText { detail("", dp) }
                    detail("flags", [node.isClickable ? "clickable" : nil, node.isEnabled ? nil : "disabled"].compactMap { $0 }.joined(separator: ", "))
                }
                .padding(Theme.Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Pick an element, or point at one on the phone.").foregroundStyle(.secondary).padding(Theme.Space.s3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func detail(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Text(verbatim: label).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                Text(verbatim: value).textSelection(.enabled)
            }
            .font(Theme.Font.monoCaption)
        }
    }
}
