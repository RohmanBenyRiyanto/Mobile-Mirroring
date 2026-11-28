import Foundation
import DomainModels

public enum SessionOrder {
    public static func activeSerial(afterRemoving removed: String, from serials: [String], active: String?) -> String? {
        let remaining = serials.filter { $0 != removed }
        if let active, active != removed, remaining.contains(active) { return active }
        guard let index = serials.firstIndex(of: removed) else { return remaining.first }
        return remaining.isEmpty ? nil : remaining[max(index - 1, 0)]
    }

    public static func streamPort(base: Int, taken: Set<Int>) -> Int {
        guard base > 0 else { return base }
        let range = MirrorSettings.streamPortRange
        let start = min(max(base, range.lowerBound), range.upperBound)
        for offset in 0..<range.count {
            let candidate = range.lowerBound + (start - range.lowerBound + offset) % range.count
            if !taken.contains(candidate) { return candidate }
        }
        return start
    }
}
