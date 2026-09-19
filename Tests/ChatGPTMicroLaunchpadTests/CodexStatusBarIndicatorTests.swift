import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class CodexStatusBarIndicatorTests: XCTestCase {
    func testAnimationStates_includeWorkAndAttentionStatesOnly() {
        XCTAssertTrue(CodexStatusBarIndicator.isAnimatedActivity(.connecting))
        XCTAssertTrue(CodexStatusBarIndicator.isAnimatedActivity(.running))
        XCTAssertTrue(CodexStatusBarIndicator.isAnimatedActivity(.waitingForApproval))
        XCTAssertTrue(CodexStatusBarIndicator.isAnimatedActivity(.failed))
        XCTAssertFalse(CodexStatusBarIndicator.isAnimatedActivity(.idle))
        XCTAssertFalse(CodexStatusBarIndicator.isAnimatedActivity(.completed))
    }
}
