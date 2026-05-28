import AppKit

// Generates a 1280x640 GitHub social-preview image into the path given as arg1.

func cg(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}
func ns(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(red: r/255, green: g/255, blue: b/255, alpha: 1)
}

let W: CGFloat = 1280, H: CGFloat = 640

func drawEye(_ ctx: CGContext, center: CGPoint, ew: CGFloat) {
    let eh = ew * 0.58
    let cx = center.x, cy = center.y
    let L = CGPoint(x: cx - ew/2, y: cy), R = CGPoint(x: cx + ew/2, y: cy)
    let eye = CGMutablePath()
    eye.move(to: L)
    eye.addCurve(to: R, control1: CGPoint(x: cx - ew*0.25, y: cy + eh*0.5),
                 control2: CGPoint(x: cx + ew*0.25, y: cy + eh*0.5))
    eye.addCurve(to: L, control1: CGPoint(x: cx + ew*0.25, y: cy - eh*0.5),
                 control2: CGPoint(x: cx - ew*0.25, y: cy - eh*0.5))
    ctx.saveGState(); ctx.addPath(eye)
    ctx.setStrokeColor(cg(232, 238, 249)); ctx.setLineWidth(ew * 0.05); ctx.setLineJoin(.round)
    ctx.strokePath(); ctx.restoreGState()

    let irisR = eh * 0.46
    ctx.saveGState(); ctx.addPath(eye); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [cg(34,211,238), cg(37,99,235)] as CFArray, locations: [0,1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: irisR,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    let pr = irisR * 0.46
    ctx.setFillColor(cg(11,16,32))
    ctx.fillEllipse(in: CGRect(x: cx-pr, y: cy-pr, width: 2*pr, height: 2*pr))
    ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:0.9))
    ctx.fillEllipse(in: CGRect(x: cx-pr*0.2, y: cy+pr*0.1, width: pr*0.5, height: pr*0.5))
}

// y is the rect's bottom; in a non-flipped context text fills from the rect's TOP down.
func text(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
    let p = NSMutableParagraphStyle(); p.lineSpacing = 6
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
        .draw(in: NSRect(x: x, y: y, width: w, height: h))
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background gradient.
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [cg(67,56,202), cg(11,16,32)] as CFArray, locations: [0,1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W*0.7, y: 0), options: [])

// Icon badge (rounded square) on the left with the eye.
let side: CGFloat = 360, bx: CGFloat = 96, by = (H-side)/2
let badge = CGPath(roundedRect: CGRect(x: bx, y: by, width: side, height: side),
                   cornerWidth: side*0.2235, cornerHeight: side*0.2235, transform: nil)
ctx.saveGState(); ctx.addPath(badge); ctx.clip()
let badgeGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [cg(99,102,241), cg(17,24,48)] as CFArray, locations: [0,1])!
ctx.drawLinearGradient(badgeGrad, start: CGPoint(x: bx, y: by+side), end: CGPoint(x: bx, y: by), options: [])
ctx.restoreGState()
drawEye(ctx, center: CGPoint(x: bx+side/2, y: by+side/2), ew: side*0.66)

// Text block on the right (non-flipped context: y is from the bottom).
let tx: CGFloat = bx + side + 80, tw = W - tx - 60
text("Vigil", NSFont.systemFont(ofSize: 132, weight: .bold), .white, x: tx, y: 300, w: tw, h: 170)
text("Your Mac stays awake while your\nAI agents work — and sleeps when they don't.",
     NSFont.systemFont(ofSize: 38, weight: .medium), ns(199,210,254), x: tx, y: 120, w: tw, h: 165)
text("github.com/botus-ai/vigil   ·   @degusto_ai",
     NSFont.systemFont(ofSize: 28, weight: .semibold), ns(34,211,238), x: tx, y: 48, w: tw, h: 50)

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "social-preview.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
