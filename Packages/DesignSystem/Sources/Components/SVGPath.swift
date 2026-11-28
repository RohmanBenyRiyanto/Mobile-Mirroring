import CoreGraphics
import Foundation
import SwiftUI

public enum SVGPath {
    public static func parse(_ data: String) -> Path? {
        var scanner = Scanner(string: data)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t")
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        let commands = CharacterSet(charactersIn: "MLHVCAZ")

        func number() -> CGFloat? { scanner.scanDouble().map { CGFloat($0) } }
        func flag() -> Bool? { number().map { $0 != 0 } }

        while !scanner.isAtEnd {
            guard let letter = scanner.scanCharacters(from: commands)?.first else { return nil }
            switch letter {
            case "M":
                guard let x = number(), let y = number() else { return nil }
                current = CGPoint(x: x, y: y); start = current
                path.move(to: current)
            case "L":
                guard let x = number(), let y = number() else { return nil }
                current = CGPoint(x: x, y: y); path.addLine(to: current)
            case "H":
                guard let x = number() else { return nil }
                current.x = x; path.addLine(to: current)
            case "V":
                guard let y = number() else { return nil }
                current.y = y; path.addLine(to: current)
            case "C":
                guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return nil }
                current = CGPoint(x: x, y: y)
                path.addCurve(to: current, control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case "A":
                guard let rx = number(), let ry = number(), let rotation = number(), let large = flag(), let sweep = flag(),
                      let x = number(), let y = number() else { return nil }
                let end = CGPoint(x: x, y: y)
                addArc(to: &path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, largeArc: large, sweep: sweep)
                current = end
            default:
                path.closeSubpath()
                current = start
            }
        }
        return path
    }

    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotation: CGFloat, largeArc: Bool, sweep: Bool) {
        guard p0 != p1 else { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let (cosPhi, sinPhi) = (cos(phi), sin(phi))
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { let scale = lambda.squareRoot(); rx *= scale; ry *= scale }

        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : (max(0, numerator) / denominator).squareRoot()
        if largeArc == sweep { factor = -factor }
        let cxp = factor * rx * y1 / ry
        let cyp = -factor * ry * x1 / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let sign: CGFloat = (ux * vy - uy * vx) < 0 ? -1 : 1
            let cosine = (ux * vx + uy * vy) / ((ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot())
            return sign * acos(min(1, max(-1, cosine)))
        }
        let theta1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(step / 4)
        var angleStart = theta1
        for _ in 0..<segments {
            let angleEnd = angleStart + step
            func point(_ a: CGFloat, _ dxScale: CGFloat = 0, _ dyScale: CGFloat = 0) -> CGPoint {
                let ex = rx * (cos(a) + dxScale), ey = ry * (sin(a) + dyScale)
                return CGPoint(x: cosPhi * ex - sinPhi * ey + cx, y: sinPhi * ex + cosPhi * ey + cy)
            }
            let c1 = point(angleStart, -t * sin(angleStart), t * cos(angleStart))
            let c2 = point(angleEnd, t * sin(angleEnd), -t * cos(angleEnd))
            path.addCurve(to: point(angleEnd), control1: c1, control2: c2)
            angleStart = angleEnd
        }
    }
}
