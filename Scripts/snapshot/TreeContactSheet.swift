// Tiles a folder of snapshot PNGs into one labelled overview image, for reviewing the tree matrix at a glance.
//
//   xcrun swift Scripts/snapshot/TreeContactSheet.swift <png-dir> <output.png> [columns=4] [tile-width=402]
//
// Files are taken in name order (the matrix scenes are numbered); the output file itself is skipped.
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: TreeContactSheet.swift <png-dir> <output.png> [columns] [tile-width]")
    exit(1)
}
let directory = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let columns = arguments.count > 3 ? max(1, Int(arguments[3]) ?? 4) : 4
let tileWidth = arguments.count > 4 ? CGFloat(Double(arguments[4]) ?? 402) : 402

let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
let pngs = files
    .filter { $0.pathExtension.lowercased() == "png" && $0.standardizedFileURL != output.standardizedFileURL && !$0.lastPathComponent.hasPrefix("00-") }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
let images = pngs.compactMap { url -> (String, CGImage)? in
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return (url.deletingPathExtension().lastPathComponent, image)
}
guard let first = images.first?.1 else {
    print("no PNGs in \(directory.path)")
    exit(1)
}

let tileHeight = tileWidth * CGFloat(first.height) / CGFloat(first.width)
let gap: CGFloat = 12, label: CGFloat = 34, margin: CGFloat = 24
let rows = (images.count + columns - 1) / columns
let width = margin * 2 + CGFloat(columns) * tileWidth + CGFloat(columns - 1) * gap
let height = margin * 2 + CGFloat(rows) * (tileHeight + label) + CGFloat(rows - 1) * gap
let scale: CGFloat = 2

guard let context = CGContext(
    data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
context.scaleBy(x: scale, y: scale)
context.setFillColor(CGColor(srgbRed: 0x05 / 255, green: 0x07 / 255, blue: 0x0D / 255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = graphics
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(srgbRed: 0x8A / 255, green: 0x96 / 255, blue: 0xAD / 255, alpha: 1),
]
for (index, (name, image)) in images.enumerated() {
    let column = index % columns, row = index / columns
    let x = margin + CGFloat(column) * (tileWidth + gap)
    let top = margin + CGFloat(row) * (tileHeight + label + gap)
    // Core Graphics is y-up: flip the row order.
    let y = height - top - tileHeight
    context.draw(image, in: CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
    NSAttributedString(string: name, attributes: attributes).draw(at: CGPoint(x: x + 2, y: y - label + 10))
}
NSGraphicsContext.current = nil

guard let sheet = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: sheet).representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
print("wrote \(output.path) (\(images.count) tiles)")
