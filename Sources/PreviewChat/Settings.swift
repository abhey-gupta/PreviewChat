import SwiftUI

enum ResponseFont: String, CaseIterable, Identifiable {
    case sourceSerif, newYork, sfPro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sourceSerif: "Source Serif (Claude-style)"
        case .newYork: "New York"
        case .sfPro: "SF Pro"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .sourceSerif: .custom("Source Serif 4", size: size)
        case .newYork: .system(size: size, design: .serif)
        case .sfPro: .system(size: size)
        }
    }
}

enum Prefs {
    static let fontKey = "responseFont"
    static let sizeKey = "fontSize"
    static let defaultSize: Double = 15
}

struct SettingsView: View {
    @AppStorage(Prefs.fontKey) private var font = ResponseFont.sourceSerif
    @AppStorage(Prefs.sizeKey) private var size = Prefs.defaultSize

    var body: some View {
        Form {
            Section("Text") {
                Picker("Response font", selection: $font) {
                    ForEach(ResponseFont.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Text size") {
                    HStack(spacing: 10) {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                        Slider(value: $size, in: 11...22, step: 1).frame(width: 160)
                        Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                        Text("\(Int(size)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    }
                }
                if size != Prefs.defaultSize {
                    Button("Reset to Default") { size = Prefs.defaultSize }
                }
            }
            Section("Preview") {
                MarkdownView(text: "## Linear discriminant analysis\nAssign **x** to the group with the *largest* score fᵢ (p. 5).")
                    .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
