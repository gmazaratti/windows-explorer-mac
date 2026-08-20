import AppKit

// Renders the app icon: a Fluent-styled folder carrying an explorer's compass.
// Original artwork, drawn from scratch, so the app ships nothing of Microsoft's.
//
//   swiftc -O Tools/MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon <out.png> [size]

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: colors as CFArray, locations: locations)!
}

func drawIcon(in ctx: CGContext, size S: CGFloat) {
    let u = S / 1024                     // design units
    // Below this size the fine detail turns to mush, so the small variants get
    // a bolder, simplified rose, the way system icon sets ship per-size art.
    let small = S <= 64
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: (1024 - y) * u) }

    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // MARK: Folder back panel, with the tab along the top left.
    let back = CGMutablePath()
    let tabTop: CGFloat = 168, bodyTop: CGFloat = 300, bottom: CGFloat = 604
    let left: CGFloat = 84, right: CGFloat = 940, r: CGFloat = 58
    back.move(to: p(left, tabTop + r))
    back.addQuadCurve(to: p(left + r, tabTop), control: p(left, tabTop))
    back.addLine(to: p(430, tabTop))
    back.addLine(to: p(556, bodyTop))
    back.addLine(to: p(right - r, bodyTop))
    back.addQuadCurve(to: p(right, bodyTop + r), control: p(right, bodyTop))
    back.addLine(to: p(right, bottom))
    back.addLine(to: p(left, bottom))
    back.closeSubpath()

    ctx.saveGState()
    ctx.addPath(back)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xF0B32A), rgb(0xD79000)], [0, 1]),
                           start: p(0, tabTop), end: p(0, bottom), options: [])
    ctx.restoreGState()

    // MARK: Folder front panel.
    let frontTop: CGFloat = 322, frontBottom: CGFloat = 900
    let front = CGPath(roundedRect: CGRect(x: left * u, y: (1024 - frontBottom) * u,
                                           width: (right - left) * u,
                                           height: (frontBottom - frontTop) * u),
                       cornerWidth: 64 * u, cornerHeight: 64 * u, transform: nil)

    ctx.saveGState()
    if !small {
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 26 * u,
                      color: rgb(0x7A4E00, 0.35))
    }
    ctx.addPath(front)
    ctx.setFillColor(rgb(0xFFCE44))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(front)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFE08A), rgb(0xFFC42E)], [0, 1]),
                           start: p(180, frontTop), end: p(880, frontBottom), options: [])
    if !small {
        // Highlight along the top edge.
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.42))
        ctx.setLineWidth(10 * u)
        ctx.move(to: p(left + 60, frontTop + 6))
        ctx.addLine(to: p(right - 60, frontTop + 6))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // MARK: The explorer's mark: a compass rose on a Fluent badge.
    // Deliberately a rounded square rather than a disc, so it reads as its own
    // thing next to the circular compass Safari uses.
    let cx: CGFloat = 512, cy: CGFloat = 648
    let half: CGFloat = small ? 196 : 168

    let badgeRect = CGRect(x: (cx - half) * u, y: (1024 - cy - half) * u,
                           width: half * 2 * u, height: half * 2 * u)
    let badge = CGPath(roundedRect: badgeRect, cornerWidth: (small ? 66 : 58) * u,
                       cornerHeight: (small ? 66 : 58) * u, transform: nil)

    ctx.saveGState()
    if !small {
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u,
                      color: rgb(0x123A5C, 0.42))
    }
    ctx.addPath(badge)
    ctx.setFillColor(rgb(0x2E86D8))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(badge)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x62CCFF), rgb(0x1668B4)], [0, 1]),
                           start: p(cx - half, cy - half), end: p(cx + half, cy + half),
                           options: [])
    ctx.restoreGState()

    // Compass rose: four long points, four short ones.
    ctx.saveGState()
    ctx.translateBy(x: cx * u, y: (1024 - cy) * u)
    ctx.rotate(by: 0)

    let outer: CGFloat = (small ? 140 : 112) * u
    let inner: CGFloat = (small ? 46 : 36) * u
    let minor: CGFloat = (small ? 0 : 64) * u
    let points = small ? 4 : 8
    let rose = CGMutablePath()
    for i in 0..<points {
        let step = 2 * CGFloat.pi / CGFloat(points)
        let angle = CGFloat(i) * step
        let radius = (points == 4 || i % 2 == 0) ? outer : minor
        let point = CGPoint(x: sin(angle) * radius, y: cos(angle) * radius)
        if i == 0 { rose.move(to: point) } else { rose.addLine(to: point) }
        // Waist between each pair of points gives the rose its pinched shape.
        let waist = angle + step / 2
        rose.addLine(to: CGPoint(x: sin(waist) * inner, y: cos(waist) * inner))
    }
    rose.closeSubpath()

    ctx.addPath(rose)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()

    // North point picked out, the way a real rose marks it.
    let waistAngle = CGFloat.pi / (small ? 4 : 8)
    let north = CGMutablePath()
    north.move(to: CGPoint(x: 0, y: outer))
    north.addLine(to: CGPoint(x: sin(waistAngle) * inner, y: cos(waistAngle) * inner))
    north.addLine(to: CGPoint(x: -sin(waistAngle) * inner, y: cos(waistAngle) * inner))
    north.closeSubpath()
    ctx.addPath(north)
    ctx.setFillColor(rgb(0xE8453C))
    ctx.fillPath()

    if !small {
        ctx.addEllipse(in: CGRect(x: -13 * u, y: -13 * u, width: 26 * u, height: 26 * u))
        ctx.setFillColor(rgb(0x1668B4))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "/tmp/icon.png"
let size = CGFloat(args.count > 2 ? Double(args[2])! : 1024)

guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
drawIcon(in: ctx, size: size)
guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) at \(Int(size))px")
