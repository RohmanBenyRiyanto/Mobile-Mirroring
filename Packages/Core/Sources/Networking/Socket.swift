import Darwin
import Foundation

public enum SocketError: LocalizedError {
    case system(String)
    case addressInUse(UInt16)
    case timeout
    case closed

    public var errorDescription: String? {
        switch self {
        case let .system(call): return "Socket error in \(call) (errno \(errno))"
        case let .addressInUse(port): return "Port \(port) is already in use. Pick another port."
        case .timeout: return "Timed out waiting for the device to connect"
        case .closed: return "Connection closed"
        }
    }
}

public final class TCPStream: @unchecked Sendable {
    private let fd: Int32

    public init(fd: Int32) {
        self.fd = fd
        var enabled: Int32 = 1
        let size = socklen_t(MemoryLayout<Int32>.size)
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &enabled, size)
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, size)
    }

    deinit { Darwin.close(fd) }

    public func readExactly(_ count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let received = Darwin.read(fd, buffer.baseAddress! + offset, count - offset)
                if received > 0 {
                    offset += received
                } else if received == 0 {
                    throw SocketError.closed
                } else if errno != EINTR {
                    throw SocketError.system("read")
                }
            }
        }
        return data
    }

    public func write(_ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if sent > 0 {
                    offset += sent
                } else if sent < 0 && errno != EINTR {
                    throw SocketError.system("write")
                }
            }
        }
    }

    public func setTimeouts(seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, size)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, size)
    }

    public func readSome(limit: Int) throws -> Data {
        var data = Data(count: limit)
        let received = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, limit) }
        if received < 0 { throw SocketError.system("read") }
        return data.prefix(received)
    }

    public static func connect(host: String, port: Int, timeout: Int = 10) throws -> TCPStream {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &found) == 0, let first = found else { throw SocketError.system("resolve") }
        defer { freeaddrinfo(found) }
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            let fd = socket(entry.pointee.ai_family, entry.pointee.ai_socktype, entry.pointee.ai_protocol)
            if fd >= 0 {
                var limit = timeval(tv_sec: timeout, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
                if Darwin.connect(fd, entry.pointee.ai_addr, entry.pointee.ai_addrlen) == 0 { return TCPStream(fd: fd) }
                Darwin.close(fd)
            }
            cursor = entry.pointee.ai_next
        }
        throw SocketError.system("connect")
    }

    public func shutdown() { Darwin.shutdown(fd, SHUT_RDWR) }
}

public final class LoopbackListener {
    public let port: UInt16
    private let fd: Int32

    public init(port requestedPort: UInt16 = 0) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket") }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = requestedPort.bigEndian
        address.sin_addr = in_addr(s_addr: in_addr_t(0x7F00_0001).bigEndian)

        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            let inUse = errno == EADDRINUSE
            Darwin.close(fd)
            throw inUse ? SocketError.addressInUse(requestedPort) : SocketError.system("bind/listen")
        }

        var assigned = sockaddr_in()
        var assignedSize = size
        let named = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &assignedSize) }
        }
        guard named == 0 else {
            Darwin.close(fd)
            throw SocketError.system("getsockname")
        }

        self.fd = fd
        self.port = UInt16(bigEndian: assigned.sin_port)
    }

    deinit { Darwin.close(fd) }

    public func accept(timeout: TimeInterval, shouldContinue: () -> Bool = { true }) throws -> TCPStream {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, shouldContinue() {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready > 0 {
                let client = Darwin.accept(fd, nil, nil)
                guard client >= 0 else { throw SocketError.system("accept") }
                return TCPStream(fd: client)
            }
            if ready < 0 && errno != EINTR { throw SocketError.system("poll") }
        }
        throw SocketError.timeout
    }
}
