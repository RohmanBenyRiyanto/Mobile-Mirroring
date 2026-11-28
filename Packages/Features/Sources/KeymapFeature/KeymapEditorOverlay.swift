import SwiftUI
import DomainModels

public struct KeymapEditorOverlay: View {
    @ObservedObject public var editor: KeymapEditorModel
    public let videoSize: CGSize

    public init(editor: KeymapEditorModel, videoSize: CGSize) {
        self.editor = editor
        self.videoSize = videoSize
    }

    private static let space = "keymap-overlay"

    public var body: some View {
        GeometryReader { geometry in
            let mapper = CoordinateMapper(viewSize: geometry.size, frameSize: videoSize)
            ZStack {
                Color.black.opacity(0.2)
                    .contentShape(Rectangle())
                    .onTapGesture { editor.selection = nil }

                ForEach(editor.keymap.elements) { element in
                    ElementMarker(editor: editor, element: element, mapper: mapper, space: Self.space)
                }
                if let selected = editor.selectedElement, case let .swipe(_, end, _) = selected.action {
                    SwipeHandle(editor: editor, id: selected.id, start: selected.position, end: end, mapper: mapper, space: Self.space)
                }
                if let selected = editor.selectedElement, case let .skillShot(_, _, _, range, hero) = selected.action {
                    HeroHandle(editor: editor, id: selected.id, hero: hero, range: range, mapper: mapper, space: Self.space)
                }
            }
            .coordinateSpace(name: Self.space)
            .clipped()
        }
    }
}

private struct ElementMarker: View {
    @ObservedObject var editor: KeymapEditorModel
    let element: KeymapElement
    let mapper: CoordinateMapper
    let space: String

    @State private var isDragging = false

    private var isSelected: Bool { editor.selection == element.id }
    private var center: CGPoint { mapper.viewPoint(forRatio: element.position.cgPoint) }
    private var shorterEdge: Double { Double(min(mapper.videoRect.width, mapper.videoRect.height)) }

    var body: some View {
        ZStack {
            if let radius = reach {
                Circle()
                    .strokeBorder(.white.opacity(isSelected ? 0.9 : 0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: radius * 2, height: radius * 2)
                    .allowsHitTesting(false)
            }
            KeyCapMarker(key: summary.key, caption: summary.caption, symbol: summary.symbol, isSelected: isSelected)
                .gesture(drag)
        }
        .position(center)
    }

    private var reach: Double? {
        switch element.action {
        case let .joystick(_, _, _, _, radius, _), let .aim(_, _, radius), let .skillShot(_, _, radius, _, _): return radius * shorterEdge
        case .button, .mouseButton, .macro, .turbo, .swipe: return nil
        }
    }

    private var summary: (key: String, caption: String, symbol: String) {
        func caption(_ fallback: String) -> String { element.label.isEmpty ? fallback : element.label }
        switch element.action {
        case let .button(key, mode):
            let kind = mode == .tap ? "Tap" : mode == .hold ? "Hold" : "Toggle"
            return (KeyNames.name(for: key), caption(kind), "hand.tap")
        case let .joystick(up, left, down, right, _, _): return ([up, left, down, right].map(KeyNames.name).joined(), caption("Joystick"), "gamecontroller")
        case let .aim(key, _, _): return (KeyNames.name(for: key), caption("Aim"), "scope")
        case let .mouseButton(button, _): return (["L", "R", "M", "4", "5"][min(button, 4)], caption("Click"), "computermouse")
        case let .skillShot(key, _, _, _, _): return (KeyNames.name(for: key), caption("Skill shot"), "target")
        case let .turbo(key, rate): return (KeyNames.name(for: key), caption("Rapid") + " ×\(Int(rate))/s", "bolt")
        case let .swipe(key, _, _): return (KeyNames.name(for: key), caption("Swipe"), "arrow.up.forward")
        case let .macro(key, steps, _, _): return (KeyNames.name(for: key), caption("Macro") + " ×\(steps.count)", "play.circle")
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                editor.selection = element.id
                let moved = hypot(value.translation.width, value.translation.height) > 2
                if moved, !isDragging {
                    isDragging = true
                    editor.checkpoint()
                }
                if isDragging, let ratio = mapper.clampedRatio(forViewPoint: value.location) {
                    editor.move(element.id, to: NormalizedPoint(x: ratio.x, y: ratio.y))
                }
            }
            .onEnded { _ in isDragging = false }
    }
}

private struct KeyCapMarker: View {
    let key: String
    let caption: String
    let symbol: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(key)
                .font(.system(size: key.count > 2 ? 11 : 14, weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(minWidth: 34, minHeight: 34)
                .padding(.horizontal, key.count > 2 ? 6 : 0)
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .background(isSelected ? Color.white : Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(isSelected ? 0 : 0.85), lineWidth: 1.5))
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .foregroundStyle(.white)
                .background(Color.black.opacity(0.55), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HeroHandle: View {
    @ObservedObject var editor: KeymapEditorModel
    let id: UUID
    let hero: NormalizedPoint
    let range: Double
    let mapper: CoordinateMapper
    let space: String

    @State private var isDragging = false

    var body: some View {
        let shorter = Double(min(mapper.videoRect.width, mapper.videoRect.height))
        ZStack {
            Circle()
                .strokeBorder(.yellow.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: range * shorter * 2, height: range * shorter * 2)
                .allowsHitTesting(false)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
                .shadow(radius: 2)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                        .onChanged { value in
                            if !isDragging { isDragging = true; editor.checkpoint() }
                            if let ratio = mapper.clampedRatio(forViewPoint: value.location) {
                                editor.moveHero(of: id, to: NormalizedPoint(x: ratio.x, y: ratio.y))
                            }
                        }
                        .onEnded { _ in isDragging = false }
                )
        }
        .position(mapper.viewPoint(forRatio: hero.cgPoint))
        .help("Where your hero stands on the screen")
    }
}

private struct SwipeHandle: View {
    @ObservedObject var editor: KeymapEditorModel
    let id: UUID
    let start: NormalizedPoint
    let end: NormalizedPoint
    let mapper: CoordinateMapper
    let space: String

    @State private var isDragging = false

    var body: some View {
        let from = mapper.viewPoint(forRatio: start.cgPoint), to = mapper.viewPoint(forRatio: end.cgPoint)
        ZStack {
            Path { path in path.move(to: from); path.addLine(to: to) }
                .stroke(.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .allowsHitTesting(false)
            Image(systemName: "arrowtriangle.right.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
                .shadow(radius: 2)
                .position(to)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                        .onChanged { value in
                            if !isDragging { isDragging = true; editor.checkpoint() }
                            if let ratio = mapper.clampedRatio(forViewPoint: value.location) {
                                editor.moveSwipeEnd(of: id, to: NormalizedPoint(x: ratio.x, y: ratio.y))
                            }
                        }
                        .onEnded { _ in isDragging = false }
                )
                .help("Where the swipe ends")
        }
    }
}
