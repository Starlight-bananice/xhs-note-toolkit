import AppKit
import Foundation

// Original vector artwork; draw every icon size independently for crisp edges.
func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255,
            blue: CGFloat(hex & 255)/255, alpha: alpha)
}
func rounded(_ rect: CGRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func draw() {
    let shadow = NSShadow(); shadow.shadowColor = color(0x71152c, alpha: 0.22)
    shadow.shadowBlurRadius = 25; shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    let tile = NSBezierPath(roundedRect: CGRect(x: 72, y: 72, width: 880, height: 880), xRadius: 198, yRadius: 198)
    NSGradient(starting: color(0xff6379), ending: color(0xdd244d))!.draw(in: tile, angle: -65)
    NSGraphicsContext.restoreGraphicsState()
    rounded(CGRect(x: 194, y: 216, width: 466, height: 563), 64, color(0xffffff, alpha: 0.26))
    let paperShadow = NSShadow(); paperShadow.shadowColor = color(0x941c36, alpha: 0.15)
    paperShadow.shadowBlurRadius = 28; paperShadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState(); paperShadow.set()
    rounded(CGRect(x: 262, y: 263, width: 470, height: 570), 64, color(0xfffcf8))
    NSGraphicsContext.restoreGraphicsState()
    rounded(CGRect(x: 334, y: 686, width: 208, height: 30), 15, color(0xf14b68))
    rounded(CGRect(x: 334, y: 611, width: 282, height: 26), 13, color(0xf6d5da))
    rounded(CGRect(x: 334, y: 542, width: 213, height: 26), 13, color(0xf6d5da))
    // Two interlocking, oblique links remain readable at Dock sizes.
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform(); transform.translateX(by: 620, yBy: 370)
    transform.rotate(byDegrees: 38); transform.concat()
    color(0x202a40).setStroke()
    for x: CGFloat in [-173, -3] {
        let link = NSBezierPath(roundedRect: CGRect(x: x, y: -67, width: 225, height: 134), xRadius: 67, yRadius: 67)
        link.lineWidth = 39; link.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    rounded(CGRect(x: 726, y: 686, width: 38, height: 38), 19, color(0xffd6bc))
}

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")
let set = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points*scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(size)/1024); transform.concat()
        draw(); context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        let png = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: set.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if size == 1024 { try png.write(to: root.appendingPathComponent("AppIcon.png")) }
    }
}
// ICNS stores PNG representations directly; this avoids depending on iconutil's image service.
func uint32(_ value: Int) -> Data { var word = UInt32(value).bigEndian; return withUnsafeBytes(of: &word) { Data($0) } }
let members = [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"),
               ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
               ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"), ("ic12", "icon_32x32@2x.png"),
               ("ic13", "icon_128x128@2x.png"), ("ic14", "icon_256x256@2x.png")]
var body = Data()
for (type, filename) in members {
    let png = try Data(contentsOf: set.appendingPathComponent(filename))
    body.append(Data(type.utf8)); body.append(uint32(png.count+8)); body.append(png)
}
var icns = Data("icns".utf8); icns.append(uint32(body.count+8)); icns.append(body)
let destination = root.appendingPathComponent("AppIcon.icns")
try icns.write(to: destination)
guard NSImage(contentsOf: destination) != nil else { fatalError("无法读取生成的应用图标") }
