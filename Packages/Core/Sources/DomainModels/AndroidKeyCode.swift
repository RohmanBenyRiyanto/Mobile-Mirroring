import Foundation

public enum AndroidKeyCode: UInt32 {
    case home = 3
    case back = 4
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case tab = 61
    case space = 62
    case enter = 66
    case delete = 67
    case menu = 82
    case pageUp = 92
    case pageDown = 93
    case escape = 111
    case forwardDelete = 112
    case moveHome = 122
    case moveEnd = 123
    case appSwitch = 187
    case letterA = 29, letterC = 31, letterV = 50, letterX = 52, letterY = 53, letterZ = 54

    public init?(macKeyCode: UInt16) {
        switch macKeyCode {
        case 36, 76: self = .enter
        case 48: self = .tab
        case 49: self = .space
        case 51: self = .delete
        case 53: self = .escape
        case 115: self = .moveHome
        case 116: self = .pageUp
        case 117: self = .forwardDelete
        case 119: self = .moveEnd
        case 121: self = .pageDown
        case 123: self = .dpadLeft
        case 124: self = .dpadRight
        case 125: self = .dpadDown
        case 126: self = .dpadUp
        default: return nil
        }
    }
}

public struct KeyMeta: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let shift = KeyMeta(rawValue: 0x0001 | 0x0040)
    public static let alt = KeyMeta(rawValue: 0x0002 | 0x0010)
    public static let ctrl = KeyMeta(rawValue: 0x1000 | 0x2000)
}
