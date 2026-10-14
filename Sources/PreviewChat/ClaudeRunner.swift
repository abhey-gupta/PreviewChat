import Foundation

/// Runs one turn of `claude -p` (subscription auth, no API key) and streams events back.
final class ClaudeRunner {
    enum Event {
        case session(String)
        case text(String)
        case status(String)
        case done(error: String?)
    }

    private var process: Process?

    /// Environment of the user's interactive login shell. GUI apps don't source ~/.zshrc, which is
    /// where nvm (PATH to `claude`) and CLAUDE_CODE_OAUTH_TOKEN (subscription auth) are set up.
    static let shellEnv: [String: String] = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "printf __ENV__; env -0; printf __ENV__"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try? p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self)
        guard let r = s.range(of: "__ENV__"), let e = s.range(of: "__ENV__", options: .backwards),
              r.upperBound <= e.lowerBound else {
            return ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(NSHomeDirectory())/.local/bin"]
        }
        var env: [String: String] = [:]
        for entry in s[r.upperBound..<e.lowerBound].split(separator: "\0") {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return env
    }()

    static let workDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PreviewChat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let systemPrompt = """
        You are a PDF reading assistant inside a macOS menu bar app. The user has a PDF open in Preview. \
        Its extracted text is given in <document> tags in the first message. Answer questions about it concisely, \
        cite page numbers like (p. 4) when useful, and use Markdown. If the extracted text is missing, truncated, \
        or a question concerns figures/tables/scans, use the Read tool on the PDF path (with the pages parameter for large files).
        """

    func send(prompt: String, pdf: URL, sessionID: String?, model: String, onEvent: @escaping (Event) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = ["claude", "-p",
                    "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                    "--tools", "Read", "--allowedTools", "Read",
                    "--add-dir", pdf.deletingLastPathComponent().path,
                    "--append-system-prompt", Self.systemPrompt,
                    "--disable-slash-commands", "--strict-mcp-config"]
        if !model.isEmpty { args += ["--model", model] }
        if let sessionID { args += ["--resume", sessionID] }
        p.arguments = args
        p.currentDirectoryURL = Self.workDir

        var env = ProcessInfo.processInfo.environment.merging(Self.shellEnv) { _, shell in shell }
        // Force subscription (OAuth) auth instead of per-token API billing.
        for k in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"] { env[k] = nil }
        p.environment = env

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        var buffer = Data()
        var sawText = false
        var finalError: String?
        var finalResult: String?
        let emit: (Event) -> Void = { e in DispatchQueue.main.async { onEvent(e) } }

        func handle(line: Data) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = obj["type"] as? String else { return }
            switch type {
            case "system":
                if obj["subtype"] as? String == "init", let sid = obj["session_id"] as? String { emit(.session(sid)) }
            case "stream_event":
                guard let ev = obj["event"] as? [String: Any] else { return }
                if ev["type"] as? String == "content_block_start",
                   let block = ev["content_block"] as? [String: Any], block["type"] as? String == "text", sawText {
                    emit(.text("\n\n"))
                }
                if ev["type"] as? String == "content_block_delta",
                   let d = ev["delta"] as? [String: Any], d["type"] as? String == "text_delta",
                   let t = d["text"] as? String {
                    sawText = true
                    emit(.text(t))
                }
            case "assistant":
                if let msg = obj["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] {
                    for c in content where c["type"] as? String == "tool_use" {
                        let input = c["input"] as? [String: Any]
                        let pages = (input?["pages"] as? String).map { " pages \($0)" } ?? ""
                        emit(.status("Reading PDF\(pages)…"))
                    }
                }
            case "result":
                if obj["is_error"] as? Bool == true {
                    finalError = (obj["result"] as? String) ?? (obj["subtype"] as? String) ?? "Unknown error"
                } else {
                    finalResult = obj["result"] as? String
                }
            default: break
            }
        }

        // Serializes parsing between the readability and termination handlers.
        let q = DispatchQueue(label: "PreviewChat.claude-output")

        stdout.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { return }
            q.sync {
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<nl)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    handle(line: line)
                }
            }
        }

        p.terminationHandler = { proc in q.sync {
            stdout.fileHandleForReading.readabilityHandler = nil
            buffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
            for line in buffer.split(separator: 0x0A) { handle(line: Data(line)) }
            buffer.removeAll()
            if !sawText, finalError == nil, let r = finalResult, !r.isEmpty { emit(.text(r)) }
            var err = finalError
            if err == nil, proc.terminationStatus != 0, proc.terminationReason != .uncaughtSignal {
                let se = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                err = se.isEmpty ? "claude exited with status \(proc.terminationStatus)" : se
            }
            emit(.done(error: err))
        } }

        do {
            try p.run()
        } catch {
            emit(.done(error: "Couldn't launch claude: \(error.localizedDescription)"))
            return
        }
        process = p
        DispatchQueue.global().async {
            stdin.fileHandleForWriting.write(prompt.data(using: .utf8)!)
            try? stdin.fileHandleForWriting.close()
        }
    }

    func cancel() { process?.terminate() }
}
