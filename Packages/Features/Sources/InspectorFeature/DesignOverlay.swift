import SwiftUI
import DomainModels

/// The grid, crosshair and colour readout drawn over the mirror. It passes clicks through.
public struct DesignOverlay: View {
    @ObservedObject public var design: DesignModel
    public let videoSize: CGSize
    public let screenSize: CGSize
    public let densityScale: Double?

    public init(design: DesignModel, videoSize: CGSize, screenSize: CGSize, densityScale: Double?) {
        self.design = design
        self.videoSize = videoSize
        self.screenSize = screenSize
        self.densityScale = densityScale
    }

    public var body: some View {
        GeometryReader { proxy in
            let mapper = CoordinateMapper(viewSize: proxy.size, frameSize: videoSize)
            let video = mapper.videoRect
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawGrid(context, video: video)
                    drawCrosshair(context, mapper: mapper, video: video)
                }
                readout(mapper: mapper, in: proxy.size)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Drawing

    private func drawGrid(_ context: GraphicsContext, video: CGRect) {
        guard let step = design.grid.stepDP, let scale = densityScale else { return }
        let majorEvery = design.grid.majorEvery
        for (axis, extent, length) in [(0, screenSize.width, video.width), (1, screenSize.height, video.height)] {
            for line in DesignGrid.lines(extentPixels: extent, densityScale: scale, stepDP: step, viewLength: length, majorEvery: majorEvery) {
                var path = Path()
                if axis == 0 {
                    let x = video.minX + line.ratio * video.width
                    path.move(to: CGPoint(x: x, y: video.minY)); path.addLine(to: CGPoint(x: x, y: video.maxY))
                } else {
                    let y = video.minY + line.ratio * video.height
                    path.move(to: CGPoint(x: video.minX, y: y)); path.addLine(to: CGPoint(x: video.maxX, y: y))
                }
                context.stroke(path, with: .color(.red.opacity(line.isMajor ? 0.55 : 0.25)), lineWidth: line.isMajor ? 1 : 0.5)
            }
        }
    }

    private func drawCrosshair(_ context: GraphicsContext, mapper: CoordinateMapper, video: CGRect) {
        guard design.tool != .off, let ratio = design.pointer else { return }
        let point = mapper.viewPoint(forRatio: ratio)
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: video.minY)); path.addLine(to: CGPoint(x: point.x, y: video.maxY))
        path.move(to: CGPoint(x: video.minX, y: point.y)); path.addLine(to: CGPoint(x: video.maxX, y: point.y))
        context.stroke(path, with: .color(.cyan.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    // MARK: Readout

    @ViewBuilder
    private func readout(mapper: CoordinateMapper, in size: CGSize) -> some View {
        if design.tool != .off {
            let ratio = design.pointer
            let cross = ratio.flatMap { CrosshairReadout(ratio: $0, screenSize: screenSize, densityScale: densityScale) }
            let alignment: Alignment = (ratio?.y ?? 1) < 0.5 ? .bottomTrailing : .topTrailing
            VStack(alignment: .leading, spacing: 3) {
                if design.tool == .colorPicker { colorRows }
                if let cross {
                    Text(cross.pixelText)
                    if let dp = cross.dpText { Text(dp) }
                    Text(cross.edgesText).foregroundStyle(.secondary)
                } else {
                    Text("Point at the screen").foregroundStyle(.secondary)
                }
            }
            .font(.caption.monospaced())
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
    }

    @ViewBuilder
    private var colorRows: some View {
        switch design.snapshotStatus {
        case .reading, .none:
            Text("Reading the screen")
        case let .failed(message):
            Text(message).foregroundStyle(.red)
        case .ready:
            if let color = design.color {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: color.swatch)).frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.6)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(color.hex).font(.headline.monospaced())
                        Text(color.rgbText)
                    }
                }
                Text("Click to copy").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
