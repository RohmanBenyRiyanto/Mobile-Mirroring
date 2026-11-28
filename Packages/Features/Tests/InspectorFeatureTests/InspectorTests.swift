import SwiftUI
import XCTest
import TestSupport
@testable import DomainModels
@testable import InspectorFeature

final class InspectorTests: XCTestCase {
    private func dump(extra: String = "") -> Data {
        func node(bounds: String, cls: String = "android.view.View", id: String = "", text: String = "", desc: String = "",
                  clickable: Bool = false, _ children: String = "") -> String {
            "<node index=\"0\" text=\"\(text)\" resource-id=\"\(id)\" class=\"\(cls)\" package=\"com.app\" content-desc=\"\(desc)\" checkable=\"false\" checked=\"false\" clickable=\"\(clickable)\" enabled=\"true\" focusable=\"false\" focused=\"false\" scrollable=\"false\" long-clickable=\"false\" password=\"false\" selected=\"false\" bounds=\"\(bounds)\" drawing-order=\"1\" hint=\"\">\(children)</node>"
        }
        let button = node(bounds: "[40,60][240,160]", cls: "android.widget.Button", id: "com.app:id/play", text: "Play &amp; Win", clickable: true)
        let toolbar = node(bounds: "[0,0][1000,200]", cls: "android.widget.FrameLayout", id: "com.app:id/toolbar", button)
        let overlay = node(bounds: "[100,100][300,300]", cls: "android.widget.ImageView", desc: "Overlay")
        let empty = node(bounds: "[0,0][0,0]")
        let root = node(bounds: "[0,0][1000,2000]", toolbar + overlay + empty)
        let xml = "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation=\"0\">\(root)</hierarchy>\(extra)UI hierchary dumped to: /dev/tty"
        return Data(xml.utf8)
    }

    // MARK: Parsing

    func testParsesElementsInDocumentOrderWithDepth() throws {
        let hierarchy = try XCTUnwrap(UIHierarchyParser.parse(dump()))
        XCTAssertEqual(hierarchy.nodes.count, 5)
        XCTAssertEqual(hierarchy.nodes.map(\.depth), [0, 1, 2, 1, 1])
        XCTAssertEqual(hierarchy.screenSize, CGSize(width: 1000, height: 2000))
        let button = hierarchy.nodes[2]
        XCTAssertEqual(button.text, "Play & Win")
        XCTAssertEqual(button.resourceID, "com.app:id/play")
        XCTAssertEqual(button.shortResourceID, "play")
        XCTAssertEqual(button.shortClassName, "Button")
        XCTAssertEqual(button.bounds, CGRect(x: 40, y: 60, width: 200, height: 100))
        XCTAssertTrue(button.isClickable)
    }

    func testRejectsGarbageAndOversizedDumps() {
        XCTAssertNil(UIHierarchyParser.parse(Data("ERROR: could not get idle state.".utf8)))
        XCTAssertNil(UIHierarchyParser.parse(Data("<hierarchy rotation=\"0\"></hierarchy>".utf8)))
        XCTAssertNil(UIHierarchyParser.parse(Data(count: UIHierarchyParser.maxBytes + 1)))
    }

    func testDoesNotFetchExternalEntities() {
        let hostile = Data("<?xml version='1.0'?><!DOCTYPE x [<!ENTITY e SYSTEM \"file:///etc/passwd\">]><hierarchy><node text=\"&e;\" bounds=\"[0,0][10,10]\"/></hierarchy>".utf8)
        let nodes = UIHierarchyParser.parse(hostile)?.nodes
        XCTAssertFalse(nodes?.contains { $0.text.contains("root:") } ?? false)
    }

    func testBoundsParsing() {
        XCTAssertEqual(UIHierarchyParser.bounds(from: "[0,0][1080,2340]"), CGRect(x: 0, y: 0, width: 1080, height: 2340))
        XCTAssertEqual(UIHierarchyParser.bounds(from: "[-20,5][30,45]"), CGRect(x: -20, y: 5, width: 50, height: 40))
        XCTAssertNil(UIHierarchyParser.bounds(from: "[10,10][5,5]"))
        XCTAssertNil(UIHierarchyParser.bounds(from: "nonsense"))
        XCTAssertNil(UIHierarchyParser.bounds(from: ""))
    }

    // MARK: Hit testing

    func testPicksTheDeepestElementUnderThePointer() throws {
        let hierarchy = try XCTUnwrap(UIHierarchyParser.parse(dump()))
        XCTAssertEqual(hierarchy.node(atRatio: CGPoint(x: 0.1, y: 0.05))?.shortResourceID, "play")
        XCTAssertEqual(hierarchy.node(atRatio: CGPoint(x: 0.8, y: 0.05))?.shortResourceID, "toolbar")
        XCTAssertEqual(hierarchy.node(atRatio: CGPoint(x: 0.5, y: 0.9))?.id, 0)
    }

    func testLaterSiblingWinsWhereElementsOverlapAndEmptyElementsNeverMatch() throws {
        let hierarchy = try XCTUnwrap(UIHierarchyParser.parse(dump()))
        let hit = hierarchy.node(atRatio: CGPoint(x: 0.15, y: 0.075))
        XCTAssertEqual(hit?.shortResourceID, "play")
        XCTAssertEqual(hierarchy.node(atRatio: CGPoint(x: 0.28, y: 0.14))?.contentDescription, "Overlay")
        XCTAssertNotEqual(hierarchy.node(atRatio: .zero)?.bounds.size, .zero)
    }

    // MARK: Measurements

    func testMeasurementsInPixelsAndDP() throws {
        let hierarchy = try XCTUnwrap(UIHierarchyParser.parse(dump()))
        let button = hierarchy.nodes[2]
        let measured = NodeMeasurements(node: button, densityScale: 2.5)
        XCTAssertEqual(measured.pixelText, "200 × 100 px at 40, 60")
        XCTAssertEqual(measured.dpText, "80 × 40 dp at 16, 24")
        XCTAssertNil(NodeMeasurements(node: button, densityScale: nil).dpText)
        XCTAssertNil(NodeMeasurements(node: button, densityScale: 0).dpText)
    }

    func testFractionalDPIsShortened() throws {
        let node = try XCTUnwrap(UIHierarchyParser.parse(dump())?.nodes[2])
        XCTAssertEqual(NodeMeasurements(node: node, densityScale: 3).dpText, "66.7 × 33.3 dp at 13.3, 20")
    }

    // MARK: Model

    @MainActor
    func testModelReadsOnDemandTracksHoverAndTurnsOff() async throws {
        let data = dump()
        let model = InspectorModel(fetch: { data })
        XCTAssertFalse(model.isOn)
        model.pointerMoved(to: CGPoint(x: 0.1, y: 0.05))
        XCTAssertNil(model.hovered)

        model.setOn(true)
        XCTAssertEqual(model.status, .reading)
        try await waitUntil { model.status == .ready }
        XCTAssertEqual(model.hovered?.shortResourceID, "play")

        model.pointerMoved(to: CGPoint(x: 0.8, y: 0.05))
        XCTAssertEqual(model.hovered?.shortResourceID, "toolbar")
        model.pointerMoved(to: nil)
        XCTAssertNil(model.hovered)

        model.setOn(false)
        XCTAssertFalse(model.isOn)
        XCTAssertNil(model.hierarchy)
    }

    @MainActor
    func testModelReportsUnreadableScreens() async throws {
        let model = InspectorModel(fetch: { Data("ERROR: null root node returned by UiTestAutomationBridge.".utf8) })
        model.setOn(true)
        try await waitUntil { if case .failed = model.status { return true } else { return false } }
    }

    @MainActor
    func testModelReportsFetchFailures() async throws {
        struct Boom: Error {}
        let model = InspectorModel(fetch: { throw Boom() })
        model.setOn(true)
        try await waitUntil { if case .failed = model.status { return true } else { return false } }
    }

    @MainActor
    func testTurningOffWhileReadingIgnoresTheLateAnswer() async throws {
        let data = dump()
        let model = InspectorModel(fetch: { try await Task.sleep(for: .milliseconds(150)); return data })
        model.setOn(true)
        model.setOn(false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.status, .off)
        XCTAssertNil(model.hierarchy)
    }

    @MainActor
    func testCopyPrefersIdThenTextThenDescription() async throws {
        let data = dump()
        let model = InspectorModel(fetch: { data })
        model.setOn(true)
        try await waitUntil { model.status == .ready }
        model.pointerMoved(to: CGPoint(x: 0.1, y: 0.05))
        XCTAssertEqual(model.copyHovered(), "com.app:id/play")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "com.app:id/play")
        model.pointerMoved(to: CGPoint(x: 0.28, y: 0.14))
        XCTAssertEqual(model.copyHovered(), "Overlay")
        model.pointerMoved(to: nil)
        XCTAssertNil(model.copyHovered())
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: Drawing

    @MainActor
    func testOverlayDrawsOutlineAndCard() async throws {
        let data = dump()
        let model = InspectorModel(fetch: { data })
        model.setOn(true)
        try await waitUntil { model.status == .ready }
        model.pointerMoved(to: CGPoint(x: 0.1, y: 0.05))
        let view = ZStack { Color.gray.opacity(0.3); InspectorOverlay(inspector: model, videoSize: CGSize(width: 1000, height: 2000), densityScale: 2.5) }
        let image = try renderSnapshot(view, size: CGSize(width: 300, height: 600), name: "inspector")
        XCTAssertFalse(isBlankImage(image))
    }
}
