import AppKit
let folder = CommandLine.arguments[1]
let image = NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
let rect = NSRect(x:68,y:68,width:888,height:888)
let outline = NSBezierPath(roundedRect:rect,xRadius:205,yRadius:205)
NSGradient(starting:NSColor(red:0.15,green:0.23,blue:0.42,alpha:1), ending:NSColor(red:0.04,green:0.08,blue:0.19,alpha:1))!.draw(in:outline,angle:-65)
NSColor.white.withAlphaComponent(0.16).setStroke(); outline.lineWidth = 3; outline.stroke()
let heights: [CGFloat] = [110,220,360,480,300,190,100]
for (index,height) in heights.enumerated() {
    let bar = NSBezierPath(roundedRect:NSRect(x:244+CGFloat(index)*76,y:512-height/2,width:36,height:height),xRadius:18,yRadius:18)
    NSGradient(starting:NSColor(red:0.71,green:0.88,blue:1,alpha:1),ending:NSColor(red:0.4,green:0.6,blue:0.96,alpha:1))!.draw(in:bar,angle:90)
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:folder))
