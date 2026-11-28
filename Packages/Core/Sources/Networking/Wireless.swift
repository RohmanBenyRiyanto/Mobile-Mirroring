import Darwin
import Foundation

public enum WirelessInput {
    public static func isValidAddress(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = Int(parts[1]), (1...65535).contains(port) else { return false }
        let host = parts[0]
        return !host.isEmpty && host.count <= 253
            && host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    public static func isValidPairingCode(_ text: String) -> Bool {
        text.count == 6 && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    public static func interfaces(inIPOutput output: String) -> [IPv4Interface] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let inet = fields.firstIndex(of: "inet"), inet >= 1, inet + 1 < fields.count else { return nil }
            let name = String(fields[inet - 1])
            let parts = fields[inet + 1].split(separator: "/")
            guard name != "lo", parts.count == 2, let address = IPv4Interface.parse(String(parts[0])),
                  let prefix = Int(parts[1]), (0...32).contains(prefix)
            else { return nil }
            return IPv4Interface(name: name, address: address, prefix: prefix)
        }
    }

    public static func networkMismatch(address: String, mac: [IPv4Interface]) -> (phone: String, mac: String)? {
        guard isValidAddress(address), let host = address.split(separator: ":").first.map(String.init),
              let ip = IPv4Interface.parse(host), let reference = mac.first(where: { $0.name.hasPrefix("en") }) ?? mac.first else { return nil }
        let phone = IPv4Interface(name: "phone", address: ip, prefix: 24)
        return mac.contains { $0.shares(networkWith: phone) } ? nil : (host, reference.text)
    }

    public static func reachableAddress(phone: [IPv4Interface], mac: [IPv4Interface]) -> IPv4Interface? {
        phone.first { candidate in mac.contains { $0.shares(networkWith: candidate) } }
    }
}

public struct IPv4Interface: Equatable {
    public let name: String
    public let address: UInt32
    public let prefix: Int

    public init(name: String, address: UInt32, prefix: Int) {
        self.name = name
        self.address = address
        self.prefix = prefix
    }

    public var text: String { Self.format(address) }

    public func shares(networkWith other: IPv4Interface) -> Bool {
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - min(prefix, other.prefix))
        return address & mask == other.address & mask
    }

    public static func parse(_ text: String) -> UInt32? {
        let octets = text.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
        guard octets.count == 4, text.split(separator: ".", omittingEmptySubsequences: false).count == 4 else { return nil }
        return octets.reduce(0) { $0 << 8 | UInt32($1) }
    }

    public static func format(_ address: UInt32) -> String {
        (0..<4).map { String(address >> UInt32(24 - 8 * $0) & 0xFF) }.joined(separator: ".")
    }

    public static func ofThisMac() -> [IPv4Interface] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        return sequence(first: first, next: { $0.pointee.ifa_next }).compactMap { entry in
            let interface = entry.pointee
            guard interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0, interface.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = interface.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let netmask = interface.ifa_netmask
            else { return nil }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            return IPv4Interface(name: String(cString: interface.ifa_name), address: ip, prefix: mask.nonzeroBitCount)
        }
    }
}

extension ADB {
    public static let defaultTCPPort = 5555

    public func enableWireless(serial: String, macNetworks: [IPv4Interface] = IPv4Interface.ofThisMac()) throws -> String {
        let output = String(decoding: try run(["-s", serial, "shell", "ip", "-o", "-f", "inet", "addr", "show"], timeout: 10), as: UTF8.self)
        guard let phone = WirelessInput.reachableAddress(phone: WirelessInput.interfaces(inIPOutput: output), mac: macNetworks) else {
            throw ADBError.failed(command: "wireless", message: "The phone and this Mac are not on the same network. Join the same Wi-Fi, or turn on the phone's hotspot and connect this Mac to it.")
        }
        try run(["-s", serial, "tcpip", String(Self.defaultTCPPort)], timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        let address = "\(phone.text):\(Self.defaultTCPPort)"
        try connect(address: address)
        return address
    }

    public func switchToUSB(serial: String) throws {
        guard serial.contains(":"), AndroidDevice.isValidSerial(serial) else { throw ADBError.failed(command: "usb", message: "This phone is not connected over Wi-Fi.") }
        try run(["-s", serial, "usb"], timeout: 10)
        _ = try? run(["disconnect", serial], timeout: 5)
    }

    public func pair(address: String, code: String) throws {
        guard WirelessInput.isValidAddress(address), WirelessInput.isValidPairingCode(code) else {
            throw ADBError.failed(command: "pair", message: "Enter the address as host:port and the 6-digit code.")
        }
        let output = String(decoding: try run(["pair", address], input: Data((code + "\n").utf8), timeout: 20), as: UTF8.self)
        guard output.localizedCaseInsensitiveContains("Successfully paired") else {
            throw ADBError.failed(command: "pair", message: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func connect(address: String) throws {
        guard WirelessInput.isValidAddress(address) else {
            throw ADBError.failed(command: "connect", message: "Enter the address as host:port.")
        }
        let output = String(decoding: try run(["connect", address], timeout: 15), as: UTF8.self)
        guard output.contains("connected to") else {
            throw ADBError.failed(command: "connect", message: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
