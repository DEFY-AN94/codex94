import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_app_icon.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 1024
let height = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("failed to create bitmap context\n", stderr)
    exit(1)
}

let bounds = CGRect(x: 56, y: 56, width: 912, height: 912)
let tile = CGPath(roundedRect: bounds, cornerWidth: 210, cornerHeight: 210, transform: nil)
context.saveGState()
context.addPath(tile)
context.clip()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1),
        CGColor(red: 0.15, green: 0.17, blue: 0.21, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 170, y: 880),
    end: CGPoint(x: 870, y: 160),
    options: []
)
context.restoreGState()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: CGColor(gray: 0, alpha: 0.42))
context.addPath(tile)
context.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
context.setLineWidth(5)
context.strokePath()
context.restoreGState()

let center = CGPoint(x: 512, y: 530)
let radius: CGFloat = 275
context.setLineCap(.round)
context.setLineWidth(58)
context.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.strokePath()

context.setStrokeColor(CGColor(red: 0.32, green: 0.88, blue: 0.52, alpha: 1))
context.addArc(
    center: center,
    radius: radius,
    startAngle: -82 * .pi / 180,
    endAngle: 168 * .pi / 180,
    clockwise: false
)
context.strokePath()

context.setStrokeColor(CGColor(red: 0.98, green: 0.72, blue: 0.26, alpha: 1))
context.addArc(
    center: center,
    radius: radius,
    startAngle: 176 * .pi / 180,
    endAngle: 239 * .pi / 180,
    clockwise: false
)
context.strokePath()

let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
NSString(string: "94").draw(
    in: NSRect(x: 250, y: 384, width: 524, height: 292),
    withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 236, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
)
NSGraphicsContext.restoreGraphicsState()

context.setFillColor(CGColor(red: 0.32, green: 0.88, blue: 0.52, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 683, y: 353, width: 91, height: 20), cornerWidth: 10, cornerHeight: 10, transform: nil))
context.fillPath()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fputs("failed to prepare PNG output\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("failed to write PNG\n", stderr)
    exit(1)
}

