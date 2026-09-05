import Foundation

enum TerminalCommandFileStore {
    private static let directoryName = "Commands"
    private static let filePrefix = "button-"
    private static let fileExtension = "command"

    static func macButtonIdentifier(pageIndex: Int, padID: String) -> String {
        "mac_page_\(pageIndex)_\(padID)"
    }

    static func commandFileURL(for identifier: String, in directoryURL: URL? = nil) -> URL {
        let directory = directoryURL ?? defaultDirectoryURL
        return directory.appendingPathComponent("\(filePrefix)\(safeFileName(identifier)).\(fileExtension)")
    }

    static func shellCommand(for identifier: String) -> String? {
        let url = commandFileURL(for: identifier)
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return "/bin/zsh \(shellQuoted(url.path))"
    }

    static func synchronize(
        macPages: [LaunchPage],
        smartphonePages: [SmartphonePage],
        in directoryURL: URL? = nil
    ) {
        let directory = directoryURL ?? defaultDirectoryURL
        var commands: [String: String] = [:]

        for (pageIndex, page) in macPages.enumerated() {
            for pad in page.pads where pad.action.kind == .terminalCommand {
                let command = pad.action.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty {
                    commands[macButtonIdentifier(pageIndex: pageIndex, padID: pad.id)] = command
                }
            }
        }

        for page in smartphonePages {
            for button in page.buttons where button.action.kind == .terminalCommand {
                let command = button.action.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty {
                    commands[button.id] = command
                }
            }
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let managedFiles = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter {
                $0.pathExtension == fileExtension && $0.deletingPathExtension().lastPathComponent.hasPrefix(filePrefix)
            }

            for fileURL in managedFiles {
                let identifier = fileURL.deletingPathExtension().lastPathComponent.dropFirst(filePrefix.count)
                if commands[String(identifier)] == nil {
                    try fileManager.removeItem(at: fileURL)
                }
            }

            for (identifier, command) in commands {
                let fileURL = commandFileURL(for: identifier, in: directory)
                let script = "#!/bin/zsh\nset -e\n\(command)\n"
                try Data(script.utf8).write(to: fileURL, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: fileURL.path)
            }
        } catch {
            // Settings remain persisted even if the optional convenience files cannot be written.
        }
    }

    private static var defaultDirectoryURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("Micro Launchpad", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func safeFileName(_ identifier: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return String(identifier.map { allowed.contains($0) ? $0 : "_" })
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
