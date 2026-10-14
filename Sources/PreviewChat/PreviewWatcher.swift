import AppKit

/// Asks Preview (via AppleScript) for the path of its frontmost document.
enum PreviewWatcher {
    static let bundleID = "com.apple.Preview"

    private static let script = NSAppleScript(source: """
        tell application id "com.apple.Preview"
            if (count of windows) is 0 then return ""
            try
                return path of document of front window
            on error
                try
                    return path of front document
                on error
                    return ""
                end try
            end try
        end tell
        """)!

    /// Returns nil if Preview isn't running or has no PDF open. Must run on main thread.
    static func frontPDF() -> URL? {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty == false else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err { lastError = err[NSAppleScript.errorMessage] as? String; return nil }
        lastError = nil
        guard let path = result.stringValue, !path.isEmpty, path.lowercased().hasSuffix(".pdf") else { return nil }
        return URL(fileURLWithPath: path)
    }

    static var lastError: String?
}
