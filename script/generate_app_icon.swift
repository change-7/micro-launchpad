import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "MicroLaunchpad.png"
let size = 1024
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

roundedRect(bounds, radius: 224, fill: color(10, 11, 15))
roundedRect(NSRect(x: 57, y: 57, width: 910, height: 910), radius: 182, fill: color(27, 28, 35), stroke: color(75, 77, 91), lineWidth: 12)
roundedRect(NSRect(x: 145, y: 145, width: 734, height: 734), radius: 88, fill: color(16, 17, 23), stroke: color(52, 54, 65), lineWidth: 10)

let cell: CGFloat = 61
let gap: CGFloat = 15
let startX: CGFloat = 218
let startY: CGFloat = 218
let highlighted: [String: NSColor] = [
    "2,3": color(245, 166, 35),
    "3,4": color(57, 211, 83),
    "4,2": color(255, 86, 48),
    "4,3": color(57, 211, 83),
    "4,4": color(245, 166, 35),
    "5,3": color(57, 211, 83)
]

for row in 0..<8 {
    for column in 0..<8 {
        let key = "\(row),\(column)"
        let fill = highlighted[key] ?? color(27, 29, 38)
        if highlighted[key] != nil {
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = fill.withAlphaComponent(0.78)
            shadow.shadowBlurRadius = 22
            shadow.shadowOffset = .zero
            shadow.set()
            roundedRect(NSRect(x: startX + CGFloat(column) * (cell + gap), y: startY + CGFloat(row) * (cell + gap), width: cell, height: cell), radius: 16, fill: fill)
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            roundedRect(NSRect(x: startX + CGFloat(column) * (cell + gap), y: startY + CGFloat(row) * (cell + gap), width: cell, height: cell), radius: 16, fill: fill)
        }
    }
}

for row in 0..<4 {
    for x in [183.0, 840.0] {
        let dot = NSBezierPath(ovalIn: NSRect(x: x, y: 272 + CGFloat(row) * 90, width: 23, height: 23))
        color(245, 166, 35).setFill()
        dot.fill()
    }
}

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG 생성 실패") }
try png.write(to: URL(fileURLWithPath: outputPath))
