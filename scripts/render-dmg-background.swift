#!/usr/bin/env swift
import AppKit

private enum Layout {
    static let size = CGSize(width: 1360, height: 840)
    static let appPad = CGRect(x: 300, y: 392, width: 220, height: 196)
    static let applicationsPad = CGRect(x: 840, y: 392, width: 220, height: 196)
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render-dmg-background.swift <output.png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(Layout.size.width),
    pixelsHigh: Int(Layout.size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: .alphaFirst,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("error: could not create bitmap\n", stderr)
    exit(1)
}

bitmap.size = Layout.size

guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("error: could not create graphics context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("error: could not create graphics context\n", stderr)
    exit(1)
}

func rectFromTop(_ rect: CGRect) -> CGRect {
    CGRect(
        x: rect.minX,
        y: Layout.size.height - rect.minY - rect.height,
        width: rect.width,
        height: rect.height
    )
}

func pointFromTop(x: CGFloat, y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: Layout.size.height - y)
}

func drawText(
    _ text: String,
    in rect: CGRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .center
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(in: rectFromTop(rect))
}

NSColor(srgbRed: 0.953, green: 0.973, blue: 0.968, alpha: 1).setFill()
NSBezierPath(rect: CGRect(origin: .zero, size: Layout.size)).fill()

let topBand = NSBezierPath(rect: rectFromTop(CGRect(x: 0, y: 0, width: Layout.size.width, height: 18)))
NSColor(srgbRed: 0.106, green: 0.129, blue: 0.157, alpha: 1).setFill()
topBand.fill()

drawText(
    "Drag TokenAtlas to Applications",
    in: CGRect(x: 150, y: 142, width: 1060, height: 86),
    font: .systemFont(ofSize: 62, weight: .medium),
    color: NSColor(srgbRed: 0.105, green: 0.118, blue: 0.135, alpha: 1)
)

drawText(
    "Install once. Future releases arrive through Sparkle updates.",
    in: CGRect(x: 300, y: 232, width: 760, height: 34),
    font: .systemFont(ofSize: 22, weight: .regular),
    color: NSColor(srgbRed: 0.330, green: 0.380, blue: 0.420, alpha: 1)
)

func drawLandingPad(_ topRect: CGRect) {
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 24,
        color: NSColor.black.withAlphaComponent(0.10).cgColor
    )

    let padPath = NSBezierPath(roundedRect: rectFromTop(topRect), xRadius: 30, yRadius: 30)
    NSColor.white.withAlphaComponent(0.82).setFill()
    padPath.fill()
    context.restoreGState()

    NSColor(srgbRed: 0.760, green: 0.825, blue: 0.840, alpha: 0.70).setStroke()
    padPath.lineWidth = 2
    padPath.stroke()
}

drawLandingPad(Layout.appPad)
drawLandingPad(Layout.applicationsPad)

let arrowPath = NSBezierPath()
arrowPath.move(to: pointFromTop(x: 594, y: 490))
arrowPath.line(to: pointFromTop(x: 766, y: 490))
arrowPath.move(to: pointFromTop(x: 734, y: 466))
arrowPath.line(to: pointFromTop(x: 766, y: 490))
arrowPath.line(to: pointFromTop(x: 734, y: 514))
arrowPath.lineWidth = 9
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
NSColor(srgbRed: 0.913, green: 0.365, blue: 0.208, alpha: 1).setStroke()
arrowPath.stroke()

drawText(
    "Open the disk image, then drag the app icon onto the Applications folder.",
    in: CGRect(x: 250, y: 690, width: 860, height: 34),
    font: .systemFont(ofSize: 18, weight: .regular),
    color: NSColor(srgbRed: 0.370, green: 0.430, blue: 0.460, alpha: 1)
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("error: could not encode PNG\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
