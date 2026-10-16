import SwiftUI

struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.sizeKey) private var fontSize = Prefs.defaultSize
    @AppStorage(Prefs.layoutKey) private var layout = PanelLayout.portrait
    @ViewState private var input = ""
    @ViewState private var scrolled = false
    // Edge-based scrolling works even when the LazyVStack's tail isn't laid out yet (id-based scrollTo doesn't).
    @ViewState private var position = ScrollPosition(edge: .bottom)
    @FocusState private var focused: Bool
    @ViewState private var visible = false

    var body: some View {
        Group {
            if let doc = store.document {
                conversation(doc)
            } else {
                noDocument
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelBackground() }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .background { settingsShortcut }
        .background { WindowVisibility(visible: $visible) }
        .environment(\.panelVisible, visible)
        .onAppear { store.poll(); focused = true }
    }

    // MARK: Conversation

    private func conversation(_ doc: PDFInfo) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if store.messages.isEmpty {
                    suggestions.padding(.top, 36)
                }
                ForEach(store.messages) { msg in
                    MessageRow(message: msg, isStreaming: store.busy && msg.id == store.messages.last?.id,
                               status: store.status)
                        .id(msg.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, v in
            scrolled = v
        }
        .safeAreaInset(edge: .top, spacing: 0) { header(doc) }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .onChange(of: store.messages.last?.text) { position.scrollTo(edge: .bottom) }
        .onChange(of: store.messages.count) {
            withAnimation(.smooth) { position.scrollTo(edge: .bottom) }
        }
    }

    private func header(_ doc: PDFInfo) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: doc.url.path))
                    .resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(doc.url.deletingPathExtension().lastPathComponent)
                        .font(.system(.body, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(doc.truncated ? "\(doc.pageCount) pages · large document" : "\(doc.pageCount) pages")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                modelMenu
                Button { withAnimation(.smooth) { store.newChat() } } label: {
                    Image(systemName: "square.and.pencil").frame(width: 18, height: 18)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .help("New Chat (⌘N)").keyboardShortcut("n").disabled(store.busy || store.messages.isEmpty)
                moreMenu(doc)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background { PanelBackground() }
        .overlay(alignment: .bottom) { Divider().opacity(scrolled ? 1 : 0) }
        .animation(.easeOut(duration: 0.15), value: scrolled)
    }

    private var modelMenu: some View {
        Menu {
            Picker("Model", selection: $store.model) {
                Label("Haiku", systemImage: "hare").tag("haiku")
                Label("Sonnet", systemImage: "sparkles").tag("sonnet")
                Label("Opus", systemImage: "brain").tag("opus")
            }
            .pickerStyle(.inline)
        } label: {
            Text(store.model.capitalized).font(.callout.weight(.medium))
        }
        .menuStyle(.button).buttonStyle(.glass).buttonBorderShape(.capsule)
        .menuIndicator(.visible).fixedSize()
        .help("Model")
    }

    private func moreMenu(_ doc: PDFInfo) -> some View {
        Menu {
            Picker("Panel Shape", selection: $layout) {
                ForEach(PanelLayout.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Settings…", systemImage: "gearshape") { showSettings() }
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([doc.url]) }
            Divider()
            Button("Quit PreviewChat", systemImage: "power") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis").frame(width: 18, height: 18)
        }
        .menuStyle(.button).buttonStyle(.glass).buttonBorderShape(.circle)
        .menuIndicator(.hidden).fixedSize()
    }

    /// ⌘, from the panel. Accessory apps have no visible menu bar, so wire it up explicitly.
    private var settingsShortcut: some View {
        Button("Settings", action: showSettings)
            .keyboardShortcut(",", modifiers: .command)
            .opacity(0).allowsHitTesting(false)
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }

    // MARK: Empty states

    private static let prompts: [(icon: String, title: String, prompt: String)] = [
        ("text.alignleft", "Summarize", "Summarize this document concisely."),
        ("list.star", "Key takeaways", "What are the key takeaways? Use a short bulleted list."),
        ("graduationcap", "Explain simply", "Explain the main ideas simply, as if I'm new to the topic."),
        ("questionmark.bubble", "Quiz me", "Ask me 5 questions to test my understanding of this document, one at a time."),
    ]

    private var suggestions: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30)).foregroundStyle(.tint)
                    .symbolEffect(.breathe, options: .repeat(.continuous), isActive: visible)
                Text("Ask about this PDF").font(.title3.weight(.semibold))
                Text("Claude has read every page.").font(.callout).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Self.prompts, id: \.title) { p in
                    Button { store.send(p.prompt) } label: {
                        Label(p.title, systemImage: p.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass).controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var noDocument: some View {
        ContentUnavailableView {
            Label("No PDF Open", systemImage: "doc.text.magnifyingglass")
        } description: {
            if let err = store.watcherError {
                Text("PreviewChat can't talk to Preview (\(err)). Allow it in System Settings → Privacy & Security → Automation.")
            } else {
                Text("Open a PDF in Preview and it'll appear here, ready to chat.")
            }
        } actions: {
            if store.watcherError != nil {
                Button("Open Automation Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Quit", systemImage: "power") { NSApp.terminate(nil) }
                .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                .padding(12)
        }
    }

    // MARK: Composer

    private var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.busy }

    private var composer: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask anything…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onKeyPress(.return, phases: .down) { press in
                        // Field editor maps Shift+Return to submit; insert newline at cursor instead.
                        if press.modifiers.contains(.shift) {
                            NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                        } else {
                            submit()
                        }
                        return .handled
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

                Group {
                    if store.busy {
                        Button { store.cancel() } label: {
                            Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold))
                                .frame(width: 20, height: 20)
                        }
                        .help("Stop")
                    } else {
                        Button(action: submit) {
                            Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                                .frame(width: 20, height: 20)
                        }
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(!canSend)
                    }
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.circle).controlSize(.large)
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .animation(.smooth(duration: 0.2), value: store.busy)
    }

    private func submit() {
        guard canSend else { return }
        store.send(input)
        input = ""
    }
}

// MARK: - Messages

struct MessageRow: View {
    let message: Message
    @AppStorage(Prefs.sizeKey) private var fontSize = Prefs.defaultSize
    var isStreaming = false
    var status: String?
    @ViewState private var hovering = false
    @ViewState private var copied = false

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: assistant
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 56)
            Text(message.text)
                .font(.system(size: fontSize))
                .textSelection(.enabled)
                .foregroundStyle(.white)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(Color.accentColor.gradient, in: .rect(cornerRadius: 18, style: .continuous))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.isError {
                errorView
            } else if message.text.isEmpty {
                ThinkingIndicator(label: status ?? "Thinking")
            } else {
                MarkdownView(text: message.text)
                    .textSelection(.enabled)
                if isStreaming, let status {
                    ThinkingIndicator(label: status)
                }
            }
            if !isStreaming && !message.text.isEmpty && !message.isError {
                copyButton.opacity(hovering ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }

    private var errorView: some View {
        Label {
            Text(message.text).textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

struct ThinkingIndicator: View {
    let label: String
    @Environment(\.panelVisible) private var visible

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .foregroundStyle(.tint)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: visible)
            let text = Text(label.trimmingCharacters(in: CharacterSet(charactersIn: "…")))
                .foregroundStyle(.secondary)
            if visible {
                text.phaseAnimator([0.4, 1.0]) { content, phase in
                    content.opacity(phase)
                } animation: { _ in .easeInOut(duration: 0.8) }
            } else {
                text
            }
        }
        .font(.callout)
    }
}

/// `@State` is a macro in the macOS 27 SDK whose plugin ships only with Xcode; this alias
/// names the same property wrapper so the app also builds with the Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

private struct PanelVisibleKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// False while the menu bar panel is closed, so continuous animations stop redrawing it.
    var panelVisible: Bool {
        get { self[PanelVisibleKey.self] }
        set { self[PanelVisibleKey.self] = newValue }
    }
}

/// Tracks whether the hosting window is on screen. MenuBarExtra only orders its window out
/// when closed, so SwiftUI would otherwise keep running repeating animations forever.
struct WindowVisibility: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> NSView { Tracker { visible = $0 } }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Tracker: NSView {
        let onChange: (Bool) -> Void
        private var observer: NSObjectProtocol?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return onChange(false) }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.report() }
            report()
        }

        private func report() {
            let v = window?.occlusionState.contains(.visible) ?? false
            DispatchQueue.main.async { self.onChange(v) }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

/// The panel's dark frosted backdrop. Also used under the header so it matches the body
/// and hides (rather than shows through) content scrolled beneath it.
struct PanelBackground: View {
    var body: some View {
        VisualEffectBackground().overlay(Color.black.opacity(0.4))
    }
}

/// Behind-window blur (dark HUD material), like other menu bar panels.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
