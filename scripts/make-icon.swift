import AppKit

// Generates Vigil's app icon (a watchful eye on a deep indigo squircle) into an
// .iconset directory. Usage: make-icon <output.iconset dir>

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: 1)
}

func draw(_ ctx: CGContext, _ s: CGFloat) {
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Rounded "squircle" background with a vertical indigo→navy gradient.
    let margin = s * 0.06
    let rect = CGRect(x: margin, y: margin, width: s - 2*margin, height: s - 2*margin)
    let radius = rect.width * 0.2235
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: space,
                          colors: [color(99, 102, 241), color(11, 16, 32)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Eye geometry.
    let cx = s/2, cy = s/2
    let ew = rect.width * 0.66
    let eh = ew * 0.58
    let L = CGPoint(x: cx - ew/2, y: cy)
    let R = CGPoint(x: cx + ew/2, y: cy)

    let eye = CGMutablePath()
    eye.move(to: L)
    eye.addCurve(to: R, control1: CGPoint(x: cx - ew*0.25, y: cy + eh*0.5),
                 control2: CGPoint(x: cx + ew*0.25, y: cy + eh*0.5))
    eye.addCurve(to: L, control1: CGPoint(x: cx + ew*0.25, y: cy - eh*0.5),
                 control2: CGPoint(x: cx - ew*0.25, y: cy - eh*0.5))

    // Eye outline.
    ctx.saveGState()
    ctx.addPath(eye)
    ctx.setStrokeColor(color(232, 238, 249))
    ctx.setLineWidth(s * 0.032)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Iris (radial cyan→blue), clipped to the eye so it sits inside.
    let irisR = eh * 0.46
    ctx.saveGState()
    ctx.addPath(eye)
    ctx.clip()
    let iris = CGGradient(colorsSpace: space,
                          colors: [color(34, 211, 238), color(37, 99, 235)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(iris,
                           startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: irisR,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Pupil + highlight.
    let pupilR = irisR * 0.46
    ctx.setFillColor(color(11, 16, 32))
    ctx.fillEllipse(in: CGRect(x: cx - pupilR, y: cy - pupilR, width: 2*pupilR, height: 2*pupilR))
    let hl = pupilR * 0.5
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: cx - pupilR*0.2, y: cy + pupilR*0.1, width: hl, height: hl))
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Vigil.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in specs {
    try! png(size: size).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("wrote \(specs.count) PNGs to \(out)")
