import AppKit
import SwiftMath
import SwiftUI

/// Renders LaTeX to images via SwiftMath, cached. Inline images carry their descent so they
/// can sit on the text baseline.
@MainActor
enum MathRenderer {
    struct Rendered { let image: NSImage; let descent: CGFloat }

    private static var cache: [String: Rendered] = [:]

    static func render(_ latex: String, size: CGFloat, display: Bool) -> Rendered? {
        let key = "\(display)|\(size)|\(latex)"
        if let hit = cache[key] { return hit }

        let mode: MTMathUILabelMode = display ? .display : .text
        let color = NSColor.white.withAlphaComponent(0.92)

        // MTMathUILabel exposes the laid-out display list (for descent); MTMathImage draws.
        let label = MTMathUILabel()
        label.labelMode = mode
        label.fontSize = size
        label.latex = latex
        guard label.error == nil else { return nil }
        label.frame.size = label.fittingSize
        label.layout()

        let img = MTMathImage(latex: latex, fontSize: size, textColor: color, labelMode: mode, textAlignment: .left)
        let (err, image) = img.asImage()
        guard err == nil, let image else { return nil }

        let r = Rendered(image: image, descent: label.displayList?.descent ?? 0)
        if cache.count > 500 { cache.removeAll() }
        cache[key] = r
        return r
    }
}

/// Builds a single Text from Markdown with `$…$` / `\(…\)` math rendered inline.
@MainActor
enum RichText {
    // 1: code span (left as-is)  2: \( … \)  3: $ … $ (no space inside the delimiters, not currency)
    private static let pattern = try! NSRegularExpression(
        pattern: #"(`[^`\n]*`)|\\\((.+?)\\\)|(?<![\\$\w])\$(?![\s$])([^$\n]+?)(?<!\s)\$(?![\d$])"#)

    static func make(_ s: String, size: CGFloat) -> Text {
        let ns = s as NSString
        var out = Text("")
        var last = 0
        for m in pattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard m.range(at: 1).location == NSNotFound else { continue }  // code span
            let latexRange = m.range(at: 2).location != NSNotFound ? m.range(at: 2) : m.range(at: 3)
            let latex = ns.substring(with: latexRange)
            guard let r = MathRenderer.render(latex, size: size * 1.05, display: false) else { continue }
            out = Text("\(out)\(markdown(ns.substring(with: NSRange(location: last, length: m.range.location - last))))")
            out = Text("\(out)\(Text(Image(nsImage: r.image)).baselineOffset(-r.descent))")
            last = m.range.location + m.range.length
        }
        return Text("\(out)\(markdown(ns.substring(from: last)))")
    }

    private static func markdown(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s))
    }
}

struct DisplayMath: View {
    let latex: String
    let size: CGFloat

    var body: some View {
        if let r = MathRenderer.render(latex, size: size * 1.15, display: true) {
            // Wide equations shrink to fit the panel rather than scroll.
            Image(nsImage: r.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: r.image.size.width)
                .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        } else {
            Text(latex).font(.system(size: size * 0.85, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
