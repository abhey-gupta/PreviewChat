import SwiftUI

/// Minimal block-level Markdown renderer: headings, lists, code fences, quotes, tables, rules.
/// Inline styling (bold, italic, code, links) is delegated to AttributedString.
struct MarkdownView: View {
    let text: String
    @AppStorage(Prefs.fontKey) private var fontChoice = ResponseFont.sourceSerif
    @AppStorage(Prefs.sizeKey) private var size = Prefs.defaultSize

    private func font(_ scale: CGFloat) -> Font { fontChoice.font(size: CGFloat(size) * scale) }

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(size) * 0.6) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(font(1))
        .lineSpacing(CGFloat(size) * 0.2)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let s):
            rich((s))
                .font(font(level == 1 ? 1.35 : level == 2 ? 1.18 : 1.05).weight(.semibold))
                .padding(.top, 4)
        case .paragraph(let s):
            rich((s))
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.marker).monospacedDigit().foregroundStyle(.secondary)
                        rich((item.text))
                    }
                    .padding(.leading, CGFloat(item.indent) * 14)
                }
            }
        case .code(let s):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(s).font(.system(size: CGFloat(size) * 0.85, design: .monospaced))
            }
            .padding(8)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        case .quote(let s):
            rich((s))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.tertiary).frame(width: 3) }
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { ForEach(Array(header.enumerated()), id: \.offset) { rich(($0.element)).bold() } }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { rich(($0.element)) } }
                    }
                }
            }
        case .math(let latex):
            DisplayMath(latex: latex, size: CGFloat(size))
        case .rule:
            Divider()
        }
    }

    private func rich(_ s: String) -> Text { RichText.make(s, size: CGFloat(size)) }
}

struct ListItem { let indent: Int; let marker: String; let text: String }

enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case list([ListItem])
    case code(String)
    case quote(String)
    case table([String], [[String]])
    case math(String)
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var para: [String] = []
        var i = 0

        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.isEmpty { flush(); i += 1; continue }

            if t.hasPrefix("```") {
                flush()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1
                continue
            }

            // Display math: $$ … $$ or \[ … \], single- or multi-line
            if t.hasPrefix("$$") || t.hasPrefix("\\[") {
                let close = t.hasPrefix("$$") ? "$$" : "\\]"
                var body = String(t.dropFirst(2))
                if let r = body.range(of: close) {
                    body = String(body[..<r.lowerBound])
                    i += 1
                } else {
                    i += 1
                    var parts = [body]
                    while i < lines.count {
                        let l = lines[i]; i += 1
                        if let r = l.range(of: close) { parts.append(String(l[..<r.lowerBound])); break }
                        parts.append(l)
                    }
                    body = parts.joined(separator: "\n")
                }
                flush()
                blocks.append(.math(body.trimmingCharacters(in: .whitespacesAndNewlines)))
                continue
            }

            if let h = heading(t) { flush(); blocks.append(h); i += 1; continue }

            if t.count >= 3, Set(t.replacingOccurrences(of: " ", with: "")).count == 1, "-*_".contains(t.first!) {
                flush(); blocks.append(.rule); i += 1; continue
            }

            if t.hasPrefix(">") {
                flush()
                var q: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    q.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(q.joined(separator: "\n")))
                continue
            }

            if t.hasPrefix("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flush()
                let header = cells(t)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    var r = cells(lines[i])
                    r += Array(repeating: "", count: max(0, header.count - r.count))
                    rows.append(Array(r.prefix(header.count)))
                    i += 1
                }
                blocks.append(.table(header, rows))
                continue
            }

            if listItem(line) != nil {
                flush()
                var items: [ListItem] = []
                while i < lines.count {
                    if let item = listItem(lines[i]) {
                        items.append(item)
                    } else if !lines[i].trimmingCharacters(in: .whitespaces).isEmpty,
                              lines[i].hasPrefix("  "), let last = items.popLast() {
                        // continuation line of previous item
                        items.append(ListItem(indent: last.indent, marker: last.marker,
                                              text: last.text + " " + lines[i].trimmingCharacters(in: .whitespaces)))
                    } else { break }
                    i += 1
                }
                blocks.append(.list(items))
                continue
            }

            para.append(t)
            i += 1
        }
        flush()
        return blocks
    }

    private static func heading(_ t: String) -> MarkdownBlock? {
        let hashes = t.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { return nil }
        return .heading(hashes, String(t.dropFirst(hashes + 1)))
    }

    private static func listItem(_ line: String) -> ListItem? {
        let indent = line.prefix(while: { $0 == " " }).count / 2
        let t = line.trimmingCharacters(in: .whitespaces)
        for b in ["- ", "* ", "+ "] where t.hasPrefix(b) {
            return ListItem(indent: indent, marker: indent == 0 ? "•" : "◦", text: String(t.dropFirst(2)))
        }
        let digits = t.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count <= 3 {
            let rest = t.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return ListItem(indent: indent, marker: "\(digits).", text: String(rest.dropFirst(2)))
            }
        }
        return nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("|") && t.contains("-") && t.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
