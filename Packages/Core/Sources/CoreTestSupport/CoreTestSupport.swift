import Darwin
import DomainModels
import Foundation
import Media
import Networking
import TestSupport
import XCTest

/// Opens a TCP connection to a loopback port (what a client such as OBS does).
public func connectLoopback(port: UInt16) throws -> TCPStream {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard result == 0 else {
        Darwin.close(fd)
        throw SocketError.system("connect")
    }
    return TCPStream(fd: fd)
}

/// Encodes a test pattern with ffmpeg (no B-frames, like the Android encoder) and returns its NAL units.
public func makeH264NALUnits(in directory: URL, seconds: Int, fps: Int) throws -> [Data] {
    let clip = directory.appendingPathComponent("clip-\(UUID().uuidString).h264")
    let result = try runTool("ffmpeg", ["-v", "error", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=\(fps)", "-t", "\(seconds)",
                                        "-c:v", "libx264", "-bf", "0", "-g", "15", "-pix_fmt", "yuv420p", "-f", "h264", clip.path])
    guard result.status == 0 else { throw XCTSkip("ffmpeg could not encode the test clip") }
    return AnnexB.nalUnits(in: try Data(contentsOf: clip))
}

public let annexBStartCode = Data([0, 0, 0, 1])
