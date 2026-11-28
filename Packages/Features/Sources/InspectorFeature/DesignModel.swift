import AppKit
import CoreGraphics
import Foundation
import DomainModels
import Networking

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

    public var capturesPointer: Bool { tool != .off }

    private let fetchScreenshot: () async throws -> Data
    private var task: Task<Void, Never>?

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

    @discardableResult
    public func copyColor() -> String? {
        guard tool == .colorPicker, let color else { return nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(color.hex, forType: .string)
        return color.hex
    }

    public func reset() {
        setTool(.off)
        grid = .off
    }
}
