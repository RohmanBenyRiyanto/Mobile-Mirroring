import CoreGraphics
import Foundation

/// Converts between the places a point can live:
///
/// - **view**: points inside the on-screen video area, origin at the top-left;
/// - **ratio**: 0…1 across the video, independent of any screen size (what keymaps are stored in);
/// - **frame**: pixels of the video frame the phone encodes (what touch events carry);
/// - **dp**: Android density-independent pixels on the phone's real screen.
///
/// The video is letterboxed (aspect fit) inside the view, and the frame may be smaller than the phone's screen
/// when the stream is downscaled, so each conversion goes through the ratio.
public struct CoordinateMapper: Equatable {
    public var viewSize: CGSize
    public var frameSize: CGSize
    /// The phone's screen in pixels, in the current orientation. Needed only for dp.
    public var screenSize: CGSize?
    /// Android density scale (dpi / 160). Needed only for dp.
    public var densityScale: Double?

    public init(viewSize: CGSize, frameSize: CGSize, screenSize: CGSize? = nil, densityScale: Double? = nil) {
        self.viewSize = viewSize
        self.frameSize = frameSize
        self.screenSize = screenSize
        self.densityScale = densityScale
    }

    /// A mapper that also knows the phone's real screen, for dp conversions.
    public init(viewSize: CGSize, frameSize: CGSize, device: DeviceInfo) {
        self.init(viewSize: viewSize, frameSize: frameSize,
                  screenSize: device.screenSize(matching: frameSize), densityScale: device.densityScale)
    }

    private var isUsable: Bool {
        viewSize.width > 0 && viewSize.height > 0 && frameSize.width > 0 && frameSize.height > 0
    }

    /// Where the video is drawn inside the view (aspect fit, centered).
    public var videoRect: CGRect {
        guard isUsable else { return .zero }
        let scale = min(viewSize.width / frameSize.width, viewSize.height / frameSize.height)
        let size = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        return CGRect(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    // MARK: View ↔ ratio

    /// The ratio under a view point, or nil if the point is on the black bars.
    public func ratio(forViewPoint point: CGPoint) -> CGPoint? {
        let rect = videoRect
        guard rect.width > 0, rect.contains(point) else { return nil }
        return unclampedRatio(forViewPoint: point)
    }

    /// Like `ratio(forViewPoint:)`, but a point outside the video snaps to its nearest edge (for drags that leave the picture).
    public func clampedRatio(forViewPoint point: CGPoint) -> CGPoint? {
        guard videoRect.width > 0 else { return nil }
        let ratio = unclampedRatio(forViewPoint: point)
        return CGPoint(x: min(max(ratio.x, 0), 1), y: min(max(ratio.y, 0), 1))
    }

    public func viewPoint(forRatio ratio: CGPoint) -> CGPoint {
        let rect = videoRect
        return CGPoint(x: rect.minX + ratio.x * rect.width, y: rect.minY + ratio.y * rect.height)
    }

    public func viewRect(forRatioRect rect: CGRect) -> CGRect {
        let origin = viewPoint(forRatio: rect.origin)
        let video = videoRect
        return CGRect(x: origin.x, y: origin.y, width: rect.width * video.width, height: rect.height * video.height)
    }

    // MARK: Ratio ↔ frame (touch events)

    /// The touch position for a ratio. Nil when the frame size does not fit the protocol's 16-bit fields.
    public func touchPosition(forRatio ratio: CGPoint) -> TouchPosition? {
        guard isUsable, frameSize.width <= CGFloat(UInt16.max), frameSize.height <= CGFloat(UInt16.max) else { return nil }
        let width = Int32(frameSize.width), height = Int32(frameSize.height)
        let x = (min(max(ratio.x, 0), 1) * CGFloat(width - 1)).rounded()
        let y = (min(max(ratio.y, 0), 1) * CGFloat(height - 1)).rounded()
        return TouchPosition(x: Int32(x), y: Int32(y), frameWidth: UInt16(width), frameHeight: UInt16(height))
    }

    /// Mouse position → touch position, clamped to the picture.
    public func touchPosition(forViewPoint point: CGPoint) -> TouchPosition? {
        clampedRatio(forViewPoint: point).flatMap(touchPosition(forRatio:))
    }

    public func ratio(for position: TouchPosition) -> CGPoint {
        CGPoint(x: position.frameWidth > 1 ? Double(position.x) / Double(position.frameWidth - 1) : 0,
                y: position.frameHeight > 1 ? Double(position.y) / Double(position.frameHeight - 1) : 0)
    }

    // MARK: Ratio ↔ dp

    /// Position on the phone's screen in dp, or nil when the screen size or density is unknown.
    public func dp(forRatio ratio: CGPoint) -> CGPoint? {
        guard let screenSize, let densityScale, densityScale > 0 else { return nil }
        return CGPoint(x: ratio.x * screenSize.width / densityScale, y: ratio.y * screenSize.height / densityScale)
    }

    public func ratio(forDP point: CGPoint) -> CGPoint? {
        guard let screenSize, let densityScale, screenSize.width > 0, screenSize.height > 0 else { return nil }
        return CGPoint(x: point.x * densityScale / screenSize.width, y: point.y * densityScale / screenSize.height)
    }

    /// A length across the phone's screen in dp (for example an element's width as a fraction of the screen).
    public func dpSize(forRatioSize size: CGSize) -> CGSize? {
        guard let screenSize, let densityScale, densityScale > 0 else { return nil }
        return CGSize(width: size.width * screenSize.width / densityScale, height: size.height * screenSize.height / densityScale)
    }

    // MARK: Private

    private func unclampedRatio(forViewPoint point: CGPoint) -> CGPoint {
        let rect = videoRect
        return CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }
}
