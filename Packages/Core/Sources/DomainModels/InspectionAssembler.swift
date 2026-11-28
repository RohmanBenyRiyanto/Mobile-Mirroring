import Foundation

/// What an agent inside a debuggable app reports about its HTTP calls, in plain values. The wire format is mapped to this elsewhere, so the
/// rules for putting a call together are plain code that is tested without a phone.
public enum InspectionEvent: Equatable, Sendable {
    case requestStarted(id: Int64, url: String, method: String, headers: [HTTPHeader], at: Date)
    case requestPayload(id: Int64, data: Data)
    case requestCompleted(id: Int64)
    case responseStarted(id: Int64, status: Int, headers: [HTTPHeader])
    case responsePayload(id: Int64, data: Data)
    case responseCompleted(id: Int64)
    case closed(id: Int64, completed: Bool)
}

/// Joins the events of each call into an `APICall` with its headers and bodies, as the API log shows it.
/// Unlike the proxy, this sees the contents of HTTPS calls: the agent reports them before they are encrypted.
public struct InspectionAssembler: Sendable {
    /// Calls that were not closed when this many others were open are dropped, so a leaky app cannot grow memory without bound.
    public static let maxOpenCalls = 256

    private struct Open {
        var call: APICall
        var details = APICallDetails()
        var started: Date
    }

    private var open: [Int64: Open] = [:]
    private var order: [Int64] = []
    private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) { self.clock = clock }

    /// The call as it stands after `event`, to show or update in the log; nil for an event of a call that was never started.
    public mutating func apply(_ event: InspectionEvent) -> APICall? {
        switch event {
        case let .requestStarted(id, url, method, headers, at):
            let parsed = URL(string: url)
            let host = parsed?.host ?? url
            var call = APICall(id: Int(truncatingIfNeeded: id), startedAt: at, method: method.uppercased(), host: host, url: url, isTunnel: false)
            call.isInspected = true
            var details = APICallDetails()
            details.requestHeaders = headers
            open[id] = Open(call: call, details: details, started: at)
            order.append(id)
            if order.count > Self.maxOpenCalls, let oldest = order.first { open[oldest] = nil; order.removeFirst() }
            return snapshot(id)
        case let .requestPayload(id, data):
            guard var entry = open[id] else { return nil }
            entry.details.requestBody.append(data.prefix(max(0, HTTPMessage.bodyCapture - entry.details.requestBody.count)))
            entry.details.requestBodyTruncated = entry.details.requestBodyTruncated || data.count > HTTPMessage.bodyCapture
            entry.call.sentBytes += data.count
            open[id] = entry
            return snapshot(id)
        case .requestCompleted:
            return nil
        case let .responseStarted(id, status, headers):
            guard var entry = open[id] else { return nil }
            entry.call.status = status
            entry.details.responseHeaders = headers
            entry.details.statusLine = "HTTP \(status)"
            open[id] = entry
            return snapshot(id)
        case let .responsePayload(id, data):
            guard var entry = open[id] else { return nil }
            entry.details.responseBody.append(data.prefix(max(0, HTTPMessage.bodyCapture - entry.details.responseBody.count)))
            entry.details.responseBodyTruncated = entry.details.responseBodyTruncated || entry.call.receivedBytes + data.count > HTTPMessage.bodyCapture
            entry.call.receivedBytes += data.count
            open[id] = entry
            return snapshot(id)
        case .responseCompleted:
            return nil
        case let .closed(id, completed):
            guard var entry = open[id] else { return nil }
            entry.call.durationMillis = max(0, Int(clock().timeIntervalSince(entry.started) * 1000))
            if !completed, entry.call.status == nil { entry.call.status = nil } // closed before an answer: shown as unfinished-with-time
            open[id] = entry
            let finished = snapshot(id)
            open[id] = nil
            order.removeAll { $0 == id }
            return finished
        }
    }

    private func snapshot(_ id: Int64) -> APICall? {
        guard var call = open[id]?.call else { return nil }
        call.details = open[id]?.details
        return call
    }
}
