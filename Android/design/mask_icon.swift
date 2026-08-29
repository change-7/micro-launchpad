import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: mask_icon.swift input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("could not read input image\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bounds = CGRect(x: 0, y: 0, width: width, height: height)
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("could not create bitmap context\n", stderr)
    exit(1)
}

context.clear(bounds)
context.saveGState()
let radius = min(CGFloat(width), CGFloat(height)) * 0.19
context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
context.clip()
context.interpolationQuality = .high
context.draw(image, in: bounds)
context.restoreGState()

guard
    let outputImage = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fputs("could not create output image\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("could not finalize output image\n", stderr)
    exit(1)
}
