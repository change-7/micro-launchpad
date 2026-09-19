import XCTest
@testable import ChatGPTMicroLaunchpad

final class MacWindowActionTests: XCTestCase {
    func testWindowActionPresetsUseNativeMacShortcuts() {
        XCTAssertEqual(MacWindowAction.allCases.count, 7)
        XCTAssertEqual(MacWindowAction.leftHalf.rawValue, "ctrl+fn+left")
        XCTAssertEqual(MacWindowAction.rightHalf.rawValue, "ctrl+fn+right")
        XCTAssertEqual(MacWindowAction.topHalf.rawValue, "ctrl+fn+up")
        XCTAssertEqual(MacWindowAction.bottomHalf.rawValue, "ctrl+fn+down")
        XCTAssertEqual(MacWindowAction.nextDisplay.rawValue, "ctrl+fn+shift+right")
        XCTAssertEqual(MacWindowAction.fill.rawValue, "ctrl+fn+f")
        XCTAssertEqual(MacWindowAction.fullScreen.rawValue, "window:full-screen")
    }

    func testWindowActionPresetsDisplayMacKeyGlyphs() {
        XCTAssertEqual(MacWindowAction.leftHalf.shortcutDisplay, "⌃ Globe ←")
        XCTAssertEqual(MacWindowAction.rightHalf.shortcutDisplay, "⌃ Globe →")
        XCTAssertEqual(MacWindowAction.topHalf.shortcutDisplay, "⌃ Globe ↑")
        XCTAssertEqual(MacWindowAction.bottomHalf.shortcutDisplay, "⌃ Globe ↓")
        XCTAssertEqual(MacWindowAction.nextDisplay.shortcutDisplay, "⌃ Globe ⇧ →")
        XCTAssertEqual(MacWindowAction.fill.shortcutDisplay, "⌃ Globe F")
        XCTAssertEqual(MacWindowAction.fullScreen.shortcutDisplay, "전체 화면")
    }

    func testWindowActionPresetsReadLegacyStoredValues() {
        XCTAssertEqual(MacWindowAction(rawValue: "window:left-half"), .leftHalf)
        XCTAssertEqual(MacWindowAction(rawValue: "window:right-half"), .rightHalf)
        XCTAssertEqual(MacWindowAction(rawValue: "window:top-half"), .topHalf)
        XCTAssertEqual(MacWindowAction(rawValue: "window:bottom-half"), .bottomHalf)
        XCTAssertEqual(MacWindowAction(rawValue: "window:next-display"), .nextDisplay)
        XCTAssertEqual(MacWindowAction(rawValue: "window:fill"), .fill)
        XCTAssertEqual(MacWindowAction(rawValue: "window:full-screen"), .fullScreen)
    }

    func testWindowActionFrameMappingKeepsDirectionsAndDisplayMoveDistinct() {
        let display = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let current = CGRect(x: 320, y: 220, width: 500, height: 300)

        XCTAssertEqual(
            MacActionRunner.windowFrame(for: .leftHalf, currentFrame: current, visibleDisplays: [display]),
            CGRect(x: 0, y: 0, width: 600, height: 800)
        )
        XCTAssertEqual(
            MacActionRunner.windowFrame(for: .rightHalf, currentFrame: current, visibleDisplays: [display]),
            CGRect(x: 600, y: 0, width: 600, height: 800)
        )
        XCTAssertEqual(
            MacActionRunner.windowFrame(for: .topHalf, currentFrame: current, visibleDisplays: [display]),
            CGRect(x: 0, y: 0, width: 1200, height: 400)
        )
        XCTAssertEqual(
            MacActionRunner.windowFrame(for: .bottomHalf, currentFrame: current, visibleDisplays: [display]),
            CGRect(x: 0, y: 400, width: 1200, height: 400)
        )
        XCTAssertEqual(
            MacActionRunner.windowFrame(for: .fill, currentFrame: current, visibleDisplays: [display]),
            display
        )
    }
}
