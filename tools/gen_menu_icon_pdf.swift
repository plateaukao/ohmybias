import AppKit
import CoreText

// 產生輸入法選單模板圖示 menu_icon.pdf：黑色圓角鍵帽 + 鏤空「米」（even-odd 單一路徑）
// Tahoe 的輸入法選單只把「單色向量 PDF」當模板圖示（自動深淺反轉）；灰階 tiff 會被
// 退回改用 app icon（彩色、不反轉）。
// 幾何實測自系統選單截圖（@2x）：鍵帽 44x32px = 22x16pt「橫向」、圓角 ≈ 4pt、
// 字符墨高 ≈ 9.5pt（あ/한 同級）。Squirrel 的 16x16 正方形在系統橫向鍵帽旁反而突兀。
// 用法：swift gen_menu_icon_pdf.swift <輸出目錄>

let W: CGFloat = 22
let H: CGFloat = 16
let radius: CGFloat = 4.0
let glyphInkHeight: CGFloat = 9.5

let font = CTFontCreateWithName("PingFangTC-Semibold" as CFString, 12, nil)
var ch: [UniChar] = Array("米".utf16)
var glyph = CGGlyph()
guard CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1), glyph != 0,
      let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil) else {
    fatalError("no glyph path for 米")
}

// 縮放到目標墨高並置中
let gb = glyphPath.boundingBoxOfPath
let k = glyphInkHeight / gb.height
var xform = CGAffineTransform(translationX: (W - gb.width * k) / 2, y: (H - gb.height * k) / 2)
    .scaledBy(x: k, y: k)
    .translatedBy(x: -gb.minX, y: -gb.minY)
let centeredGlyph = glyphPath.copy(using: &xform)!

let path = CGMutablePath()
path.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: W, height: H),
                    cornerWidth: radius, cornerHeight: radius, transform: nil))
path.addPath(centeredGlyph)

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let url = URL(fileURLWithPath: outDir + "/menu_icon.pdf") as CFURL
var box = CGRect(x: 0, y: 0, width: W, height: H)
guard let ctx = CGContext(url, mediaBox: &box, nil) else { fatalError("pdf ctx") }
ctx.beginPDFPage(nil)
ctx.addPath(path)
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fillPath(using: .evenOdd)
ctx.endPDFPage()
ctx.closePDF()
print("menu_icon.pdf written \(Int(W))x\(Int(H))pt")
