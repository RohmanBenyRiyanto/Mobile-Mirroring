import Foundation

/// Receives files opened from Finder. Files that arrive before a handler is set (a double-click that launches the
/// app) wait here and are handed over as soon as one is.
public final class FileOpenInbox {
    public var handler: (([URL]) -> Void)? {
        didSet {
            guard let handler, !pending.isEmpty else { return }
            let urls = pending
            pending = []
            handler(urls)
        }
    }

    private var pending: [URL] = []

    public init() {}

    public func receive(_ urls: [URL]) {
        if let handler { handler(urls) } else { pending += urls }
    }
}
