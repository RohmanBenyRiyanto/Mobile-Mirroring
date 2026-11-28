import DomainModels
import Foundation

enum NetworkEventMapper {
    static func map(_ event: Studio_Network_Inspection_Event, at now: Date = Date()) -> InspectionEvent? {
        guard case let .httpConnectionEvent(http)? = event.union else { return nil }
        let id = http.connectionID
        switch http.union {
        case let .httpRequestStarted(started)?:
            return .requestStarted(id: id, url: started.url, method: started.method, headers: started.headers.map(header), at: now)
        case .httpRequestCompleted?: return .requestCompleted(id: id)
        case let .httpResponseStarted(started)?:
            return .responseStarted(id: id, status: Int(started.responseCode), headers: started.headers.map(header))
        case .httpResponseCompleted?: return .responseCompleted(id: id)
        case let .httpClosed(closed)?: return .closed(id: id, completed: closed.completed)
        case let .requestPayload(payload)?: return .requestPayload(id: id, data: payload.payload)
        case let .responsePayload(payload)?: return .responsePayload(id: id, data: payload.payload)
        case .httpResponseIntercepted?, .httpThread?, nil: return nil
        }
    }

    private static func header(_ header: Studio_Network_Inspection_HttpConnectionEvent.Header) -> HTTPHeader {
        HTTPHeader(name: header.key, value: header.values.joined(separator: ", "))
    }
}
