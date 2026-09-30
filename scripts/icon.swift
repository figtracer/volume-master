import AppKit

let output = CommandLine.arguments[1]
let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(red: 0.043, green: 0.051, blue: 0.071, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p*0.04, y: p*0.04, width: p*0.92, height: p*0.92), xRadius: p*0.21, yRadius: p*0.21).fill()
        NSColor(red: 0.447, green: 0.863, blue: 0.812, alpha: 1).setFill()
        let heights: [CGFloat] = [0.19, 0.39, 0.58, 0.39, 0.19]
        for (index, height) in heights.enumerated() {
            NSBezierPath(roundedRect: NSRect(x: p*(0.235 + CGFloat(index)*0.115), y: p*(1-height)/2,
                                             width: p*0.07, height: p*height), xRadius: p*0.035, yRadius: p*0.035).fill()
        }
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory.path, "-o", output]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
