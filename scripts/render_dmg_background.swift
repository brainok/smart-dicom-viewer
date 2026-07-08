#!/usr/bin/env swift
import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "build/dmg-assets/background.png"

let width: CGFloat = 900
let height: CGFloat = 560

let appX: CGFloat = 250
let applicationsX: CGFloat = 650
let finderIconY: CGFloat = 330
let arrowCenterY = height - finderIconY

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

NSColor.white.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

func drawCentered(_ text: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let size = attributed.size()
    attributed.draw(in: NSRect(x: x - size.width / 2, y: y, width: size.width, height: size.height))
}

drawCentered(
    "Smart DICOM Viewer",
    x: width / 2,
    y: height - 118,
    font: .systemFont(ofSize: 46, weight: .bold),
    color: .black
)

drawCentered(
    "Drag Smart DICOM Viewer to Applications",
    x: width / 2,
    y: height - 158,
    font: .systemFont(ofSize: 21, weight: .regular),
    color: NSColor(white: 0.35, alpha: 1)
)

let arrowStartX = appX + 115
let arrowEndX = applicationsX - 120
let shaftHeight: CGFloat = 24
let headWidth: CGFloat = 58
let headHeight: CGFloat = 72
let shaftEndX = arrowEndX - headWidth

NSColor.black.setFill()

let shaftRect = NSRect(
    x: arrowStartX,
    y: arrowCenterY - shaftHeight / 2,
    width: shaftEndX - arrowStartX,
    height: shaftHeight
)
NSBezierPath(rect: shaftRect).fill()

let head = NSBezierPath()
head.move(to: NSPoint(x: arrowEndX, y: arrowCenterY))
head.line(to: NSPoint(x: shaftEndX, y: arrowCenterY + headHeight / 2))
head.line(to: NSPoint(x: shaftEndX, y: arrowCenterY - headHeight / 2))
head.close()
head.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render DMG background")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)
