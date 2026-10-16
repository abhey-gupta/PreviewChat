import SwiftUI

struct Message: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var isError = false
}

struct Conversation {
    var messages: [Message] = []
    var sessionID: String?
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var document: PDFInfo?
    @Published private(set) var conversations: [URL: Conversation] = [:]
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    @Published private(set) var watcherError: String?
    @AppStorage("model") var model = "sonnet"

    private var runner: ClaudeRunner?
    private var timer: Timer?

    var messages: [Message] { document.flatMap { conversations[$0.url]?.messages } ?? [] }

    init() {
        _ = ClaudeRunner.shellEnv // resolve early, off the first send
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func poll() {
        let url = PreviewWatcher.frontPDF()
        // Assign only on change: every @Published write re-renders the panel.
        if watcherError != PreviewWatcher.lastError { watcherError = PreviewWatcher.lastError }
        guard let url, url != document?.url else { return }
        Task.detached(priority: .userInitiated) {
            guard let info = PDFText.load(url) else { return }
            await MainActor.run { self.document = info }
        }
    }

    func newChat() {
        guard let doc = document, !busy else { return }
        conversations[doc.url] = nil
    }

    func cancel() { runner?.cancel() }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let doc = document, !text.isEmpty, !busy else { return }
        let key = doc.url
        var convo = conversations[key] ?? Conversation()

        var prompt = text
        if convo.sessionID == nil {
            let note = doc.truncated ? " truncated=\"true\" (text cut off; use Read for later pages)" : ""
            let body = doc.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "(no extractable text — likely scanned; use the Read tool)" : doc.text
            prompt = """
                <document path="\(doc.url.path)" pages="\(doc.pageCount)"\(note)>
                \(body)
                </document>

                \(text)
                """
        }

        convo.messages.append(Message(role: .user, text: text))
        convo.messages.append(Message(role: .assistant, text: ""))
        conversations[key] = convo
        busy = true
        status = "Thinking…"

        let r = ClaudeRunner()
        runner = r
        r.send(prompt: prompt, pdf: key, sessionID: convo.sessionID, model: model) { [weak self] event in
            self?.apply(event, to: key)
        }
    }

    private func apply(_ event: ClaudeRunner.Event, to key: URL) {
        guard var convo = conversations[key] else { return }
        let last = convo.messages.count - 1
        switch event {
        case .session(let id):
            convo.sessionID = id
        case .text(let t):
            convo.messages[last].text += t
            status = nil
        case .status(let s):
            status = s
        case .done(let error):
            if let error {
                convo.messages[last].text += (convo.messages[last].text.isEmpty ? "" : "\n\n") + error
                convo.messages[last].isError = true
                // A failed first turn leaves a useless session; start fresh next time.
                if convo.messages.count <= 2 { convo.sessionID = nil }
            }
            busy = false
            status = nil
            runner = nil
        }
        conversations[key] = convo
    }
}
