import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders the three icon concepts in a shared 1024-point coordinate system.
func renderIcon(concept: String, destination: URL) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw IconError.renderFailed }
    let teal = CGColor(colorSpace: colorSpace, components: [0.055, 0.31, 0.40, 1])!

    // A superellipse keeps the corners continuous, with transparent outer padding.
    let background = CGMutablePath()
    for step in 0...2048 {
        let angle = Double(step) * 2 * .pi / 2048
        let x = cos(angle)
        let y = sin(angle)
        let point = CGPoint(
            x: 512 + 448 * copysign(pow(abs(x), 0.5), x),
            y: 512 + 448 * copysign(pow(abs(y), 0.5), y)
        )
        if step == 0 { background.move(to: point) }
        else { background.addLine(to: point) }
    }
    background.closeSubpath()
    context.setFillColor(teal)
    context.addPath(background)
    context.fillPath()
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.setStrokeColor(CGColor(gray: 1, alpha: 1))
    context.setLineWidth(56)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    switch concept {
    case "a-mic-cursor":
        context.addPath(CGPath(
            roundedRect: CGRect(x: 430, y: 422, width: 164, height: 330),
            cornerWidth: 82, cornerHeight: 82, transform: nil
        ))
        context.fillPath()
        context.move(to: CGPoint(x: 332, y: 524))
        context.addLine(to: CGPoint(x: 332, y: 456))
        context.addCurve(to: CGPoint(x: 692, y: 456),
                         control1: CGPoint(x: 332, y: 256),
                         control2: CGPoint(x: 692, y: 256))
        context.addLine(to: CGPoint(x: 692, y: 524))
        context.strokePath()
        stroke(context, points: [(512, 306), (512, 236)])
        stroke(context, points: [(416, 236), (608, 236)])
    case "b-speech-cursor":
        let bubble = CGMutablePath()
        bubble.move(to: CGPoint(x: 382, y: 348))
        bubble.addLine(to: CGPoint(x: 326, y: 256))
        bubble.addLine(to: CGPoint(x: 326, y: 370))
        bubble.addQuadCurve(to: CGPoint(x: 268, y: 452), control: CGPoint(x: 268, y: 386))
        bubble.addLine(to: CGPoint(x: 268, y: 624))
        bubble.addQuadCurve(to: CGPoint(x: 360, y: 716), control: CGPoint(x: 268, y: 716))
        bubble.addLine(to: CGPoint(x: 664, y: 716))
        bubble.addQuadCurve(to: CGPoint(x: 756, y: 624), control: CGPoint(x: 756, y: 716))
        bubble.addLine(to: CGPoint(x: 756, y: 440))
        bubble.addQuadCurve(to: CGPoint(x: 664, y: 348), control: CGPoint(x: 756, y: 348))
        bubble.closeSubpath()
        context.addPath(bubble)
        context.strokePath()
        context.setLineCap(.butt)
        context.setLineWidth(44)
        stroke(context, points: [(512, 444), (512, 620)])
        stroke(context, points: [(472, 620), (552, 620)])
        stroke(context, points: [(472, 444), (552, 444)])
    case "c-untyped":
        stroke(context, points: [(376, 664), (256, 512), (376, 360)])
        stroke(context, points: [(648, 664), (768, 512), (648, 360)])
        stroke(context, points: [(460, 344), (564, 680)])
        // The diagonal knockout separates the cancellation stroke from the code glyph.
        context.setStrokeColor(teal)
        context.setLineWidth(100)
        stroke(context, points: [(292, 736), (732, 288)])
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(52)
        stroke(context, points: [(292, 736), (732, 288)])
    default:
        throw IconError.unknownConcept
    }
    guard let image = context.makeImage(),
          let output = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { throw IconError.renderFailed }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else { throw IconError.writeFailed }
}

/// Draws a rounded polyline without retaining path state between symbols.
func stroke(_ context: CGContext, points: [(CGFloat, CGFloat)]) {
    guard let first = points.first else { return }
    context.move(to: CGPoint(x: first.0, y: first.1))
    for point in points.dropFirst() {
        context.addLine(to: CGPoint(x: point.0, y: point.1))
    }
    context.strokePath()
}

enum IconError: Error {
    case renderFailed, writeFailed, unknownConcept
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift render-icon.swift <preview-directory>\n", stderr)
    exit(1)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for concept in ["a-mic-cursor", "b-speech-cursor", "c-untyped"] {
    try renderIcon(concept: concept, destination: directory.appendingPathComponent("\(concept).png"))
}
