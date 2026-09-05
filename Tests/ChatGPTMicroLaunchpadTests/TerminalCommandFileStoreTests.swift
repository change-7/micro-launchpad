import XCTest
@testable import ChatGPTMicroLaunchpad

final class TerminalCommandFileStoreTests: XCTestCase {
    func testSynchronize_createsManagedFilesAndRemovesThemWhenActionsDisappear() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("micro-launchpad-command-files-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let macIdentifier = TerminalCommandFileStore.macButtonIdentifier(pageIndex: 0, padID: "grid_0_0")
        let macPages = [LaunchPage(
            name: "P1",
            pads: [Pad(id: "grid_0_0", action: PadAction(kind: .terminalCommand, value: "echo mac"))]
        )]
        let smartphonePages = [SmartphonePage(
            id: "smartphone_page_0",
            name: "PAGE 01",
            buttons: [SmartphoneButton(
                id: "smartphone_page_0_button_0",
                action: PadAction(kind: .terminalCommand, value: "echo phone")
            )]
        )]

        TerminalCommandFileStore.synchronize(
            macPages: macPages,
            smartphonePages: smartphonePages,
            in: directory
        )

        let macFile = TerminalCommandFileStore.commandFileURL(for: macIdentifier, in: directory)
        let smartphoneFile = TerminalCommandFileStore.commandFileURL(
            for: "smartphone_page_0_button_0",
            in: directory
        )
        XCTAssertEqual(try String(contentsOf: macFile, encoding: .utf8), "#!/bin/zsh\nset -e\necho mac\n")
        XCTAssertEqual(try String(contentsOf: smartphoneFile, encoding: .utf8), "#!/bin/zsh\nset -e\necho phone\n")

        let userFile = directory.appendingPathComponent("my-command.command")
        try Data("keep".utf8).write(to: userFile)

        TerminalCommandFileStore.synchronize(macPages: [], smartphonePages: [], in: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: macFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: smartphoneFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
    }
}
