import AppKit
import CoreGraphics
import Foundation
import DomainModels
import Networking

/// Highlights the element under the pointer using a `uiautomator dump` snapshot, refreshed on request rather than live.
@MainActor
public final class InspectorModel: ObservableObject {
    public enum Status: Equatable {
        case off
        case reading
        case ready
        case failed(String)
    }

    @Published public private(set) var status = Status.off
    @Published public private(set) var hierarchy: UIHierarchy?
    @Published public private(set) var hovered: UINode?
    @Published public private(set) var selected: UINode?
    /// False when the dump holds only a full-screen element, as in games that draw themselves.
    public var hasDetail: Bool { (hierarchy?.nodes.count ?? 0) > 3 }

    public var isOn: Bool { status != .off }

    private let fetch: () async throws -> Data
    private var task: Task<Void, Never>?
    private var lastRatio: CGPoint?

    public init(fetch: @escaping () async throws -> Data) { self.fetch = fetch }

    public static func fetcher(adb: ADB, serial: String) -> () async throws -> Data {
        {
            try await Task.detached {
                try adb.run(["-s", serial, "exec-out", UIHierarchyParser.command], timeout: 20)
            }.value
        }
    }

    public func setOn(_ on: Bool) {
        if on {
            guard !isOn else { return }
            refresh()
        } else {
            task?.cancel()
            status = .off
            hierarchy = nil
            hovered = nil
            selected = nil
        }
    }

    public func select(_ node: UINode?) { selected = node }

    public func copyAll() {
        guard let hierarchy else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hierarchy.outline, forType: .string)
    }

    public func toggle() { setOn(!isOn) }

    public func refresh() {
        task?.cancel()
        status = .reading
        task = Task { [fetch] in
            let result: Result<UIHierarchy, Error>
            do {
                let data = try await fetch()
                if let parsed = UIHierarchyParser.parse(data) { result = .success(parsed) } else { result = .failure(InspectorError.unreadable) }
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, isOn else { return }
            switch result {
            case let .success(parsed):
                hierarchy = parsed
                status = .ready
                hovered = lastRatio.flatMap { parsed.node(atRatio: $0) }
            case let .failure(error):
                status = .failed(error.localizedDescription)
            }
        }
    }

    public func pointerMoved(to ratio: CGPoint?) {
        lastRatio = ratio
        let node = ratio.flatMap { hierarchy?.node(atRatio: $0) }
        if node != hovered { hovered = node }
    }

    /// Copies the hovered element's resource id, falling back to its text, description, then class name.
    @discardableResult
    public func copyHovered() -> String? {
        guard let node = hovered else { return nil }
        let value = [node.resourceID, node.text, node.contentDescription, node.className].first { !$0.isEmpty } ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        return value
    }
}

public enum InspectorError: LocalizedError {
    case unreadable
    public var errorDescription: String? { "The phone's screen could not be read (secure screens such as a lock screen hide their contents)." }
}

public struct NodeMeasurements: Equatable {
    public var pixels: CGRect
    public var dp: CGRect?

    public init(node: UINode, densityScale: Double?) {
        pixels = node.bounds
        if let scale = densityScale, scale > 0 {
            dp = CGRect(x: node.bounds.minX / scale, y: node.bounds.minY / scale,
                        width: node.bounds.width / scale, height: node.bounds.height / scale)
        }
    }

    private static func number(_ value: CGFloat) -> String {
        let rounded = (Double(value) * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    public var pixelText: String { "\(Self.number(pixels.width)) × \(Self.number(pixels.height)) px at \(Self.number(pixels.minX)), \(Self.number(pixels.minY))" }
    public var dpText: String? { dp.map { "\(Self.number($0.width)) × \(Self.number($0.height)) dp at \(Self.number($0.minX)), \(Self.number($0.minY))" } }
}
