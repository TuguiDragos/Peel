// Draws the background of Peel's disk image window at 1x and 2x: the album's paper, an arc of dots from Peel to
// Applications, and a warm light where Peel is dropped. Finder draws the icons and their names on top.
//
// Usage: swift Scripts/dmg_background.swift <folder> <width> <height> <peel x> <applications x> <icons y>
// Positions are the icons' centers in points from the window's top left corner, as Finder places them.
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
let numbers = arguments.dropFirst().compactMap(Double.init)
guard arguments.count == 6, numbers.count == 5 else {
    print("usage: swift dmg_background.swift <folder> <width> <height> <peel x> <applications x> <icons y>")
    exit(64)
}
let folder = URL(filePath: arguments[0], directoryHint: .isDirectory)
let width = CGFloat(numbers[0]), height = CGFloat(numbers[1])
let peel = NSPoint(x: numbers[2], y: height - numbers[4]), applications = NSPoint(x: numbers[3], y: height - numbers[4])

// The album's Sheet and PeelOrange, from the app's asset catalog.
let paper = NSColor(srgbRed: 0.962, green: 0.952, blue: 0.930, alpha: 1)
let orange = NSColor(srgbRed: 1, green: 0.55, blue: 0.13, alpha: 1)

func point(_ a: NSPoint, _ c: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
    let u = 1 - t
    return NSPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
}

func draw() {
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    paper.setFill()
    bounds.fill()
    let middle = NSPoint(x: width / 2, y: height * 0.55)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: middle, radius: 0, toCenter: middle, radius: width * 0.62, options: [])
    let edge = NSColor(srgbRed: 0.45, green: 0.35, blue: 0.2, alpha: 0.07)
    NSGradient(colors: [edge.withAlphaComponent(0), edge])!
        .draw(fromCenter: NSPoint(x: width / 2, y: height / 2), radius: width * 0.45,
              toCenter: NSPoint(x: width / 2, y: height / 2), radius: width * 0.8, options: [])
    NSGradient(colors: [orange.withAlphaComponent(0.16), orange.withAlphaComponent(0)])!
        .draw(fromCenter: applications, radius: 0, toCenter: applications, radius: 118, options: [])

    // The arc runs a little above the icons' centers, from beside one icon to beside the other.
    let start = NSPoint(x: peel.x + 80, y: peel.y + 12), end = NSPoint(x: applications.x - 78, y: applications.y + 12)
    let control = NSPoint(x: (start.x + end.x) / 2, y: start.y + 40)
    let dots = 14
    for index in 0..<dots {
        let t = CGFloat(index) / CGFloat(dots) * 0.93
        let center = point(start, control, end, t)
        let radius = 2.2 + 1.6 * t
        orange.withAlphaComponent(0.45 + 0.55 * t).setFill()
        let dot = NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        NSBezierPath(ovalIn: dot).fill()
    }
    let before = point(start, control, end, 0.97)
    let angle = atan2(end.y - before.y, end.x - before.x), length: CGFloat = 15
    let head = NSBezierPath()
    head.move(to: NSPoint(x: end.x - length * cos(angle - 0.62), y: end.y - length * sin(angle - 0.62)))
    head.line(to: end)
    head.line(to: NSPoint(x: end.x - length * cos(angle + 0.62), y: end.y - length * sin(angle + 0.62)))
    head.lineWidth = 4.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    orange.setStroke()
    head.stroke()
}

for (scale, name) in [(1, "background.png"), (2, "background@2x.png")] {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appending(path: name))
}
