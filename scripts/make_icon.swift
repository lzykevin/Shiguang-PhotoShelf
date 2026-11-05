import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = size * factor
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let p = CGFloat(pixels)
        let rect = NSRect(x: p * 0.08, y: p * 0.08, width: p * 0.84, height: p * 0.84)
        let path = NSBezierPath(roundedRect: rect, xRadius: p * 0.19, yRadius: p * 0.19)
        NSGradient(starting: NSColor(calibratedRed: 0.23, green: 0.55, blue: 0.94, alpha: 1), ending: NSColor(calibratedRed: 0.12, green: 0.29, blue: 0.66, alpha: 1))!.draw(in: path, angle: -90)
        let symbol = NSImage(systemSymbolName: "photo.stack.fill", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: p * 0.43, weight: .regular))!
        let image = NSImage(size: symbol.size, flipped: false) { rect in symbol.draw(in: rect); NSColor.white.set(); rect.fill(using: .sourceAtop); return true }
        image.draw(in: NSRect(x: p * 0.23, y: p * 0.25, width: p * 0.54, height: p * 0.5))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (factor == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
