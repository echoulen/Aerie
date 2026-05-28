#!/usr/bin/env swift
import AppKit
import CoreImage

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sources/Aerie/Resources/noise.png")
let size = CGSize(width: 256, height: 256)
let filter = CIFilter(name: "CIRandomGenerator")!
guard let image = filter.outputImage?.cropped(to: CGRect(origin: .zero, size: size)) else {
    fatalError("CIRandomGenerator produced no image")
}
let ctx = CIContext()
guard let cgImage = ctx.createCGImage(image, from: image.extent) else {
    fatalError("CIContext could not create CGImage")
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Bitmap could not produce PNG data")
}
try data.write(to: outputURL)
print("Wrote \(outputURL.path)")
