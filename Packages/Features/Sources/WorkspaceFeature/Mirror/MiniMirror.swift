import AppKit
import AVFoundation
import DomainModels
import Media
import SwiftUI
import Theme

/// A small always-on-top copy of the phone's picture. It only shows; the main window stays the place to touch and type.
public struct MiniMirrorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isHovering = false

    public init() {}

    public var body: some View {
        Group {
            if let session = model.active {
                MiniLayerView(decoder: session.scrcpy.decoder)
                    .aspectRatio(model.videoSize, contentMode: .fit)
                    .overlay(alignment: .bottom) { if isHovering { controls }}
                    .animated(value: isHovering)
            } else {
                Text("No phone is connected.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 120, minHeight: 200)
        .background(MiniWindowStyler(videoSize: model.videoSize))
        .onHover { isHovering = $0 }
    }

    private var controls: some View {
        HStack(spacing: Theme.Space.s4) {
            Button { model.press(.back) } label: { Image(systemName: "chevron.backward") }.help("Back")
            Button { model.press(.home) } label: { Image(systemName: "circle") }.help("Home")
            Button { model.press(.appSwitch) } label: { Image(systemName: "square.on.square") }.help("Recents")
            Button { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.level == .normal && $0.canBecomeMain }?.makeKeyAndOrderFront(nil) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }.help("Open the main window")
        }
        .buttonStyle(.plain).labelStyle(.iconOnly)
        .padding(.horizontal, Theme.Space.s4).padding(.vertical, Theme.Space.s2)
        .background(.regularMaterial, in: Capsule())
        .padding(Theme.Space.s3)
        .transition(.opacity)
    }
}

private struct MiniLayerView: NSViewRepresentable {
    let decoder: VideoDecoder

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = decoder.makeMirrorLayer()
        view.layer = layer
        view.wantsLayer = true
        context.coordinator.layer = layer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let layer = coordinator.layer { coordinator.decoder?.removeMirrorLayer(layer) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(decoder: decoder) }

    final class Coordinator {
        var layer: AVSampleBufferDisplayLayer?
        weak var decoder: VideoDecoder?
        init(decoder: VideoDecoder) { self.decoder = decoder }
    }
}

private struct MiniWindowStyler: NSViewRepresentable {
    let videoSize: CGSize

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            if videoSize.width > 0, videoSize.height > 0 { window.contentAspectRatio = videoSize }
        }
    }
}
