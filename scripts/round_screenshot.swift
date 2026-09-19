// Trims a uniform border from a screenshot and rounds its corners, so README
// images sit on the page the way the window does on screen.
//
//   swift scripts/round_screenshot.swift <file.png> [cornerRadius]
//
// The radius is in pixels of the source image; a 2x Retina capture wants twice
// the point value of the real window.
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: round_screenshot.swift <file.png> [radius]\n".utf8))
    exit(2)
}
let path = args[1]
let requestedRadius = args.count > 2 ? Double(args[2]) : nil

guard let source = NSImage(contentsOfFile: path),
      let tiff = source.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    FileHandle.standardError.write(Data("error: cannot read \(path)\n".utf8))
    exit(1)
}

let width = rep.pixelsWide, height = rep.pixelsHigh

/// How many identical rows/columns of the corner colour sit around the content.
func uniformInset() -> Int {
    guard let corner = rep.colorAt(x: 0, y: 0) else { return 0 }
    func matches(_ x: Int, _ y: Int) -> Bool {
        guard let c = rep.colorAt(x: x, y: y) else { return false }
        return abs(c.redComponent - corner.redComponent) < 0.02
            && abs(c.greenComponent - corner.greenComponent) < 0.02
            && abs(c.blueComponent - corner.blueComponent) < 0.02
    }
    var inset = 0
    let limit = min(width, height) / 4
    while inset < limit {
        // A ring is part of the border only if it is uniform all the way round.
        let mid = height / 2
        let midX = width / 2
        guard matches(inset, mid), matches(width - 1 - inset, mid),
              matches(midX, inset), matches(midX, height - 1 - inset) else { break }
        inset += 1
    }
    return inset
}

let inset = uniformInset()
let cropped = NSRect(x: inset, y: inset, width: width - 2 * inset, height: height - 2 * inset)
let radius = requestedRadius ?? min(cropped.width, cropped.height) * 0.035

guard let context = CGContext(
    data: nil,
    width: Int(cropped.width), height: Int(cropped.height),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write(Data("error: cannot create context\n".utf8))
    exit(1)
}

let bounds = CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height)
context.beginPath()
context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
context.clip()

guard let cgSource = rep.cgImage,
      let croppedCG = cgSource.cropping(to: CGRect(
          x: cropped.origin.x,
          y: CGFloat(height) - cropped.origin.y - cropped.height,
          width: cropped.width,
          height: cropped.height)) else {
    FileHandle.standardError.write(Data("error: cannot crop\n".utf8))
    exit(1)
}
context.draw(croppedCG, in: bounds)

guard let output = context.makeImage() else { exit(1) }
let outRep = NSBitmapImageRep(cgImage: output)
guard let png = outRep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: path))

print("\((path as NSString).lastPathComponent): trimmed \(inset)px border, \(Int(cropped.width))x\(Int(cropped.height)), radius \(Int(radius))px")
