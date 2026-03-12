#!/usr/bin/env swift

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "assets/AppIcon-1024.png"
let outputURL = URL(fileURLWithPath: outputPath)

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
} catch {
    fputs("Failed to create icon directory: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let size: CGFloat = 1024
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: canvas.size)

image.lockFocus()

NSColor(calibratedRed: 0.03, green: 0.10, blue: 0.18, alpha: 1.0).setFill()
NSBezierPath(rect: canvas).fill()

let tileRect = canvas.insetBy(dx: 72, dy: 72)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 180, yRadius: 180)
if let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.45, alpha: 1.0),
    NSColor(calibratedRed: 0.09, green: 0.20, blue: 0.33, alpha: 1.0)
]) {
    gradient.draw(in: tilePath, angle: 90)
}

NSGraphicsContext.current?.saveGraphicsState()
tilePath.addClip()
NSColor.white.withAlphaComponent(0.07).setStroke()
for i in stride(from: tileRect.minY + 40, through: tileRect.maxY, by: 44) {
    let path = NSBezierPath()
    path.lineWidth = 2
    path.move(to: NSPoint(x: tileRect.minX, y: i))
    path.curve(
        to: NSPoint(x: tileRect.maxX, y: i),
        controlPoint1: NSPoint(x: tileRect.minX + 240, y: i + 14),
        controlPoint2: NSPoint(x: tileRect.minX + 500, y: i - 14)
    )
    path.stroke()
}
NSGraphicsContext.current?.restoreGraphicsState()

let ringRect = NSRect(x: 212, y: 212, width: 600, height: 600)
let ringPath = NSBezierPath(ovalIn: ringRect)
NSColor.white.withAlphaComponent(0.18).setFill()
ringPath.fill()

let symbolRect = NSRect(x: 236, y: 236, width: 552, height: 552)
if let ferrySymbol = NSImage(systemSymbolName: "ferry.fill", accessibilityDescription: "Ferry") {
    let pointConfig = NSImage.SymbolConfiguration(pointSize: 430, weight: .regular)
    let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: NSColor.white.withAlphaComponent(0.95))
    let mergedConfig = pointConfig.applying(colorConfig)
    let configured = ferrySymbol.withSymbolConfiguration(mergedConfig) ?? ferrySymbol
    configured.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
} else {
    let ferry = "⛴︎"
    let ferryAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 390, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.95)
    ]
    let ferrySize = ferry.size(withAttributes: ferryAttributes)
    ferry.draw(
        at: NSPoint(
            x: (size - ferrySize.width) / 2,
            y: ((size - ferrySize.height) / 2) + 20
        ),
        withAttributes: ferryAttributes
    )
}

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiffData),
    let pngData = rep.representation(using: .png, properties: [.compressionFactor: 1.0])
else {
    fputs("Failed to encode PNG icon.\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: outputURL, options: .atomic)
    print("Generated icon: \(outputURL.path)")
} catch {
    fputs("Failed to write icon: \(error.localizedDescription)\n", stderr)
    exit(1)
}
