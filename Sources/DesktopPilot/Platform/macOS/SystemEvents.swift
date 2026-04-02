import Foundation

// MARK: - System Events Error

/// Errors from AppleScript/System Events execution.
enum SystemEventsError: Error, LocalizedError, Sendable {
    case scriptFailed(String)
    case appNotFound(String)
    case elementNotFound(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let msg):
            return "AppleScript error: \(msg)"
        case .appNotFound(let name):
            return "App not found: \(name)"
        case .elementNotFound(let desc):
            return "Element not found: \(desc)"
        }
    }
}

// MARK: - System Events Helper

/// Helper for executing AppleScript/JXA and System Events commands.
///
/// System Events is the universal UI automation bridge -- it works
/// with ANY app, not just scriptable ones. This helper wraps common
/// operations: running scripts, clicking elements, typing text,
/// pressing keys, and inspecting UI trees.
struct SystemEventsHelper: Sendable {

    // MARK: - Script Execution

    /// Execute AppleScript code and return the result.
    func runAppleScript(_ code: String) -> Result<String, Error> {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", code]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()

            // Read pipes before waiting to avoid deadlock on large output
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: outData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorOutput = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                return .success(output)
            } else {
                return .failure(SystemEventsError.scriptFailed(errorOutput))
            }
        } catch {
            return .failure(error)
        }
    }

    /// Execute JXA (JavaScript for Automation) code.
    func runJXA(_ code: String) -> Result<String, Error> {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", code]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()

            // Read pipes before waiting to avoid deadlock on large output
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: outData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorOutput = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                return .success(output)
            } else {
                return .failure(SystemEventsError.scriptFailed(errorOutput))
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Scriptability Detection

    /// Check if an app has an AppleScript dictionary (is natively scriptable).
    ///
    /// Uses `sdef` to probe for a scripting definition file. Apps with an sdef
    /// support direct `tell application` commands beyond System Events.
    func isScriptable(appName: String) -> Bool {
        guard let appPath = findAppPath(appName) else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sdef")
        process.arguments = [appPath]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Find the filesystem path to an app by its display name.
    ///
    /// Uses Spotlight (`mdfind`) to locate the .app bundle.
    func findAppPath(_ appName: String) -> String? {
        let process = Process()
        let pipe = Pipe()

        let sanitizedName = appName.replacingOccurrences(of: "'", with: "'\\''")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [
            "kMDItemDisplayName == '\(sanitizedName)' && kMDItemContentType == 'com.apple.application-bundle'"
        ]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output.components(separatedBy: "\n").first(where: { !$0.isEmpty })
        } catch {
            return nil
        }
    }

    // MARK: - System Events UI Actions

    /// Click a UI element via System Events using its description/path.
    ///
    /// - Parameters:
    ///   - appName: The process name of the target application.
    ///   - elementDescription: AppleScript element reference, e.g.
    ///     `button "OK" of window 1`.
    func clickElement(
        appName: String,
        elementDescription: String
    ) -> Result<String, Error> {
        let script = """
            tell application "System Events"
                tell process "\(escapeForAppleScript(appName))"
                    click \(elementDescription)
                end tell
            end tell
            """
        return runAppleScript(script)
    }

    /// Get the UI element tree for an app via System Events.
    ///
    /// Returns a text listing of every window and its contents
    /// (class, name, description) suitable for LLM consumption.
    func getUIElements(appName: String) -> Result<String, Error> {
        let escaped = escapeForAppleScript(appName)
        let script = """
            tell application "System Events"
                tell process "\(escaped)"
                    set windowList to every window
                    set resultText to ""
                    repeat with w in windowList
                        set resultText to resultText & "Window: " & (name of w) & linefeed
                        try
                            set uiElements to entire contents of w
                            repeat with elem in uiElements
                                set elemClass to class of elem as text
                                set elemName to ""
                                try
                                    set elemName to name of elem
                                end try
                                set elemDesc to ""
                                try
                                    set elemDesc to description of elem
                                end try
                                set resultText to resultText & "  " & elemClass & ": " & elemName & " (" & elemDesc & ")" & linefeed
                            end repeat
                        end try
                    end repeat
                    return resultText
                end tell
            end tell
            """
        return runAppleScript(script)
    }

    /// Type text into the focused field of an app via System Events.
    ///
    /// Uses `keystroke` which simulates actual key presses, making it
    /// more reliable than `AXSetValue` for some apps (e.g. Electron apps).
    func typeText(
        appName: String,
        text: String
    ) -> Result<String, Error> {
        let escaped = escapeForAppleScript(text)
        let script = """
            tell application "System Events"
                tell process "\(escapeForAppleScript(appName))"
                    keystroke "\(escaped)"
                end tell
            end tell
            """
        return runAppleScript(script)
    }

    /// Press a keyboard shortcut via System Events.
    ///
    /// - Parameters:
    ///   - appName: The process name of the target application.
    ///   - key: The key code (numeric) or key character to press.
    ///   - modifiers: Modifier names, e.g. `["command down", "shift down"]`.
    func keyPress(
        appName: String,
        key: String,
        modifiers: [String]
    ) -> Result<String, Error> {
        let modifierStr = modifiers.isEmpty
            ? ""
            : " using {\(modifiers.joined(separator: ", "))}"
        let script = """
            tell application "System Events"
                tell process "\(escapeForAppleScript(appName))"
                    key code \(key)\(modifierStr)
                end tell
            end tell
            """
        return runAppleScript(script)
    }

    /// Press a keystroke with modifiers (character-based, not key code).
    ///
    /// Use this for shortcuts like Cmd+C, Cmd+V where you know the character.
    func keystrokeWithModifiers(
        appName: String,
        character: String,
        modifiers: [String]
    ) -> Result<String, Error> {
        let modifierStr = modifiers.isEmpty
            ? ""
            : " using {\(modifiers.joined(separator: ", "))}"
        let script = """
            tell application "System Events"
                tell process "\(escapeForAppleScript(appName))"
                    keystroke "\(escapeForAppleScript(character))"\(modifierStr)
                end tell
            end tell
            """
        return runAppleScript(script)
    }

    // MARK: - App Queries

    /// Check if an app process is currently running via System Events.
    func isRunning(appName: String) -> Bool {
        let script = """
            tell application "System Events"
                return (name of every process) contains "\(escapeForAppleScript(appName))"
            end tell
            """
        switch runAppleScript(script) {
        case .success(let result):
            return result.lowercased() == "true"
        case .failure:
            return false
        }
    }

    /// Get the frontmost status of an app via System Events.
    func isFrontmost(appName: String) -> Bool {
        let script = """
            tell application "System Events"
                tell process "\(escapeForAppleScript(appName))"
                    return frontmost
                end tell
            end tell
            """
        switch runAppleScript(script) {
        case .success(let result):
            return result.lowercased() == "true"
        case .failure:
            return false
        }
    }

    /// Bring an app to the front via System Events.
    func activate(appName: String) -> Result<String, Error> {
        let script = """
            tell application "System Events"
                set frontmost of process "\(escapeForAppleScript(appName))" to true
            end tell
            """
        return runAppleScript(script)
    }

    // MARK: - Private Helpers

    /// Escape special characters for safe embedding in AppleScript strings.
    private func escapeForAppleScript(_ input: String) -> String {
        return input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
