#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Renders a crisp native macOS squircle AppIcon.iconset (16px through 1024px) with zero external dependencies.

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // macOS Big Sur+ icon inset (~9.7% margin for standard squircle visual weight)
    let inset = size * 0.095
    let cardRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = cardRect.width * 0.225
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Subtle outer drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.018),
        blur: size * 0.04,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
    )
    ctx.addPath(cardPath)
    ctx.setFillColor(CGColor(red: 0.06, green: 0.07, blue: 0.13, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle
    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()

    // Deep obsidian-indigo background gradient
    let bgColors = [
        CGColor(red: 0.07, green: 0.07, blue: 0.16, alpha: 1.0),
        CGColor(red: 0.11, green: 0.08, blue: 0.25, alpha: 1.0),
        CGColor(red: 0.04, green: 0.11, blue: 0.21, alpha: 1.0)
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.52, 1.0]) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
            end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
            options: []
        )
    }

    // Iridescent top-left violet aurora glow
    let violetGlowColors = [
        CGColor(red: 0.56, green: 0.35, blue: 1.0, alpha: 0.55),
        CGColor(red: 0.56, green: 0.35, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let glow = CGGradient(colorsSpace: colorSpace, colors: violetGlowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: cardRect.minX + cardRect.width * 0.25, y: cardRect.maxY - cardRect.height * 0.2),
            startRadius: 0,
            endCenter: CGPoint(x: cardRect.minX + cardRect.width * 0.25, y: cardRect.maxY - cardRect.height * 0.2),
            endRadius: cardRect.width * 0.65,
            options: []
        )
    }

    // Iridescent bottom-right cyan aurora glow
    let cyanGlowColors = [
        CGColor(red: 0.10, green: 0.85, blue: 0.96, alpha: 0.45),
        CGColor(red: 0.10, green: 0.85, blue: 0.96, alpha: 0.0)
    ] as CFArray
    if let glow = CGGradient(colorsSpace: colorSpace, colors: cyanGlowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: cardRect.maxX - cardRect.width * 0.22, y: cardRect.minY + cardRect.height * 0.2),
            startRadius: 0,
            endCenter: CGPoint(x: cardRect.maxX - cardRect.width * 0.22, y: cardRect.minY + cardRect.height * 0.2),
            endRadius: cardRect.width * 0.62,
            options: []
        )
    }

    // Subtle precision aperture ring
    let center = CGPoint(x: size * 0.5, y: size * 0.5)
    let ringRadius = cardRect.width * 0.34
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.14))
    ctx.setLineWidth(max(1.0, size * 0.012))
    ctx.strokeEllipse(in: CGRect(
        x: center.x - ringRadius,
        y: center.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    ))

    // Stylised Velora "V" / downward prism arrow emblem
    let chevronPath = CGMutablePath()
    let topY = center.y + cardRect.height * 0.22
    let midY = center.y - cardRect.height * 0.14
    let leftX = center.x - cardRect.width * 0.23
    let rightX = center.x + cardRect.width * 0.23

    chevronPath.move(to: CGPoint(x: leftX, y: topY))
    chevronPath.addLine(to: CGPoint(x: center.x, y: midY))
    chevronPath.addLine(to: CGPoint(x: rightX, y: topY))

    let strokeWidth = max(2.0, cardRect.width * 0.11)
    let strokedChevron = chevronPath.copy(
        strokingWithWidth: strokeWidth,
        lineCap: .round,
        lineJoin: .round,
        miterLimit: 4
    )

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.015),
        blur: size * 0.04,
        color: CGColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.55)
    )
    ctx.addPath(strokedChevron)
    ctx.clip()

    let emblemColors = [
        CGColor(red: 0.77, green: 0.58, blue: 1.0, alpha: 1.0),
        CGColor(red: 0.44, green: 0.69, blue: 1.0, alpha: 1.0),
        CGColor(red: 0.15, green: 0.92, blue: 0.96, alpha: 1.0)
    ] as CFArray
    if let emblemGrad = CGGradient(colorsSpace: colorSpace, colors: emblemColors, locations: [0.0, 0.5, 1.0]) {
        ctx.drawLinearGradient(
            emblemGrad,
            start: CGPoint(x: leftX, y: topY + strokeWidth),
            end: CGPoint(x: rightX, y: midY - strokeWidth),
            options: []
        )
    }
    ctx.restoreGState()

    // Sleek luminous download tray bar beneath the V prism
    let trayWidth = cardRect.width * 0.36
    let trayHeight = max(2.0, cardRect.height * 0.068)
    let trayRect = CGRect(
        x: center.x - trayWidth * 0.5,
        y: center.y - cardRect.height * 0.30,
        width: trayWidth,
        height: trayHeight
    )
    let trayPath = CGPath(roundedRect: trayRect, cornerWidth: trayHeight * 0.5, cornerHeight: trayHeight * 0.5, transform: nil)
    ctx.saveGState()
    ctx.addPath(trayPath)
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.92))
    ctx.fillPath()
    ctx.restoreGState()

    // Glass rim highlight around the squircle
    ctx.addPath(cardPath)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.20))
    ctx.setLineWidth(max(1.0, size * 0.012))
    ctx.strokePath()

    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    guard let pngData = renderIcon(pixelSize: px) else {
        fputs("Failed to render \(filename)\n", stderr)
        exit(1)
    }
    try pngData.write(to: iconsetURL.appendingPathComponent(filename))
}
