import Foundation

/// Position of a pointer event in video-frame pixels, plus the frame size it refers to.
public struct TouchPosition: Equatable {
    public var x: Int32
    public var y: Int32
    public var frameWidth: UInt16
    public var frameHeight: UInt16

    public init(x: Int32, y: Int32, frameWidth: UInt16, frameHeight: UInt16) {
        self.x = x
        self.y = y
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }

    fileprivate func write(to data: inout Data) {
        data.appendBigEndian(x)
        data.appendBigEndian(y)
        data.appendBigEndian(frameWidth)
        data.appendBigEndian(frameHeight)
    }
}

public enum KeyAction: UInt8 { case down = 0, up = 1 }
public enum TouchAction: UInt8 { case down = 0, up = 1, move = 2 }
public enum CopyKey: UInt8 { case none = 0, copy = 1, cut = 2 }

public enum MouseButton {
    public static let primary: UInt32 = 1 << 0
}

/// Identifies the pointer a touch belongs to. The server tracks up to 10 distinct ids at once.
public struct PointerID: RawRepresentable, Hashable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    /// A mouse; with only the primary button held the server injects it as a finger.
    public static let mouse = PointerID(rawValue: 0xFFFF_FFFF_FFFF_FFFF)
    public static let finger = PointerID(rawValue: 0xFFFF_FFFF_FFFF_FFFE)
    public static let virtualFinger = PointerID(rawValue: 0xFFFF_FFFF_FFFF_FFFD)

    /// The server tracks at most this many simultaneous pointers.
    public static let slotCount = 10

    public static func slot(_ slot: Int) -> PointerID {
        precondition((0..<slotCount).contains(slot), "pointer slot out of range")
        return PointerID(rawValue: UInt64(slot))
    }
}

/// Client-to-device messages in scrcpy's wire format (v5.0.1).
public enum ControlMessage: Equatable {
    case keycode(KeyAction, AndroidKeyCode)
    case text(String)
    case touch(TouchAction, TouchPosition, pressure: Float, pointer: PointerID = .mouse)
    case scroll(TouchPosition, horizontal: Float, vertical: Float)
    case backOrScreenOn(KeyAction)
    case expandNotificationPanel
    case expandSettingsPanel
    case collapsePanels
    case getClipboard(CopyKey)
    case setClipboard(String, paste: Bool)
    case setDisplayPower(Bool)
    case rotateDevice
    case resetVideo

    public static let maxTextBytes = 300
    public static let maxClipboardBytes = (1 << 18) - 14

    private enum TypeID: UInt8 {
        case keycode = 0, text, touch, scroll, backOrScreenOn
        case expandNotificationPanel, expandSettingsPanel, collapsePanels
        case getClipboard, setClipboard, setDisplayPower, rotateDevice
        case resetVideo = 17
    }

    public var serialized: Data {
        var data = Data()
        switch self {
        case let .keycode(action, code):
            data.append(TypeID.keycode.rawValue)
            data.append(action.rawValue)
            data.appendBigEndian(code.rawValue)
            data.appendBigEndian(UInt32(0))
            data.appendBigEndian(UInt32(0))

        case let .text(text):
            data.append(TypeID.text.rawValue)
            let bytes = text.utf8Prefix(maxBytes: Self.maxTextBytes)
            data.appendBigEndian(UInt32(bytes.count))
            data.append(bytes)

        case let .touch(action, position, pressure, pointer):
            let buttons: UInt32 = action == .up ? 0 : MouseButton.primary
            data.append(TypeID.touch.rawValue)
            data.append(action.rawValue)
            data.appendBigEndian(pointer.rawValue)
            position.write(to: &data)
            data.appendBigEndian(Self.unsignedFixedPoint(pressure))
            data.appendBigEndian(MouseButton.primary)
            data.appendBigEndian(buttons)

        case let .scroll(position, horizontal, vertical):
            data.append(TypeID.scroll.rawValue)
            position.write(to: &data)
            data.appendBigEndian(Self.signedFixedPoint(horizontal / 16))
            data.appendBigEndian(Self.signedFixedPoint(vertical / 16))
            data.appendBigEndian(UInt32(0))

        case let .backOrScreenOn(action):
            data.append(TypeID.backOrScreenOn.rawValue)
            data.append(action.rawValue)

        case .expandNotificationPanel: data.append(TypeID.expandNotificationPanel.rawValue)
        case .expandSettingsPanel: data.append(TypeID.expandSettingsPanel.rawValue)
        case .collapsePanels: data.append(TypeID.collapsePanels.rawValue)
        case .rotateDevice: data.append(TypeID.rotateDevice.rawValue)
        case .resetVideo: data.append(TypeID.resetVideo.rawValue)

        case let .getClipboard(copyKey):
            data.append(TypeID.getClipboard.rawValue)
            data.append(copyKey.rawValue)

        case let .setClipboard(text, paste):
            data.append(TypeID.setClipboard.rawValue)
            data.appendBigEndian(UInt64(0)) // sequence 0: no acknowledgement requested
            data.append(paste ? 1 : 0)
            let bytes = text.utf8Prefix(maxBytes: Self.maxClipboardBytes)
            data.appendBigEndian(UInt32(bytes.count))
            data.append(bytes)

        case let .setDisplayPower(on):
            data.append(TypeID.setDisplayPower.rawValue)
            data.append(on ? 1 : 0)
        }
        return data
    }

    // MARK: Fixed-point encodings used by the protocol

    /// Encodes a [0, 1] value as an unsigned 16-bit fixed-point number, as scrcpy expects.
    public static func unsignedFixedPoint(_ value: Float) -> UInt16 {
        UInt16(min(min(max(value, 0), 1) * 65536, 65535))
    }

    /// Encodes a [-1, 1] value as a signed 16-bit fixed-point number, as scrcpy expects.
    public static func signedFixedPoint(_ value: Float) -> Int16 {
        Int16(min(max(min(max(value, -1), 1) * 32768, -32768), 32767))
    }
}
