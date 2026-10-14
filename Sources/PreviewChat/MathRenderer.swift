import AppKit
import SwiftMath
import SwiftUI

/// Renders LaTeX to images via SwiftMath, cached. Inline images carry their descent so they
/// can sit on the text baseline.
@MainActor
enum MathRenderer {
    struct Rendered { let image: NSImage; let descent: CGFloat }

    private static var cache: [String: Rendered?] = [:]

    static func render(_ latex: String, size: CGFloat, display: Bool) -> Rendered? {
        let key = "\(display)|\(size)|\(latex)"
        if let hit = cache[key] { return hit }
        let r = LaTeX.parseable(latex).flatMap { draw($0, size: size, display: display) }
        if cache.count > 500 { cache.removeAll() }
        cache[key] = r
        return r
    }

    private static func draw(_ latex: String, size: CGFloat, display: Bool) -> Rendered? {
        let mode: MTMathUILabelMode = display ? .display : .text

        // MTMathUILabel exposes the laid-out display list (for descent); MTMathImage draws.
        let label = MTMathUILabel()
        label.labelMode = mode
        label.fontSize = size
        label.latex = latex
        label.frame.size = label.fittingSize
        label.layout()

        let img = MTMathImage(latex: latex, fontSize: size, textColor: NSColor.white.withAlphaComponent(0.92),
                              labelMode: mode, textAlignment: .left)
        let (err, image) = img.asImage()
        guard err == nil, let image else { return nil }
        return Rendered(image: image, descent: label.displayList?.descent ?? 0)
    }
}

/// Rewrites common LaTeX that SwiftMath doesn't support into equivalents it does.
enum LaTeX {
    private static let rewrites: [(String, String)] = [
        (#"\\[td]frac(?![a-zA-Z])"#, #"\\frac"#),
        (#"\\[td]binom(?![a-zA-Z])"#, #"\\binom"#),
        (#"\\operatorname\*?\{([^}]*)\}"#, #"\\mathrm{$1}"#),
        (#"\\boldsymbol(?![a-zA-Z])"#, #"\\bm"#),
        (#"\\intercal(?![a-zA-Z])"#, #"\\top"#),
        (#"\\[lr]Vert(?![a-zA-Z])"#, #"\\|"#),
        (#"\\[lr]vert(?![a-zA-Z])"#, "|"),
        (#"\\dots[bcmoi]?(?![a-zA-Z])"#, #"\\ldots"#),
        (#"\\(?:under|over)brace(?![a-zA-Z])"#, ""),
        (#"\\implies(?![a-zA-Z])"#, #"\\Rightarrow"#),
        (#"\\impliedby(?![a-zA-Z])"#, #"\\Leftarrow"#),
        (#"\\iff(?![a-zA-Z])"#, #"\\Leftrightarrow"#),
        (#"\\[hm]box(?![a-zA-Z])"#, #"\\text"#),
        (#"\\[Bb]igg?[lrm]?(?![a-zA-Z])"#, ""),
        (#"\\checkmark(?![a-zA-Z])"#, #"\\surd"#),
        (#"\\(?:tag|label)\*?\{[^}]*\}"#, ""),
        (#"\\(?:nonumber|notag)(?![a-zA-Z])"#, ""),
        (#"\\begin\{array\}\{[^}]*\}"#, #"\\begin{matrix}"#),
        (#"\\end\{array\}"#, #"\\end{matrix}"#),
        (#"\\begin\{(?:align|equation|gather)\*?\}"#, #"\\begin{aligned}"#),
        (#"\\end\{(?:align|equation|gather)\*?\}"#, #"\\end{aligned}"#),
    ]

    static func normalize(_ s: String) -> String {
        var s = s
        for (pattern, template) in rewrites {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s
    }

    /// Returns a version of `latex` SwiftMath can parse, or nil. Unknown commands that survive
    /// normalization are shown as upright text (`\foo` → `\mathrm{foo}`) rather than failing the formula.
    static func parseable(_ latex: String) -> String? {
        var s = normalize(latex)
        for _ in 0..<8 {
            var error: NSError?
            _ = MTMathListBuilder.build(fromString: s, error: &error)
            guard let error else { return s }
            let msg = error.localizedDescription
            guard let r = msg.range(of: #"\\[a-zA-Z]+"#, options: .regularExpression), msg.contains("Invalid command") else {
                return nil
            }
            let cmd = String(msg[r])
            s = s.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: cmd) + #"(?![a-zA-Z])"#, with: #"\\mathrm{\#(cmd.dropFirst())}"#,
                                       options: .regularExpression)
        }
        return nil
    }

    /// Heuristic for code spans/blocks that are really math (Claude sometimes wraps LaTeX in backticks).
    static func looksLikeMath(_ s: String) -> Bool {
        s.range(of: #"\\(frac|tfrac|dfrac|mu|sigma|Sigma|sum|prod|int|sqrt|alpha|beta|theta|lambda|pi|ln|log|exp|cdot|times|le|ge|mathbf|mathrm|begin\{[bp]?matrix\}|left|right|top|hat|bar)(?![a-zA-Z])|[_^]\{"#,
                options: .regularExpression) != nil
    }
}

/// Builds a single Text from Markdown with `$…$` / `\(…\)` math rendered inline.
/// Markdown is parsed once over the whole string (math swapped for placeholders), so emphasis
/// that wraps or spans math (`**… $x$ …**`) still works.
@MainActor
enum RichText {
    // 1: code span  2: \( … \)  3: $ … $ (no space inside the delimiters, not currency)
    private static let pattern = try! NSRegularExpression(
        pattern: #"`([^`\n]*)`|\\\((.+?)\\\)|(?<![\\$\w])\$(?![\s$])([^$\n]+?)(?<!\s)\$(?![\d$])"#)
    private static let open = "\u{E000}", close = "\u{E001}"

    static func make(_ s: String, size: CGFloat) -> Text {
        let ns = s as NSString
        var source = ""
        var maths: [String] = []
        var last = 0
        for m in pattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let latex: String
            if m.range(at: 1).location != NSNotFound {
                let code = ns.substring(with: m.range(at: 1))
                guard LaTeX.looksLikeMath(code) else { continue }  // real code: leave for Markdown
                latex = code
            } else {
                latex = ns.substring(with: m.range(at: 2).location != NSNotFound ? m.range(at: 2) : m.range(at: 3))
            }
            source += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            source += "\(open)\(maths.count)\(close)"
            maths.append(latex)
            last = m.range.location + m.range.length
        }
        source += ns.substring(from: last)

        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attr = (try? AttributedString(markdown: source, options: opts)) ?? AttributedString(source)

        var out = Text("")
        var cursor = attr.startIndex
        while let o = attr[cursor...].range(of: open), let c = attr[o.upperBound...].range(of: close) {
            out = Text("\(out)\(Text(AttributedString(attr[cursor..<o.lowerBound])))")
            if let i = Int(String(attr[o.upperBound..<c.lowerBound].characters)), i < maths.count {
                out = Text("\(out)\(math(maths[i], size: size))")
            }
            cursor = c.upperBound
        }
        return Text("\(out)\(Text(AttributedString(attr[cursor...])))")
    }

    private static func math(_ latex: String, size: CGFloat) -> Text {
        if let r = MathRenderer.render(latex, size: size * 1.05, display: false) {
            return Text(Image(nsImage: r.image)).baselineOffset(-r.descent)
        }
        // Unrenderable: show the source quietly instead of with raw $ delimiters.
        return Text(latex).font(.system(size: size * 0.85, design: .monospaced)).foregroundColor(.secondary)
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
