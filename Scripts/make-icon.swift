import AppKit

// Renders an SVG into the PNG sizes an .icns needs.
//
// AppKit reads SVG directly, so no external converter is needed. The icon is
// drawn on a transparent canvas at each size rather than scaled from one
// bitmap, which keeps the small sizes crisp.
//
// Usage: swift Scripts/make-icon.swift <input.svg> <output.iconset>

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: make-icon.swift <input.svg> <output.iconset>\n".data(using: .utf8)!)
    exit(1)
}

let source = URL(fileURLWithPath: arguments[1])
let destination = URL(fileURLWithPath: arguments[2])

guard let image = NSImage(contentsOf: source) else {
    FileHandle.standardError.write("could not read \(source.path)\n".data(using: .utf8)!)
    exit(1)
}

try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

/// The sizes `iconutil` expects, with their file names.
let variants: [(pixels: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for variant in variants {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: variant.pixels,
            pixelsHigh: variant.pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let box = NSRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels)
    image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try? data.write(to: destination.appendingPathComponent(variant.name))
}

print("wrote \(variants.count) sizes to \(destination.lastPathComponent)")
