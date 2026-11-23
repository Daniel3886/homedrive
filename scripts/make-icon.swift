// Draws the HomeDrive app icon: a house carrying an up and a down arrow
// (files going to and coming from your home PC) on a blue squircle.
//
// Usage: swift scripts/make-icon.swift <output.iconset> [preview.png]
import AppKit

let args = CommandLine.arguments.dropFirst()
let out = URL(fileURLWithPath: args.first ?? "HomeDrive.iconset")
let preview = args.dropFirst().first.map { URL(fileURLWithPath: $0) }
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// An arrow pointing up (or down), centred on `x`, spanning `bottom...top`.
func arrow(x: CGFloat, bottom: CGFloat, top: CGFloat, up: Bool) -> CGPath {
    let shaft: CGFloat = 50, head: CGFloat = 136, headLength: CGFloat = 104
    let p = CGMutablePath()
    if up {
        p.move(to: CGPoint(x: x - shaft / 2, y: bottom))
        p.addLine(to: CGPoint(x: x - shaft / 2, y: top - headLength))
        p.addLine(to: CGPoint(x: x - head / 2, y: top - headLength))
        p.addLine(to: CGPoint(x: x, y: top))
        p.addLine(to: CGPoint(x: x + head / 2, y: top - headLength))
        p.addLine(to: CGPoint(x: x + shaft / 2, y: top - headLength))
        p.addLine(to: CGPoint(x: x + shaft / 2, y: bottom))
    } else {
        p.move(to: CGPoint(x: x - shaft / 2, y: top))
        p.addLine(to: CGPoint(x: x - shaft / 2, y: bottom + headLength))
        p.addLine(to: CGPoint(x: x - head / 2, y: bottom + headLength))
        p.addLine(to: CGPoint(x: x, y: bottom))
        p.addLine(to: CGPoint(x: x + head / 2, y: bottom + headLength))
        p.addLine(to: CGPoint(x: x + shaft / 2, y: bottom + headLength))
        p.addLine(to: CGPoint(x: x + shaft / 2, y: top))
    }
    p.closeSubpath()
    return p
}

/// Draws the icon on a 1024×1024 canvas (scaled to the requested pixel size).
func render(_ px: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    ctx.setShouldAntialias(true)

    // Squircle on Apple's macOS icon grid: 824pt body, 100pt margins.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x2F3BD0))
    ctx.fillPath()
    ctx.restoreGState()

    // Background: blue → indigo, plus a soft glow from the top.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [color(0x5AA2FF), color(0x3A5BF0), color(0x3021B5)] as CFArray,
                        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])
    ctx.restoreGState()

    // House: roof + walls as one rounded shape.
    let house = CGMutablePath()
    house.move(to: CGPoint(x: 512, y: 792))       // roof apex
    house.addLine(to: CGPoint(x: 838, y: 518))    // right eave
    house.addLine(to: CGPoint(x: 748, y: 518))
    house.addLine(to: CGPoint(x: 748, y: 238))    // right wall bottom
    house.addLine(to: CGPoint(x: 276, y: 238))
    house.addLine(to: CGPoint(x: 276, y: 518))
    house.addLine(to: CGPoint(x: 186, y: 518))    // left eave
    house.closeSubpath()
    let rounded = house.copy(strokingWithWidth: 44, lineCap: .round, lineJoin: .round, miterLimit: 1)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x10105A, 0.45))
    ctx.addPath(house)
    ctx.addPath(rounded)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath(using: .winding)
    ctx.restoreGState()

    // Subtle shading on the house so it doesn't look flat.
    ctx.saveGState()
    ctx.addPath(house)
    ctx.addPath(rounded)
    ctx.clip(using: .winding)
    let shade = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xE3E8FF)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(shade, start: CGPoint(x: 512, y: 820), end: CGPoint(x: 512, y: 210), options: [])
    ctx.restoreGState()

    // The two arrows: up = send (orange), down = retrieve (blue).
    let send = arrow(x: 440, bottom: 282, top: 560, up: true)
    let retrieve = arrow(x: 584, bottom: 282, top: 560, up: false)
    for (path, top, bottom) in [(send, 0xFFB340, 0xFF7A1A), (retrieve, 0x4FA8FF, 0x2F5BEA)] as [(CGPath, UInt32, UInt32)] {
        // Fill the arrow and a thin rounded outline of it separately; combining the two paths
        // in one clip would cancel out where their windings disagree.
        let soft = path.copy(strokingWithWidth: 16, lineCap: .round, lineJoin: .round, miterLimit: 1)
        let g = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
        for part in [path, soft] {
            ctx.saveGState()
            ctx.addPath(part)
            ctx.clip()
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 580), end: CGPoint(x: 0, y: 270),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if let preview { try! render(1024).write(to: preview) }
print("Wrote \(out.path)")
