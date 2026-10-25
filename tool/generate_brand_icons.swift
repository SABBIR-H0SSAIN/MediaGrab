// Run: swift tool/generate_brand_icons.swift /absolute/path/to/repository
// Retain the supplied source outside the bundled assets/icon directory.
// Only remove its connected black outer canvas; never redraw the artwork.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift tool/generate_brand_icons.swift REPOSITORY_ROOT")
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let sourceURL = root.appendingPathComponent("assets/branding/app_logo_source.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot read \(sourceURL.path)")
}

// Flood only near-black pixels connected to the outside. Interior dark areas
// and every colored edge of the rounded tile remain part of the image.
let artworkContext = CGContext(
    data: nil, width: original.width, height: original.height, bitsPerComponent: 8,
    bytesPerRow: original.width * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
artworkContext.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
let artworkPixels = artworkContext.data!.assumingMemoryBound(to: UInt8.self)
var outside: [Int] = []
func clearOutside(_ index: Int) {
    let offset = index * 4
    if artworkPixels[offset + 3] != 0 &&
        max(artworkPixels[offset], max(artworkPixels[offset + 1], artworkPixels[offset + 2])) <= 8 {
        for channel in 0..<4 { artworkPixels[offset + channel] = 0 }
        outside.append(index)
    }
}
for x in 0..<original.width {
    clearOutside(x)
    clearOutside((original.height - 1) * original.width + x)
}
for y in 0..<original.height {
    clearOutside(y * original.width)
    clearOutside(y * original.width + original.width - 1)
}
var cursor = 0
while cursor < outside.count {
    let index = outside[cursor]
    cursor += 1
    let x = index % original.width
    let y = index / original.width
    if x > 0 { clearOutside(index - 1) }
    if x + 1 < original.width { clearOutside(index + 1) }
    if y > 0 { clearOutside(index - original.width) }
    if y + 1 < original.height { clearOutside(index + original.width) }
}
var minX = original.width, minY = original.height, maxX = 0, maxY = 0
for y in 0..<original.height {
    for x in 0..<original.width where artworkPixels[(y * original.width + x) * 4 + 3] != 0 {
        minX = min(minX, x); minY = min(minY, y)
        maxX = max(maxX, x); maxY = max(maxY, y)
    }
}
guard minX <= maxX && minY <= maxY else { fatalError("Source contains no artwork") }
// CGImage cropping uses a top-left origin, unlike CGContext's pixel buffer.
let logo = artworkContext.makeImage()!.cropping(to: CGRect(
    x: minX, y: original.height - 1 - maxY,
    width: maxX - minX + 1, height: maxY - minY + 1))!

func writePNG(_ image: CGImage, _ relativePath: String) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Failed to encode \(url.path)")
    }
}

func scaled(_ image: CGImage, dimension: Int, round: Bool = false) -> CGImage {
    let context = CGContext(
        data: nil, width: dimension, height: dimension, bitsPerComponent: 8,
        bytesPerRow: dimension * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: dimension, height: dimension)
    if round {
        context.addEllipse(in: rect)
        context.clip()
    }
    context.interpolationQuality = .high
    let ratio = min(Double(dimension) / Double(image.width), Double(dimension) / Double(image.height))
    let width = Double(image.width) * ratio
    let height = Double(image.height) * ratio
    context.draw(image, in: CGRect(
        x: (Double(dimension) - width) / 2,
        y: (Double(dimension) - height) / 2, width: width, height: height))
    return context.makeImage()!
}

// Android small notification icons use a white alpha mask. Take the actual
// download arrow/tray from the supplied logo, without its opaque background.
let arrowRect = CGRect(
    x: Double(original.width) * 0.394, y: Double(original.height) * 0.519,
    width: Double(original.width) * 0.207, height: Double(original.height) * 0.178).integral
let arrow = original.cropping(to: arrowRect)!
let maskContext = CGContext(
    data: nil, width: arrow.width, height: arrow.height, bitsPerComponent: 8,
    bytesPerRow: arrow.width * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
maskContext.draw(arrow, in: CGRect(x: 0, y: 0, width: arrow.width, height: arrow.height))
let pixels = maskContext.data!.assumingMemoryBound(to: UInt8.self)
for index in 0..<(arrow.width * arrow.height) {
    let offset = index * 4
    let brightness = Int(max(pixels[offset], max(pixels[offset + 1], pixels[offset + 2])))
    let alpha = UInt8(max(0, min(255, (brightness - 48) * 255 / 128)))
    for channel in 0..<4 { pixels[offset + channel] = alpha }
}
let notificationMark = maskContext.makeImage()!

try writePNG(scaled(logo, dimension: 1024), "assets/icon/app_logo.png")
try writePNG(scaled(logo, dimension: 512), "android/app/src/main/res/drawable-nodpi/brand_logo.png")
for (density, dimension, notificationDimension) in [
    ("mdpi", 48, 24), ("hdpi", 72, 36), ("xhdpi", 96, 48),
    ("xxhdpi", 144, 72), ("xxxhdpi", 192, 96)
] {
    for (name, round) in [("ic_launcher", false), ("ic_launcher_round", true)] {
        try writePNG(scaled(logo, dimension: dimension, round: round),
            "android/app/src/main/res/mipmap-\(density)/\(name).png")
    }
    // Center the proportional mark in a 24 dp notification canvas with padding.
    let context = CGContext(
        data: nil, width: notificationDimension, height: notificationDimension,
        bitsPerComponent: 8, bytesPerRow: notificationDimension * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let width = Double(notificationDimension) * 0.84
    let height = width * Double(notificationMark.height) / Double(notificationMark.width)
    context.interpolationQuality = .high
    context.draw(notificationMark, in: CGRect(
        x: (Double(notificationDimension) - width) / 2,
        y: (Double(notificationDimension) - height) / 2, width: width, height: height))
    try writePNG(context.makeImage()!,
        "android/app/src/main/res/drawable-\(density)/ic_notification.png")
}
