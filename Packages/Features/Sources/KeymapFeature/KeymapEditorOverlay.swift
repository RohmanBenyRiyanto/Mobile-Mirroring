import SwiftUI
import DomainModels

/// Draws the keymap's elements on top of the live phone screen so they can be dragged into place.
/// It also dims the picture and takes every click, so editing never touches the phone.
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
                if let selected = editor.selectedElement, case let .skillShot(_, _, _, range, hero) = selected.action {
                    HeroHandle(editor: editor, id: selected.id, hero: hero, range: range, mapper: mapper, space: Self.space)
                }
            }
            .coordinateSpace(name: Self.space)
            .clipped() // a chip near the edge must not spill over the side panel
        }
    }
}

/// One element: its reach as a ring, and a chip to grab.
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
            if let radius = reach { // how far the finger can travel
                Circle()
                    .strokeBorder(.white.opacity(isSelected ? 0.9 : 0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: radius * 2, height: radius * 2)
                    .allowsHitTesting(false)
            }
            Chip(text: summary.text, symbol: summary.symbol, isSelected: isSelected)
                .gesture(drag)
        }
        .position(center)
    }

    /// Radius of the ring in points, for the elements that have one.
    private var reach: Double? {
        switch element.action {
        case let .joystick(_, _, _, _, radius, _), let .aim(_, _, radius), let .skillShot(_, _, radius, _, _): return radius * shorterEdge
        case .button, .mouseButton, .macro: return nil
        }
    }

    private var summary: (text: String, symbol: String) {
        let name = element.label.isEmpty ? "" : "\(element.label) "
        switch element.action {
        case let .button(key, mode): return (name + KeyNames.name(for: key), mode == .tap ? "hand.tap" : mode == .hold ? "hand.point.down" : "switch.2")
        case let .joystick(up, left, down, right, _, _): return (name + [up, left, down, right].map(KeyNames.name).joined(), "gamecontroller")
        case let .aim(key, _, _): return (name + KeyNames.name(for: key), "scope")
        case let .mouseButton(button, _): return (name + ["Left", "Right", "Middle", "Button 4", "Button 5"][min(button, 4)] + " click", "computermouse")
        case let .skillShot(key, _, _, _, _): return (name + KeyNames.name(for: key), "target")
        case let .macro(key, steps, _, _): return (name + KeyNames.name(for: key) + " ×\(steps.count)", "play.circle")
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                editor.selection = element.id
                let moved = hypot(value.translation.width, value.translation.height) > 2
                if moved, !isDragging {
                    isDragging = true
                    editor.checkpoint() // the whole drag is one undo step
                }
                if isDragging, let ratio = mapper.clampedRatio(forViewPoint: value.location) {
                    editor.move(element.id, to: NormalizedPoint(x: ratio.x, y: ratio.y))
                }
            }
            .onEnded { _ in isDragging = false }
    }
}

private struct Chip: View {
    let text: String
    let symbol: String
    let isSelected: Bool

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .background(isSelected ? Color.white : Color.black.opacity(0.75), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: isSelected ? 0 : 1))
    }
}

/// Where the hero stands on the screen (the origin of a skill-shot's aim), with the mouse range around it.
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
