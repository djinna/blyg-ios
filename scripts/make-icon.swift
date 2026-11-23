// Draws Blyglet's app icons: the "C6 curl", a piglet's tail drawn as one rising stroke with round ends.
// The curl was designed on a claude.ai design canvas (2026-11-23); its outline is copied here exactly, in
// that canvas's SVG units, so the script needs no other file.
// Usage: swift scripts/make-icon.swift Blyg/Assets.xcassets
// Writes the primary icon (light, dark, tinted), one alternate icon set per palette, and small previews for
// the in-app picker. The picker's list lives in Blyg/Theme/AppIcons.swift; keep the two in step.
import AppKit

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// The curl's outline, as on the canvas: one M…L…Z polygon, in units placed by `translate(371.5 411.1) scale(75.908)`
/// on a 1024 × 1024 SVG (y down). Two circles round off its ends.
let outline = """
M-1.028 4.490L-0.880 4.400L-0.729 4.303L-0.581 4.202L-0.435 4.099L-0.292 3.993L-0.151 3.884L-0.014 3.773L0.120
3.659L0.250 3.542L0.377 3.424L0.500 3.303L0.620 3.181L0.736 3.057L0.847 2.931L0.954 2.803L1.057 2.675L1.156
2.545L1.250 2.414L1.339 2.282L1.424 2.149L1.504 2.016L1.579 1.883L1.650 1.749L1.715 1.615L1.775 1.481L1.830
1.347L1.880 1.214L1.924 1.081L1.963 0.948L1.997 0.816L2.026 0.686L2.049 0.556L2.066 0.427L2.078 0.299L2.085
0.173L2.085 0.049L2.081 -0.074L2.070 -0.194L2.054 -0.313L2.032 -0.429L2.004 -0.542L1.971 -0.653L1.932
-0.760L1.887 -0.865L1.837 -0.965L1.782 -1.062L1.721 -1.154L1.655 -1.242L1.585 -1.325L1.510 -1.403L1.431
-1.476L1.348 -1.543L1.261 -1.605L1.172 -1.662L1.079 -1.712L0.984 -1.757L0.887 -1.796L0.789 -1.830L0.688
-1.857L0.587 -1.879L0.485 -1.896L0.382 -1.907L0.279 -1.912L0.176 -1.913L0.073 -1.908L-0.029 -1.898L-0.131
-1.883L-0.232 -1.864L-0.332 -1.840L-0.431 -1.811L-0.528 -1.778L-0.624 -1.740L-0.718 -1.698L-0.810
-1.653L-0.900 -1.603L-0.988 -1.549L-1.073 -1.492L-1.155 -1.431L-1.235 -1.366L-1.311 -1.298L-1.385
-1.227L-1.455 -1.152L-1.521 -1.075L-1.584 -0.995L-1.642 -0.911L-1.697 -0.826L-1.747 -0.737L-1.792
-0.647L-1.833 -0.554L-1.869 -0.459L-1.900 -0.362L-1.925 -0.264L-1.945 -0.165L-1.959 -0.064L-1.967 0.037L-1.970
0.139L-1.966 0.242L-1.956 0.344L-1.940 0.445L-1.917 0.546L-1.889 0.646L-1.854 0.744L-1.812 0.841L-1.765
0.935L-1.711 1.027L-1.652 1.117L-1.587 1.203L-1.517 1.287L-1.442 1.367L-1.361 1.443L-1.275 1.516L-1.185
1.586L-1.090 1.652L-0.990 1.713L-0.886 1.771L-0.779 1.825L-0.667 1.875L-0.551 1.921L-0.432 1.963L-0.310
2.000L-0.184 2.034L-0.054 2.063L0.078 2.088L0.213 2.108L0.351 2.125L0.492 2.137L0.635 2.144L0.780 2.148L0.928
2.147L1.077 2.142L1.229 2.132L1.382 2.118L1.536 2.099L1.692 2.077L1.849 2.050L2.007 2.018L2.166 1.982L2.325
1.943L2.484 1.898L2.644 1.850L2.804 1.798L2.963 1.741L3.122 1.681L3.281 1.616L3.438 1.548L3.595 1.476L3.750
1.400L3.904 1.321L4.057 1.238L4.208 1.152L4.357 1.063L4.503 0.970L4.648 0.874L4.790 0.776L4.929 0.674L5.066
0.570L5.199 0.464L5.330 0.355L5.457 0.243L5.579 0.132L5.213 -0.279L5.093 -0.176L4.972 -0.077L4.848 0.020L4.722
0.114L4.592 0.206L4.460 0.296L4.326 0.383L4.189 0.467L4.051 0.548L3.911 0.626L3.769 0.701L3.626 0.773L3.481
0.841L3.336 0.906L3.190 0.968L3.043 1.025L2.896 1.079L2.749 1.130L2.602 1.177L2.456 1.219L2.310 1.258L2.164
1.294L2.020 1.325L1.877 1.352L1.735 1.376L1.594 1.395L1.456 1.411L1.319 1.422L1.185 1.430L1.053 1.434L0.924
1.435L0.797 1.431L0.674 1.424L0.553 1.414L0.436 1.400L0.323 1.383L0.213 1.362L0.107 1.339L0.004 1.312L-0.094
1.282L-0.187 1.250L-0.277 1.215L-0.362 1.178L-0.442 1.139L-0.518 1.098L-0.590 1.055L-0.657 1.010L-0.719
0.964L-0.776 0.917L-0.829 0.868L-0.878 0.819L-0.922 0.769L-0.962 0.718L-0.997 0.667L-1.029 0.616L-1.056
0.564L-1.080 0.512L-1.100 0.460L-1.117 0.408L-1.130 0.355L-1.139 0.303L-1.146 0.250L-1.149 0.197L-1.149
0.144L-1.146 0.091L-1.139 0.038L-1.130 -0.015L-1.117 -0.068L-1.102 -0.121L-1.083 -0.174L-1.061 -0.226L-1.036
-0.278L-1.007 -0.330L-0.976 -0.380L-0.942 -0.430L-0.906 -0.478L-0.866 -0.526L-0.824 -0.572L-0.779
-0.616L-0.733 -0.658L-0.684 -0.699L-0.632 -0.737L-0.580 -0.774L-0.525 -0.808L-0.469 -0.840L-0.412
-0.869L-0.353 -0.895L-0.294 -0.919L-0.234 -0.940L-0.174 -0.958L-0.114 -0.974L-0.053 -0.986L0.007 -0.996L0.067
-1.002L0.126 -1.006L0.184 -1.006L0.242 -1.004L0.298 -0.999L0.353 -0.991L0.406 -0.981L0.458 -0.968L0.508
-0.952L0.556 -0.933L0.603 -0.913L0.647 -0.889L0.690 -0.864L0.731 -0.836L0.770 -0.806L0.807 -0.773L0.842
-0.738L0.875 -0.701L0.907 -0.661L0.936 -0.618L0.964 -0.573L0.989 -0.524L1.013 -0.473L1.034 -0.418L1.052
-0.361L1.068 -0.300L1.081 -0.236L1.092 -0.169L1.099 -0.098L1.103 -0.025L1.103 0.052L1.100 0.132L1.093
0.214L1.082 0.300L1.067 0.388L1.047 0.478L1.024 0.571L0.996 0.666L0.964 0.763L0.927 0.861L0.886 0.961L0.840
1.063L0.790 1.166L0.735 1.270L0.676 1.374L0.612 1.479L0.543 1.585L0.471 1.690L0.394 1.796L0.312 1.902L0.227
2.007L0.137 2.112L0.044 2.216L-0.054 2.318L-0.155 2.420L-0.259 2.521L-0.368 2.620L-0.479 2.718L-0.594
2.813L-0.712 2.907L-0.833 2.999L-0.956 3.088L-1.082 3.176L-1.211 3.260L-1.341 3.342L-1.474 3.421L-1.614 3.501Z
"""
let ends: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [(-1.321, 3.996, 0.575), (5.396, -0.074, 0.275)]

/// The curl as separate shapes, filled one by one so their overlaps can't cancel out.
func curlShapes() -> [CGPath] {
    // The literal is wrapped at spaces, so a line break separates two numbers.
    let numbers = outline.split(whereSeparator: { "MLZ \n".contains($0) }).map { Double($0)! }
    precondition(numbers.count % 2 == 0, "odd number of coordinates in the curl outline")
    let body = CGMutablePath()
    for i in stride(from: 0, to: numbers.count, by: 2) {
        let p = CGPoint(x: numbers[i], y: numbers[i + 1])
        if i == 0 { body.move(to: p) } else { body.addLine(to: p) }
    }
    body.closeSubpath()
    return [body] + ends.map { CGPath(ellipseIn: CGRect(x: $0.x - $0.r, y: $0.y - $0.r, width: 2 * $0.r, height: 2 * $0.r), transform: nil) }
}

func render(ground: UInt32, ink: UInt32, size: Int = 1024, to url: URL) throws {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(color(ground))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    // SVG coordinates: flip to y-down, scale the 1024 canvas to this size, then the canvas's own placement.
    let k = CGFloat(size) / 1024
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: k, y: -k)
    ctx.translateBy(x: 371.5, y: 411.1)
    ctx.scaleBy(x: 75.908, y: 75.908)
    ctx.setFillColor(color(ink))
    for shape in curlShapes() {
        ctx.addPath(shape)
        ctx.fillPath()
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

/// One palette: the asset name's suffix, the ground and the curl. The first is the default icon.
let palettes: [(name: String, ground: UInt32, ink: UInt32)] = [
    ("PencilBlue", 0x23608C, 0xFBFAF6),
    ("Paper", 0xFBFAF6, 0x23608C),
    ("Ink", 0x111819, 0x9CCBE8),
    ("Sky", 0x9CCBE8, 0x111819),
    ("PigletPink", 0xF4C7CF, 0x111819),
    ("PigletPinkOnWhite", 0xFFFFFF, 0xD9677F),
    ("PencilBluePinkCurl", 0x23608C, 0xF4C7CF),
    ("PencilBlueCoralCurl", 0x23608C, 0xF5A58E),
    ("WarmPigPink", 0xF5BFAE, 0x111819),
    ("Coral", 0xEE9A82, 0x111819),
    ("Moss", 0xCDE3C6, 0x111819),
    ("Butter", 0xF3E3A6, 0x111819),
]
/// Dark home screens: a deeper Pencil blue with the same curl. Tinted home screens: gray artwork on black,
/// which iOS colors itself.
let dark = (ground: UInt32(0x173F5C), ink: UInt32(0xFBFAF6))
let tinted = (ground: UInt32(0x000000), ink: UInt32(0xE6E6E6))

let catalog = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
func folder(_ name: String) throws -> URL {
    let url = catalog.appending(path: name)
    try fm.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func iconEntry(_ file: String, _ appearance: String? = nil) -> [String: Any] {
    var e: [String: Any] = ["filename": file, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
    if let appearance { e["appearances"] = [["appearance": "luminosity", "value": appearance]] }
    return e
}
let info: [String: Any] = ["author": "xcode", "version": 1]

// The primary icon.
let primary = try folder("AppIcon.appiconset")
try render(ground: palettes[0].ground, ink: palettes[0].ink, to: primary.appending(path: "AppIcon.png"))
try render(ground: dark.ground, ink: dark.ink, to: primary.appending(path: "AppIcon-dark.png"))
try render(ground: tinted.ground, ink: tinted.ink, to: primary.appending(path: "AppIcon-tinted.png"))
try writeJSON(["images": [iconEntry("AppIcon.png"), iconEntry("AppIcon-dark.png", "dark"), iconEntry("AppIcon-tinted.png", "tinted")], "info": info],
              to: primary.appending(path: "Contents.json"))

// Alternate icons, one light-only set each, and a 180 px preview of every palette for the picker.
let previews = try folder("IconPreviews")
try writeJSON(["info": info, "properties": ["provides-namespace": true]], to: previews.appending(path: "Contents.json"))
for (i, p) in palettes.enumerated() {
    if i > 0 {
        let set = try folder("AppIcon-\(p.name).appiconset")
        try render(ground: p.ground, ink: p.ink, to: set.appending(path: "Icon.png"))
        try writeJSON(["images": [iconEntry("Icon.png")], "info": info], to: set.appending(path: "Contents.json"))
    }
    let preview = try folder("IconPreviews/\(p.name).imageset")
    try render(ground: p.ground, ink: p.ink, size: 180, to: preview.appending(path: "\(p.name).png"))
    try writeJSON(["images": [["filename": "\(p.name).png", "idiom": "universal", "scale": "3x"]], "info": info],
                  to: preview.appending(path: "Contents.json"))
}
print("Wrote \(palettes.count) palettes to \(catalog.path)")
