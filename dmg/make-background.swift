// Genera dmg/background.tiff (1x + 2x Retina) con las instrucciones que se ven al abrir el DMG.
// Uso: swift dmg/make-background.swift   (después se versiona el .tiff; solo hace falta repetirlo si cambia el texto)
import AppKit

let W = 520, H = 420   // tamaño de la ventana en puntos; los iconos van en (150, 232) y (370, 232) desde arriba; zona visible segura ~300 pt (Finder añade barras)

func render(scale s: Int, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W * s, pixelsHigh: H * s, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)   // con 2x queda a 144 dpi, como exige tiffutil -cathidpicheck
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(starting: NSColor(white: 0.98, alpha: 1), ending: NSColor(white: 0.90, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    func text(_ str: String, size: CGFloat, bold: Bool = false, gray: CGFloat, y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
            .foregroundColor: NSColor(white: gray, alpha: 1),
        ]
        let w = (str as NSString).size(withAttributes: attrs).width
        (str as NSString).draw(at: NSPoint(x: (CGFloat(W) - w) / 2, y: y), withAttributes: attrs)
    }
    text("M999Battery", size: 24, bold: true, gray: 0.12, y: CGFloat(H) - 92)
    text("Si macOS la bloquea: Ajustes > Privacidad y seguridad > Abrir de todos modos", size: 11, gray: 0.45, y: CGFloat(H) - 114)
    text("Doble clic en la app para instalarla en /Applications", size: 14, bold: true, gray: 0.20, y: CGFloat(H) - 152)
    text("o arrástrala a Applications", size: 12, gray: 0.35, y: CGFloat(H) - 172)

    // Flecha entre la app (izquierda) y Applications (derecha)
    let arrow = NSBezierPath()
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 228, y: CGFloat(H) - 232)); arrow.line(to: NSPoint(x: 292, y: CGFloat(H) - 232))
    arrow.move(to: NSPoint(x: 283, y: CGFloat(H) - 223)); arrow.line(to: NSPoint(x: 292, y: CGFloat(H) - 232))
    arrow.line(to: NSPoint(x: 283, y: CGFloat(H) - 241))
    NSColor(white: 0.45, alpha: 1).setStroke(); arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(scale: 1, to: "dmg/background.png")
render(scale: 2, to: "dmg/background@2x.png")
