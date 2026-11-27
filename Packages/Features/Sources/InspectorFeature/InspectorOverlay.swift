import SwiftUI
import DomainModels

public struct InspectorOverlay: View {
    @ObservedObject public var inspector: InspectorModel
    public let videoSize: CGSize
    public let densityScale: Double?

    public init(inspector: InspectorModel, videoSize: CGSize, densityScale: Double?) {
        self.inspector = inspector
        self.videoSize = videoSize
        self.densityScale = densityScale
    }

    private var cardAlignment: Alignment {
        guard let node = inspector.hovered, let screen = inspector.hierarchy?.screenSize, screen.height > 0 else { return .topLeading }
        return node.bounds.midY < screen.height / 2 ? .bottomLeading : .topLeading
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let node = inspector.hovered, let screen = inspector.hierarchy?.screenSize, screen.width > 0 {
                    let mapper = CoordinateMapper(viewSize: proxy.size, frameSize: videoSize)
                    let rect = mapper.viewRect(forRatioRect: CGRect(x: node.bounds.minX / screen.width, y: node.bounds.minY / screen.height,
                                                                    width: node.bounds.width / screen.width, height: node.bounds.height / screen.height))
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.15))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
                InspectorCard(inspector: inspector, densityScale: densityScale)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cardAlignment)
            }
            .allowsHitTesting(false)
        }
    }
}

public struct InspectorCard: View {
    @ObservedObject public var inspector: InspectorModel
    public let densityScale: Double?

    public init(inspector: InspectorModel, densityScale: Double?) {
        self.inspector = inspector
        self.densityScale = densityScale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch inspector.status {
            case .off:
                EmptyView()
            case .reading:
                Text("Reading the screen…")
            case let .failed(message):
                Text(message).foregroundStyle(.red)
            case .ready:
                if let node = inspector.hovered {
                    let measurements = NodeMeasurements(node: node, densityScale: densityScale)
                    Text(node.shortClassName).font(.headline)
                    if !node.resourceID.isEmpty { row("id", node.resourceID) }
                    if !node.text.isEmpty { row("text", node.text) }
                    if !node.contentDescription.isEmpty { row("desc", node.contentDescription) }
                    row("size", measurements.pixelText)
                    if let dp = measurements.dpText { row("", dp) }
                    if node.isClickable { Text("clickable").foregroundStyle(.secondary) }
                    Text("Click to copy").font(.caption2).foregroundStyle(.secondary)
                } else if !inspector.hasDetail {
                    Text("This screen shows no elements (games usually draw everything themselves).")
                } else {
                    Text("Point at an element")
                }
            }
        }
        .font(.caption.monospaced())
        .padding(8)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            Text(value).lineLimit(3).textSelection(.disabled)
        }
    }
}
