import Foundation

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
