// Draws Blyglet's app icon: an opening double quote mark ("66"), drawn as shapes so no font or SF Symbol is involved.
// Colours follow Blygger Studio's header (dark mode): light blue ground, near-black mark. The dark variant swaps them.
// Usage: swift scripts/make-icon.swift Blyg/Assets.xcassets/AppIcon.appiconset
import AppKit

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// One "6"-shaped quote: a round blob, and a tail rising from its left and curling to a point above it.
/// Returned as two shapes, filled separately so their overlap can't cancel out.
func quote(centerX cx: CGFloat, centerY cy: CGFloat, radius r: CGFloat) -> [CGPath] {
    let blob = CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: cx - r, y: cy + 0.05 * r))
    tail.addCurve(to: CGPoint(x: cx + 0.75 * r, y: cy + 2.15 * r),
                  control1: CGPoint(x: cx - 1.05 * r, y: cy + 1.25 * r),
                  control2: CGPoint(x: cx - 0.2 * r, y: cy + 2.05 * r))
    tail.addCurve(to: CGPoint(x: cx + 0.05 * r, y: cy + 0.95 * r),
                  control1: CGPoint(x: cx + 0.15 * r, y: cy + 1.75 * r),
                  control2: CGPoint(x: cx - 0.15 * r, y: cy + 1.35 * r))
    tail.closeSubpath()
    return [blob, tail]
}

func render(ground: UInt32, ink: UInt32, to url: URL) throws {
    let size = 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(color(ground))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.setFillColor(color(ink))
    let r: CGFloat = 132
    // The glyph spans cy - r ... cy + 2.15r; centre it on the canvas.
    let cy = 512 - 0.575 * r
    for cx in [512 - 1.3 * r, 512 + 1.2 * r] {
        for shape in quote(centerX: cx, centerY: cy, radius: r) {
            ctx.addPath(shape)
            ctx.fillPath()
        }
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try render(ground: 0x9CCBE8, ink: 0x111819, to: out.appending(path: "AppIcon.png"))
try render(ground: 0x111819, ink: 0x9CCBE8, to: out.appending(path: "AppIcon-dark.png"))
// Tinted home screens: grayscale artwork that iOS colours itself.
try render(ground: 0x000000, ink: 0xE6E6E6, to: out.appending(path: "AppIcon-tinted.png"))
