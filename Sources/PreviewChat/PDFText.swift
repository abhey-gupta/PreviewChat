import PDFKit

struct PDFInfo {
    let url: URL
    let pageCount: Int
    let text: String          // page-tagged extracted text
    let truncated: Bool
}

enum PDFText {
    /// ~150k tokens worth of text; beyond that Claude falls back to reading pages itself.
    static let maxChars = 600_000

    static func load(_ url: URL) -> PDFInfo? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var out = ""
        var truncated = false
        for i in 0..<doc.pageCount {
            let page = doc.page(at: i)?.string ?? ""
            let chunk = "\n--- page \(i + 1) ---\n" + page
            if out.count + chunk.count > maxChars { truncated = true; break }
            out += chunk
        }
        return PDFInfo(url: url, pageCount: doc.pageCount, text: out, truncated: truncated)
    }
}
