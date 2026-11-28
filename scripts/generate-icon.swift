#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Renders a crisp native macOS squircle AppIcon.iconset (16px through 1024px)
// in the Precision Studio Cobalt aesthetic with zero external dependencies.

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func srgb(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

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

    // macOS Big Sur+ icon inset (~9.5% margin for standard squircle visual weight)
    let inset = size * 0.095
    let cardRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = cardRect.width * 0.225
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Subtle outer drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.018),
        blur: size * 0.04,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.36)
    )
    ctx.addPath(cardPath)
    ctx.setFillColor(srgb(0x0E1014))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle
    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()

    // Deep carbon obsidian studio gradient (#0E1014 -> #161B26)
    let bgColors = [
        srgb(0x0E1014),
        srgb(0x12161F),
        srgb(0x161B26)
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.5, 1.0]) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
            end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
            options: []
        )
    }

    // Restrained Cobalt studio top-light radial ambient sheen
    let cobaltSheenColors = [
        srgb(0x5B6CFF, alpha: 0.20),
        srgb(0x3B49DF, alpha: 0.07),
        srgb(0x3B49DF, alpha: 0.0)
    ] as CFArray
    if let sheen = CGGradient(colorsSpace: colorSpace, colors: cobaltSheenColors, locations: [0.0, 0.45, 1.0]) {
        let sheenCenter = CGPoint(x: cardRect.midX, y: cardRect.maxY - cardRect.height * 0.22)
        ctx.drawRadialGradient(
            sheen,
            startCenter: sheenCenter,
            startRadius: 0,
            endCenter: sheenCenter,
            endRadius: cardRect.width * 0.72,
            options: []
        )
    }

    // Precision machined studio aperture ring
    let center = CGPoint(x: size * 0.5, y: size * 0.5)
    let ringRadius = cardRect.width * 0.345
    ctx.setStrokeColor(srgb(0xFFFFFF, alpha: 0.08))
    ctx.setLineWidth(max(1.0, size * 0.01))
    ctx.strokeEllipse(in: CGRect(
        x: center.x - ringRadius,
        y: center.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    ))

    // Geometric Cobalt & Pearl-White "V" Prism Emblem
    let topY = center.y + cardRect.height * 0.22
    let apexY = center.y - cardRect.height * 0.145
    let leftX = center.x - cardRect.width * 0.235
    let rightX = center.x + cardRect.width * 0.235
    let strokeWidth = max(2.0, cardRect.width * 0.115)

    // Left + base Cobalt prism chevron (#5B6CFF -> #3B49DF)
    let fullChevron = CGMutablePath()
    fullChevron.move(to: CGPoint(x: leftX, y: topY))
    fullChevron.addLine(to: CGPoint(x: center.x, y: apexY))
    fullChevron.addLine(to: CGPoint(x: rightX, y: topY))

    let strokedChevron = fullChevron.copy(
        strokingWithWidth: strokeWidth,
        lineCap: .round,
        lineJoin: .round,
        miterLimit: 4
    )

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.015),
        blur: size * 0.045,
        color: srgb(0x3B49DF, alpha: 0.45)
    )
    ctx.addPath(strokedChevron)
    ctx.clip()

    let cobaltColors = [
        srgb(0x5B6CFF),
        srgb(0x4A5AF0),
        srgb(0x3B49DF)
    ] as CFArray
    if let cobaltGrad = CGGradient(colorsSpace: colorSpace, colors: cobaltColors, locations: [0.0, 0.5, 1.0]) {
        ctx.drawLinearGradient(
            cobaltGrad,
            start: CGPoint(x: leftX, y: topY + strokeWidth),
            end: CGPoint(x: rightX, y: apexY - strokeWidth),
            options: []
        )
    }
    ctx.restoreGState()

    // Crisp pearl-white specular prism wing on the right facet for sharp contrast at all sizes
    let pearlWing = CGMutablePath()
    pearlWing.move(to: CGPoint(x: center.x + cardRect.width * 0.02, y: apexY + cardRect.height * 0.032))
    pearlWing.addLine(to: CGPoint(x: rightX, y: topY))

    let strokedPearlWing = pearlWing.copy(
        strokingWithWidth: strokeWidth * 0.58,
        lineCap: .round,
        lineJoin: .round,
        miterLimit: 4
    )

    ctx.saveGState()
    ctx.addPath(strokedPearlWing)
    ctx.clip()
    let pearlColors = [
        srgb(0xF4F6FA, alpha: 0.96),
        srgb(0xDDE4FA, alpha: 0.88)
    ] as CFArray
    if let pearlGrad = CGGradient(colorsSpace: colorSpace, colors: pearlColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            pearlGrad,
            start: CGPoint(x: rightX, y: topY),
            end: CGPoint(x: center.x, y: apexY),
            options: []
        )
    }
    ctx.restoreGState()

    // Crisp pearl-white download tray bar beneath the "V" prism
    let trayWidth = cardRect.width * 0.36
    let trayHeight = max(2.0, cardRect.height * 0.068)
    let trayRect = CGRect(
        x: center.x - trayWidth * 0.5,
        y: center.y - cardRect.height * 0.30,
        width: trayWidth,
        height: trayHeight
    )
    let trayPath = CGPath(
        roundedRect: trayRect,
        cornerWidth: trayHeight * 0.5,
        cornerHeight: trayHeight * 0.5,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(trayPath)
    ctx.setFillColor(srgb(0xF4F6FA, alpha: 0.95))
    ctx.fillPath()
    ctx.restoreGState()

    // Subtle studio rim highlight around the squircle
    ctx.addPath(cardPath)
    ctx.setStrokeColor(srgb(0xFFFFFF, alpha: 0.14))
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
