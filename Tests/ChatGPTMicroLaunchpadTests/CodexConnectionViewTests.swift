import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class CodexConnectionViewTests: XCTestCase {
    func testSettingsSurface_hasDisplayAndMotionPresetTabs() {
        XCTAssertEqual(CodexConnectionView.availableTabTitles, ["표시 설정", "상태별 모션", "모션 프리셋"])
    }
}
