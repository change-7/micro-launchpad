import AppKit
import Foundation

@MainActor
enum SmartphoneIconAssetProvider {
    private static var cache: [String: SmartphoneIconAsset] = [:]

    static func assets(for pages: [SmartphonePage]) -> [String: SmartphoneIconAsset] {
        var assets: [String: SmartphoneIconAsset] = [:]
        for button in pages.flatMap(\.buttons) {
            guard !button.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let asset = asset(for: button) {
                assets[button.id] = asset
            }

            for shortcut in button.folderShortcuts {
                guard !shortcut.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !shortcut.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let asset = symbolAsset(for: shortcut.symbol) else { continue }
                assets[shortcut.id] = asset
            }
        }
        return assets
    }

    private static func asset(for button: SmartphoneButton) -> SmartphoneIconAsset? {
        guard !button.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if let bundleIdentifier = targetBundleIdentifier(for: button),
           !bundleIdentifier.isEmpty,
           let appAsset = appAsset(for: bundleIdentifier) {
            return appAsset
        }
        return symbolAsset(for: button.symbol)
    }

    private static func targetBundleIdentifier(for button: SmartphoneButton) -> String? {
        switch button.action.kind {
        case .app, .appFolder:
            return button.action.value
        case .shortcut:
            return button.action.targetAppBundleIdentifier
        case .terminalCommand, .url, .clipboardText, .none:
            return nil
        }
    }

    private static func appAsset(for bundleIdentifier: String) -> SmartphoneIconAsset? {
        let cacheKey = "app:\(bundleIdentifier)"
        if let cached = cache[cacheKey] { return cached }
        guard let icon = AppRegistrationService.icon(for: bundleIdentifier),
              let pngData = pngData(for: icon, tint: nil) else { return nil }
        let asset = SmartphoneIconAsset(kind: "app", data: pngData.base64EncodedString())
        cache[cacheKey] = asset
        return asset
    }

    private static func symbolAsset(for symbol: String) -> SmartphoneIconAsset? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "symbol:\(normalizedSymbol)"
        if let cached = cache[cacheKey] { return cached }
        guard let icon = NSImage(systemSymbolName: normalizedSymbol, accessibilityDescription: nil),
              let pngData = pngData(
                for: icon.withSymbolConfiguration(.init(pointSize: 52, weight: .medium)) ?? icon,
                tint: .white
              ) else { return nil }
        let asset = SmartphoneIconAsset(kind: "sf-symbol", data: pngData.base64EncodedString())
        cache[cacheKey] = asset
        return asset
    }

    private static func pngData(for icon: NSImage, tint: NSColor?) -> Data? {
        let pixelSize = 96
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = NSImageInterpolation.high
        icon.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        if let tint {
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.setFillColor(tint.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }
}
