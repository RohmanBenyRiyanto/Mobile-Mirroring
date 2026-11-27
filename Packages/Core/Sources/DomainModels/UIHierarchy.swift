import CoreGraphics
import Foundation

/// One element of the phone's screen, as `uiautomator dump` reports it.
public struct UINode: Equatable, Identifiable {
    public let id: Int
    public let depth: Int
    public let className: String
    public let resourceID: String
    public let text: String
    public let contentDescription: String
    public let package: String
    /// In pixels of the phone's screen.
    public let bounds: CGRect
    public let isClickable: Bool
    public let isEnabled: Bool

    public init(id: Int, depth: Int, className: String, resourceID: String, text: String, contentDescription: String, package: String, bounds: CGRect, isClickable: Bool, isEnabled: Bool) {
        self.id = id
        self.depth = depth
        self.className = className
        self.resourceID = resourceID
        self.text = text
        self.contentDescription = contentDescription
        self.package = package
        self.bounds = bounds
        self.isClickable = isClickable
        self.isEnabled = isEnabled
    }

    /// The class without its package ("android.widget.Button" → "Button").
    public var shortClassName: String { className.split(separator: ".").last.map(String.init) ?? className }
    /// The id without its package ("com.app:id/play" → "play").
    public var shortResourceID: String { resourceID.split(separator: "/").last.map(String.init) ?? resourceID }
}

/// The elements on the phone's screen at one moment.
public struct UIHierarchy: Equatable {
    /// In document order: parents before children, later siblings after earlier ones (later is drawn on top).
    public let nodes: [UINode]

    public init(nodes: [UINode]) {
        self.nodes = nodes
    }

    /// The screen's size in pixels (the root element covers it).
    public var screenSize: CGSize? { nodes.first.map { $0.bounds.size } }

    /// The element under a point given as a 0…1 ratio across the screen: the deepest one, and among equals the
    /// one drawn last. Zero-area elements never match.
    public func node(atRatio ratio: CGPoint) -> UINode? {
        guard let screenSize else { return nil }
        let point = CGPoint(x: ratio.x * screenSize.width, y: ratio.y * screenSize.height)
        var best: UINode?
        for node in nodes where node.bounds.width > 0 && node.bounds.height > 0 && node.bounds.contains(point) {
            if best == nil || node.depth >= best!.depth { best = node }
        }
        return best
    }
}

public enum UIHierarchyParser {
    /// Largest dump accepted. A real screen is a few hundred KB.
    public static let maxBytes = 8 * 1024 * 1024
    public static let command = "uiautomator dump /dev/tty"

    /// Reads a dump. The tool prints a status sentence after `</hierarchy>`, which is ignored.
    public static func parse(_ data: Data) -> UIHierarchy? {
        guard data.count <= maxBytes else { return nil }
        let closing = Data("</hierarchy>".utf8)
        guard let end = data.range(of: closing) else { return nil }
        let delegate = Collector()
        let parser = XMLParser(data: data[..<end.upperBound])
        parser.shouldResolveExternalEntities = false // a dump is data, never a place to fetch things from
        parser.delegate = delegate
        guard parser.parse(), !delegate.nodes.isEmpty else { return nil }
        return UIHierarchy(nodes: delegate.nodes)
    }

    /// `[0,0][1080,2340]` → a rect. Nil for anything else.
    public static func bounds(from text: String) -> CGRect? {
        let numbers = text.split(whereSeparator: { !$0.isNumber && $0 != "-" }).compactMap { Double($0) }
        guard numbers.count == 4, numbers[2] >= numbers[0], numbers[3] >= numbers[1] else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var nodes: [UINode] = []
        private var depth = 0

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
                    attributes attrs: [String: String] = [:]) {
            guard element == "node" else { return }
            if let bounds = UIHierarchyParser.bounds(from: attrs["bounds"] ?? "") {
                nodes.append(UINode(id: nodes.count, depth: depth, className: attrs["class"] ?? "",
                                    resourceID: attrs["resource-id"] ?? "", text: attrs["text"] ?? "",
                                    contentDescription: attrs["content-desc"] ?? "", package: attrs["package"] ?? "",
                                    bounds: bounds, isClickable: attrs["clickable"] == "true", isEnabled: attrs["enabled"] != "false"))
            }
            depth += 1
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            if element == "node" { depth -= 1 }
        }
    }
}
