import AppKit

// A folded, continuous M ends in a speech tail. Use one silhouette at Dock
// and toolbar sizes, with enough inset for the native macOS icon mask.
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                        xRadius: 205, yRadius: 205)
NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.16, blue: 0.25, alpha: 1),
           ending: NSColor(srgbRed: 0.06, green: 0.32, blue: 0.36, alpha: 1))!
    .draw(in: tile, angle: 62)

let mark = NSBezierPath()
mark.move(to: NSPoint(x: 264, y: 320))
mark.line(to: NSPoint(x: 264, y: 645))
mark.curve(to: NSPoint(x: 346, y: 675), controlPoint1: NSPoint(x: 264, y: 695),
           controlPoint2: NSPoint(x: 313, y: 713))
mark.line(to: NSPoint(x: 512, y: 470))
mark.line(to: NSPoint(x: 680, y: 675))
mark.curve(to: NSPoint(x: 760, y: 644), controlPoint1: NSPoint(x: 713, y: 714),
           controlPoint2: NSPoint(x: 760, y: 692))
mark.line(to: NSPoint(x: 760, y: 445))
mark.curve(to: NSPoint(x: 693, y: 352), controlPoint1: NSPoint(x: 760, y: 395),
           controlPoint2: NSPoint(x: 735, y: 370))
mark.line(to: NSPoint(x: 580, y: 300))
mark.lineWidth = 82
mark.lineJoinStyle = .round
mark.lineCapStyle = .round
NSColor(srgbRed: 0.80, green: 0.99, blue: 0.89, alpha: 1).setStroke()
mark.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
