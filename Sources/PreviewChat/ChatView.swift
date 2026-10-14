import SwiftUI

struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.document == nil {
                emptyState
            } else {
                messageList
                Divider()
                inputBar
            }
        }
        .onAppear { store.poll(); focused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.document?.url.lastPathComponent ?? "No PDF open")
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                if let d = store.document {
                    Text("\(d.pageCount) pages\(d.truncated ? " · large, partially inlined" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("", selection: $store.model) {
                Text("Haiku").tag("haiku")
                Text("Sonnet").tag("sonnet")
                Text("Opus").tag("opus")
            }
            .labelsHidden().fixedSize()
            Button { store.newChat() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless).help("New chat").disabled(store.busy)
            Menu {
                Button("Quit PreviewChat") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.viewfinder").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Open a PDF in Preview to start chatting.").foregroundStyle(.secondary)
            if let err = store.watcherError {
                Text("Can't talk to Preview: \(err)\nAllow it in System Settings → Privacy & Security → Automation.")
                    .font(.caption).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.messages.isEmpty {
                        Text("Ask anything about this document.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(store.messages) { MessageRow(message: $0) }
                    if let s = store.status {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(s).font(.caption) }
                            .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
            }
            .onChange(of: store.messages.last?.text) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: store.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(submit)
            if store.busy {
                Button { store.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                    .buttonStyle(.borderless).help("Stop")
            } else {
                Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(10)
    }

    private func submit() {
        guard !store.busy else { return }
        store.send(input)
        input = ""
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(rendered)
                .textSelection(.enabled)
                .padding(8)
                .background(background, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(message.isError ? .red : .primary)
            if message.role == .assistant { Spacer(minLength: 20) }
        }
    }

    private var background: Color {
        message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1)
    }

    private var rendered: AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: opts)) ?? AttributedString(message.text)
    }
}
