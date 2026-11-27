import AppKit
import CoreGraphics
import Foundation
import DomainModels
import Networking

/// Tools for checking a UI against a design: a dp grid, a crosshair with measurements, and a colour picker.
/// The colour picker reads a `screencap` still, so it sees the phone's real pixels, not the compressed stream.
@MainActor
public final class DesignModel: ObservableObject {
    public enum Tool: Equatable {
        case off, crosshair, colorPicker
    }

    public enum SnapshotStatus: Equatable {
        case none, reading, ready, failed(String)
    }

    @Published public var grid = DesignGrid.off
    @Published public private(set) var tool = Tool.off
    @Published public private(set) var pointer: CGPoint?
    @Published public private(set) var snapshot: PixelImage?
    @Published public private(set) var snapshotStatus = SnapshotStatus.none

    /// Whether clicks on the mirror are taken by the active tool instead of reaching the phone.
    public var capturesPointer: Bool { tool != .off }

    private let fetchScreenshot: () async throws -> Data
    private var task: Task<Void, Never>?

    /// `fetchScreenshot` returns a PNG of the phone's screen.
    public init(fetchScreenshot: @escaping () async throws -> Data) { self.fetchScreenshot = fetchScreenshot }

    public static func fetcher(adb: ADB, serial: String) -> () async throws -> Data {
        {
            try await Task.detached {
                try adb.run(["-s", serial, "exec-out", "screencap", "-p"], timeout: 20)
            }.value
        }
    }

    public func setTool(_ newTool: Tool) {
        guard newTool != tool else { return }
        tool = newTool
        pointer = nil
        task?.cancel()
        if newTool == .colorPicker {
            refresh()
        } else {
            snapshot = nil
            snapshotStatus = .none
        }
    }

    /// Takes a new still (after the screen changed).
    public func refresh() {
        guard tool == .colorPicker else { return }
        task?.cancel()
        snapshotStatus = .reading
        task = Task { [fetchScreenshot] in
            let image: PixelImage?
            var failure: String?
            do {
                image = PixelImage(png: try await fetchScreenshot())
                if image == nil { failure = "The screenshot could not be read." }
            } catch {
                image = nil
                failure = error.localizedDescription
            }
            guard !Task.isCancelled, tool == .colorPicker else { return }
            snapshot = image
            snapshotStatus = image != nil ? .ready : .failed(failure ?? "")
        }
    }

    public func pointerMoved(to ratio: CGPoint?) { if pointer != ratio { pointer = ratio } }

    public var color: PickedColor? { pointer.flatMap { snapshot?.color(atRatio: $0) } }

    /// Copies the colour under the pointer as `#RRGGBB`. Returns it, or nil when there is none.
    @discardableResult
    public func copyColor() -> String? {
        guard tool == .colorPicker, let color else { return nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(color.hex, forType: .string)
        return color.hex
    }

    /// Switches everything off (the connection ended).
    public func reset() {
        setTool(.off)
        grid = .off
    }
}
