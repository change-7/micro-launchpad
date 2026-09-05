import AppKit
import Foundation

@MainActor
enum SmartphoneIconAssetProvider {
    private static var cache: [String: SmartphoneIconAsset] = [:]

    static func assets(for pages: [SmartphonePage]) -> [String: SmartphoneIconAsset] {
        var assets: [String: SmartphoneIconAsset] = [:]
        for button in pages.flatMap(\.buttons) {
            guard !button.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let bundleIdentifier: String
            switch button.action.kind {
            case .app:
                bundleIdentifier = button.action.value
            case .shortcut:
                bundleIdentifier = button.action.targetAppBundleIdentifier
            case .terminalCommand, .url, .none:
                continue
            }
            guard !bundleIdentifier.isEmpty else { continue }
            if let asset = asset(for: bundleIdentifier) {
                assets[button.id] = asset
            }
        }
        return assets
    }

    private static func asset(for bundleIdentifier: String) -> SmartphoneIconAsset? {
        if let cached = cache[bundleIdentifier] { return cached }
        guard let icon = AppRegistrationService.icon(for: bundleIdentifier),
              let pngData = pngData(for: icon) else { return nil }
        let asset = SmartphoneIconAsset(data: pngData.base64EncodedString())
        cache[bundleIdentifier] = asset
        return asset
    }

    private static func pngData(for icon: NSImage) -> Data? {
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
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }
}
