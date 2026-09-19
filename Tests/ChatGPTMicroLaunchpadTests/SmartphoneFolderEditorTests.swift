import XCTest
@testable import ChatGPTMicroLaunchpad

final class SmartphoneFolderEditorTests: XCTestCase {
    func testEditorSlots_keepParentFirstAndFillTheFourByFourGrid() {
        let folder = SmartphoneButton(
            id: "smartphone_page_0_button_0",
            title: "앱 폴더",
            symbol: "folder",
            action: PadAction(kind: .appFolder, value: "com.example.App"),
            folderShortcuts: [
                SmartphoneFolderShortcut(id: "shortcut-1", title: "단축키 1")
            ]
        )

        let slots = smartphoneFolderEditorSlots(for: folder)

        XCTAssertEqual(slots.count, 16)
        XCTAssertTrue(slots[0].isParent)
        XCTAssertEqual(slots[1].shortcut?.id, "shortcut-1")
        XCTAssertNil(slots[2].shortcut)
        XCTAssertFalse(slots[2].isParent)
    }

    func testEditorSlots_keepLegacyOverflowAfterTheFirstFourByFourPage() {
        let shortcuts = (0..<16).map { index in
            SmartphoneFolderShortcut(id: "shortcut-\(index)", title: "단축키 \(index + 1)")
        }
        let folder = SmartphoneButton(
            id: "smartphone_page_0_button_0",
            title: "앱 폴더",
            action: PadAction(kind: .appFolder, value: "com.example.App"),
            folderShortcuts: shortcuts
        )

        let slots = smartphoneFolderEditorSlots(for: folder)

        XCTAssertEqual(slots.count, 17)
        XCTAssertTrue(slots[0].isParent)
        XCTAssertEqual(slots[16].shortcut?.id, "shortcut-15")
    }
}
