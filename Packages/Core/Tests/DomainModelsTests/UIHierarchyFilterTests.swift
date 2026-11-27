import XCTest
@testable import DomainModels

final class UIHierarchyFilterTests: XCTestCase {
    private func node(_ id: Int, _ depth: Int, _ cls: String, rid: String = "", text: String = "", desc: String = "") -> UINode {
        UINode(id: id, depth: depth, className: cls, resourceID: rid, text: text, contentDescription: desc, package: "p",
               bounds: CGRect(x: 0, y: 0, width: 10, height: 10), isClickable: false, isEnabled: true)
    }

    private var tree: UIHierarchy {
        UIHierarchy(nodes: [node(0, 0, "android.widget.FrameLayout"), node(1, 1, "android.widget.Button", rid: "p:id/login", text: "Log in"),
                            node(2, 1, "android.widget.TextView", desc: "Welcome back")])
    }

    func testFilterNeedsEveryWord() {
        XCTAssertEqual(tree.filtered(by: "").count, 3)
        XCTAssertEqual(tree.filtered(by: "BUTTON").map(\.id), [1])
        XCTAssertEqual(tree.filtered(by: "log button").map(\.id), [1])
        XCTAssertEqual(tree.filtered(by: "welcome").map(\.id), [2])
        XCTAssertTrue(tree.filtered(by: "nothing").isEmpty)
    }

    func testOutlineIndentsByDepth() {
        XCTAssertEqual(tree.outline, "FrameLayout\n  Button #login \"Log in\"\n  TextView [Welcome back]")
    }
}
