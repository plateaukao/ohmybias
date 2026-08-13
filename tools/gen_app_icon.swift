import AppKit

// 產生 app icon（.iconset 用 png）：黑色圓角鍵帽 + 白色「米」
// 選單圖示由 ComponentInputModeDict 的 tsInputModeMenuIconFileKey（icon.tiff，模板反轉）負責；
// icns 是 app icon（Finder／系統設定），用實心白字才不會在深色背景下看不見。
// 幾何比照系統鍵帽實測（/System/.../KIM_Extension.appex 2SetKorean.tiff @2x）：
//   滿版（inset 0）、圓角 ≈ 2pt/16pt、字符約 10x11pt
// 用法：swift gen_app_icon.swift <輸出目錄>  → 產生 AppIcon.iconset/，再用 iconutil 轉 icns

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let s = CGFloat(pixels)
    let scale = s / 16.0

    // 滿版鍵帽，圓角 2pt（系統實測值；先前 3.6 太圓、0.5 inset 偏小）
    let radius = 2.0 * scale
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor.black.setFill()
    path.fill()

    // 「米」：實心白字
    let fontSize = 10.5 * scale
    let font = NSFont(name: "PingFangTC-Semibold", size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let str = NSAttributedString(string: "米", attributes: attrs)
    let size = str.size()
    let origin = NSPoint(x: (s - size.width) / 2, y: (s - size.height) / 2 - 0.2 * scale)
    str.draw(at: origin)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let setDir = outDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: setDir, withIntermediateDirectories: true)

// (檔名, 像素) — 標準 iconset 全尺寸
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    let rep = drawIcon(pixels: px)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(setDir)/\(name).png"))
}
print("iconset written to \(setDir)")
