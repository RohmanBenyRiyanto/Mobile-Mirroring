import AppKit

let size = NSSize(width: 660, height: 400)
let scale: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSGradient(colors: [NSColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1), NSColor(red: 0.86, green: 0.90, blue: 0.97, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: 90)
NSGradient(colors: [NSColor(red: 0.30, green: 0.55, blue: 1, alpha: 0.22), .clear])!
    .draw(fromCenter: NSPoint(x: 330, y: 230), radius: 0, toCenter: NSPoint(x: 330, y: 230), radius: 300, options: [])

let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor(white: 0.1, alpha: 1)]
let hint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.1, alpha: 0.6)]
func centered(_ text: String, y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
    let string = NSAttributedString(string: text, attributes: attributes)
    string.draw(at: NSPoint(x: (size.width - string.size().width) / 2, y: y))
}
centered("Install Benz Mirror", y: 332, attributes: title)
centered("Drag the app onto Applications", y: 306, attributes: hint)

let arrow = NSBezierPath()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 262, y: 210))
arrow.line(to: NSPoint(x: 394, y: 210))
arrow.move(to: NSPoint(x: 372, y: 232))
arrow.line(to: NSPoint(x: 396, y: 210))
arrow.line(to: NSPoint(x: 372, y: 188))
NSColor(red: 0.15, green: 0.40, blue: 0.95, alpha: 0.9).setStroke()
arrow.stroke()

centered("First launch: right-click the app and choose Open", y: 36, attributes: hint)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
