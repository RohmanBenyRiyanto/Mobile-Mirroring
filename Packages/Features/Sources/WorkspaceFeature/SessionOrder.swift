import Foundation
import DomainModels

/// Rules for which phone is in front when several are mirrored at once.
public enum SessionOrder {
    /// After `removed` goes away: keep the active phone if it is still there, otherwise the neighbour
    /// the removed tab was next to (the previous one, or the first), or nothing when none are left.
    public static func activeSerial(afterRemoving removed: String, from serials: [String], active: String?) -> String? {
        let remaining = serials.filter { $0 != removed }
        if let active, active != removed, remaining.contains(active) { return active }
        guard let index = serials.firstIndex(of: removed) else { return remaining.first }
        return remaining.isEmpty ? nil : remaining[max(index - 1, 0)]
    }

    /// The port for the next session's OBS stream: the requested one, or the next free port above it.
    /// Several phones cannot listen on one port, so each gets its own.
    public static func streamPort(base: Int, taken: Set<Int>) -> Int {
        guard base > 0 else { return base } // 0 means "any free port"
        let range = MirrorSettings.streamPortRange
        let start = min(max(base, range.lowerBound), range.upperBound)
        for offset in 0..<range.count {
            let candidate = range.lowerBound + (start - range.lowerBound + offset) % range.count
            if !taken.contains(candidate) { return candidate }
        }
        return start
    }
}
