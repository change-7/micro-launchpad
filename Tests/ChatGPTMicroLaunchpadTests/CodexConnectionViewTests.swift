import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class CodexConnectionViewTests: XCTestCase {
    func testSettingsSurface_containsOnlyStatusMotionSection() {
        XCTAssertEqual(CodexConnectionView.visibleSections, [.statusMotion])
    }
}
