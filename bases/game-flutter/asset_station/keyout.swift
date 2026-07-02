// keyout — chroma-key 抠色出真 alpha(资产工位件)。
// 背景:图像模型的"transparent background"常输出【画出来的棋盘格】(假透明)。
// 方案:生成时要求纯品红底(#FF00FF,与游戏配色天然远离)→ 本工具键控成真透明 + 简单去边。
// 用法: keyout <in.png> <out.png> [tolerance 0-1, 默认 0.32]
import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func die(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(1) }

let args = CommandLine.arguments
guard args.count >= 3 else { die("用法: keyout <in.png> <out.png> [tolerance]") }
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let tol = args.count > 3 ? (Double(args[3]) ?? 0.32) : 0.32

guard let src = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { die("读图失败: \(args[1])") }

let w = img.width, h = img.height
let cs = CGColorSpaceCreateDeviceRGB()
var buf = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { die("ctx 失败") }
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

// 键控:与品红的距离 < tol → 透明;近边缘做渐变 alpha + 去品红溢色
let key: (Double, Double, Double) = (1.0, 0.0, 1.0)
for i in stride(from: 0, to: buf.count, by: 4) {
    let r = Double(buf[i]) / 255, g = Double(buf[i+1]) / 255, b = Double(buf[i+2]) / 255
    let d = ((r-key.0)*(r-key.0) + (g-key.1)*(g-key.1) + (b-key.2)*(b-key.2)).squareRoot() / 1.732
    if d < tol {
        buf[i+3] = 0; buf[i] = 0; buf[i+1] = 0; buf[i+2] = 0
    } else if d < tol * 1.5 {
        let a = (d - tol) / (tol * 0.5)          // 0..1 渐变
        // 去溢色:压制品红成分(取 rg/gb 中和)
        let ng = g, nr = min(r, ng + 0.25), nb = min(b, ng + 0.25)
        buf[i]   = UInt8(max(0, min(255, nr * a * 255)))
        buf[i+1] = UInt8(max(0, min(255, ng * a * 255)))
        buf[i+2] = UInt8(max(0, min(255, nb * a * 255)))
        buf[i+3] = UInt8(max(0, min(255, a * 255)))
    }
}

guard let outImg = ctx.makeImage() else { die("makeImage 失败") }
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { die("dest 失败") }
CGImageDestinationAddImage(dest, outImg, nil)
guard CGImageDestinationFinalize(dest) else { die("写出失败") }
print("keyout ✓ \(args[2])")
