#!/usr/bin/swift

import AppKit

func fail(_ message: String) -> Never {
  fputs("Error: \(message)\n", stderr)
  exit(1)
}

guard CommandLine.arguments.count >= 2 else {
  fail("Usage: generate_dmg_background.swift OUTPUT_PATH [APP_NAME]")
}

let outputPath = CommandLine.arguments[1]
let productName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "App"
let size = NSSize(width: 700, height: 420)
let bounds = NSRect(origin: .zero, size: size)
guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: Int(size.width),
  pixelsHigh: Int(size.height),
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fail("Unable to create bitmap context")
}

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
  fail("Unable to create graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.restoreGraphicsState() }

let gradient = NSGradient(colors: [
  NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.97, alpha: 1),
  NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
])

gradient?.draw(in: bounds, angle: -90)

let framePath = NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 8), xRadius: 26, yRadius: 26)
NSColor(calibratedRed: 0.85, green: 0.87, blue: 0.9, alpha: 1).setStroke()
framePath.lineWidth = 2
framePath.stroke()

let title = "Drag \(productName) to Applications"
let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center

let titleAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
  .foregroundColor: NSColor(calibratedRed: 0.2, green: 0.24, blue: 0.28, alpha: 1),
  .paragraphStyle: titleStyle
]

title.draw(
  in: NSRect(x: 60, y: 320, width: size.width - 120, height: 32),
  withAttributes: titleAttributes
)

let subtitle = "Then open \(productName) from your Applications folder"
let subtitleAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 14, weight: .regular),
  .foregroundColor: NSColor(calibratedRed: 0.39, green: 0.42, blue: 0.46, alpha: 1),
  .paragraphStyle: titleStyle
]

subtitle.draw(
  in: NSRect(x: 90, y: 288, width: size.width - 180, height: 22),
  withAttributes: subtitleAttributes
)

let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: 330, y: 222))
arrowPath.line(to: NSPoint(x: 356, y: 222))
arrowPath.line(to: NSPoint(x: 356, y: 238))
arrowPath.line(to: NSPoint(x: 405, y: 210))
arrowPath.line(to: NSPoint(x: 356, y: 182))
arrowPath.line(to: NSPoint(x: 356, y: 198))
arrowPath.line(to: NSPoint(x: 330, y: 198))
arrowPath.close()
arrowPath.lineWidth = 3
arrowPath.setLineDash([6, 6], count: 2, phase: 0)
NSColor(calibratedRed: 0.57, green: 0.6, blue: 0.65, alpha: 0.95).setStroke()
arrowPath.stroke()

let accentPath = NSBezierPath(roundedRect: NSRect(x: 70, y: 34, width: size.width - 140, height: 28), xRadius: 14, yRadius: 14)
NSColor(calibratedRed: 0.9, green: 0.92, blue: 0.95, alpha: 0.9).setFill()
accentPath.fill()

let footer = "After copying, eject this disk image"
let footerAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 12, weight: .medium),
  .foregroundColor: NSColor(calibratedRed: 0.33, green: 0.36, blue: 0.4, alpha: 1),
  .paragraphStyle: titleStyle
]

footer.draw(
  in: NSRect(x: 90, y: 41, width: size.width - 180, height: 16),
  withAttributes: footerAttributes
)

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
  fail("Unable to serialize PNG output")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
  at: outputURL.deletingLastPathComponent(),
  withIntermediateDirectories: true,
  attributes: nil
)

do {
  try pngData.write(to: outputURL)
} catch {
  fail("Unable to write background image: \(error.localizedDescription)")
}
