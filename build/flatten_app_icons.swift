import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let folder = URL(fileURLWithPath: "/Users/kithkui/Desktop/Anky/Anky/Assets.xcassets/AppIcon.appiconset")
let bg = NSColor(calibratedRed: 0.30, green: 0.37, blue: 0.58, alpha: 1.0).cgColor
let fm = FileManager.default
let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "png" }

for file in files {
    guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fputs("Failed to load \(file.path)\n", stderr)
        exit(1)
    }

    let width = image.width
    let height = image.height
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fputs("Failed to create CGContext for \(file.path)\n", stderr)
        exit(1)
    }

    context.setFillColor(bg)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let outputImage = context.makeImage(),
          let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fputs("Failed to create output for \(file.path)\n", stderr)
        exit(1)
    }

    CGImageDestinationAddImage(dest, outputImage, nil)
    if !CGImageDestinationFinalize(dest) {
        fputs("Failed to save \(file.path)\n", stderr)
        exit(1)
    }
    print("Flattened \(file.lastPathComponent)")
}
