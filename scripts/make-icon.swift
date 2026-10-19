import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else { fatalError("Pass the output iconset directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let size = points*scale
        guard let context = CGContext(data: nil,width: size,height: size,bitsPerComponent: 8,bytesPerRow: size*4,
            space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Could not create icon") }
        context.scaleBy(x: CGFloat(size)/1024,y: CGFloat(size)/1024)
        let background = CGPath(roundedRect: CGRect(x: 64,y: 64,width: 896,height: 896),cornerWidth: 190,cornerHeight: 190,transform: nil)
        context.setFillColor(CGColor(red: 0.16,green: 0.40,blue: 0.30,alpha: 1)); context.addPath(background); context.fillPath()
        context.setFillColor(CGColor(red: 0.93,green: 0.96,blue: 0.91,alpha: 1))
        // Original nested-space mark: a large leaf beside a nested pair and Desktop base.
        for rect in [CGRect(x: 206,y: 370,width: 340,height: 460),CGRect(x: 584,y: 610,width: 234,height: 220),
                     CGRect(x: 584,y: 370,width: 234,height: 202),CGRect(x: 206,y: 194,width: 612,height: 136)] {
            context.addPath(CGPath(roundedRect: rect,cornerWidth: 28,cornerHeight: 28,transform: nil)); context.fillPath()
        }
        guard let image = context.makeImage() else { fatalError("Could not render icon") }
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { fatalError("Could not write icon") }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not finish icon") }
    }
}
