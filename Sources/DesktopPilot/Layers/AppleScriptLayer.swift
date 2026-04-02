import Foundation

// MARK: - AppleScript Layer

/// Interaction layer using AppleScript + System Events.
///
/// This is the **second priority** layer (priority 20) -- preferred over raw
/// accessibility (priority 0 = most available but least smart) for scriptable
/// apps. The Router tries layers in ascending priority order, so lower
/// priority = tried first. Since AccessibilityLayer has priority 0 it is
/// the fallback; AppleScriptLayer at 20 is offered as an alternative when
/// the app is natively scriptable.
///
/// Design decisions:
/// - **Snapshot**: Uses System Events `entire contents` to enumerate UI
///   elements. Produces `PilotElement` nodes with synthetic refs prefixed
///   "as" (e.g. "as1", "as2") so they don't collide with accessibility refs.
/// - **Click**: Uses System Events `click` on the element description stored
///   during the last snapshot.
/// - **Type**: Uses System Events `keystroke`, which simulates real key
///   presses and is more reliable than AXSetValue for Electron apps, web
///   views, and other non-native text fields.
/// - **Read**: Uses System Events to query element properties.
///
/// This layer does NOT use the shared `ElementStore` actor -- it maintains
/// its own lock-based cache of element descriptions for synchronous access.
final class AppleScriptLayer: @unchecked Sendable, InteractionLayer {

    let name: String = "AppleScript"
    let priority: Int = 20

    private let sysEvents: SystemEventsHelper
    private let elementCache: ASElementCache

    init(systemEvents: SystemEventsHelper = SystemEventsHelper()) {
        self.sysEvents = systemEvents
        self.elementCache = ASElementCache()
    }

    // MARK: - InteractionLayer Conformance

    func canHandle(bundleID: String?, appName: String) -> Bool {
        // System Events works with any running app, but we only claim
        // to handle apps that have a real AppleScript dictionary.
        // For apps without sdef, the Accessibility layer is better.
        return sysEvents.isScriptable(appName: appName)
    }

    func snapshot(pid: Int32, maxDepth: Int) throws -> [PilotElement] {
        let appName = try resolveAppName(pid: pid)
        elementCache.clear()

        let result = sysEvents.getUIElements(appName: appName)

        switch result {
        case .success(let output):
            return parseUIElementOutput(output, appName: appName)
        case .failure(let error):
            throw LayerError.snapshotFailed(
                pid: pid,
                reason: "System Events snapshot failed: \(error.localizedDescription)"
            )
        }
    }

    func click(ref: String) throws {
        guard let entry = elementCache.lookup(ref) else {
            throw PlatformError.elementNotFound(ref: ref)
        }

        let result = sysEvents.clickElement(
            appName: entry.appName,
            elementDescription: entry.elementPath
        )

        switch result {
        case .success:
            return
        case .failure(let error):
            throw PlatformError.actionFailed(
                action: "click",
                reason: "System Events click failed for ref '\(ref)': \(error.localizedDescription)"
            )
        }
    }

    func typeText(ref: String, text: String) throws {
        guard let entry = elementCache.lookup(ref) else {
            throw PlatformError.elementNotFound(ref: ref)
        }

        // First try to click the element to focus it
        _ = sysEvents.clickElement(
            appName: entry.appName,
            elementDescription: entry.elementPath
        )

        // Then type via keystroke
        let result = sysEvents.typeText(
            appName: entry.appName,
            text: text
        )

        switch result {
        case .success:
            return
        case .failure(let error):
            throw LayerError.typingFailed(
                ref: ref,
                reason: "System Events keystroke failed: \(error.localizedDescription)"
            )
        }
    }

    func readValue(ref: String) throws -> String? {
        guard let entry = elementCache.lookup(ref) else {
            throw PlatformError.elementNotFound(ref: ref)
        }

        let script = """
            tell application "System Events"
                tell process "\(escapeForAppleScript(entry.appName))"
                    try
                        set elemVal to value of \(entry.elementPath)
                        return elemVal as text
                    on error
                        try
                            set elemTitle to name of \(entry.elementPath)
                            return elemTitle as text
                        on error
                            return ""
                        end try
                    end try
                end tell
            end tell
            """

        let result = sysEvents.runAppleScript(script)

        switch result {
        case .success(let output):
            return output.isEmpty ? nil : output
        case .failure:
            throw LayerError.readFailed(
                ref: ref,
                reason: "Could not read value for element via System Events"
            )
        }
    }

    // MARK: - Private Helpers

    /// Resolve a PID to an app process name for System Events.
    private func resolveAppName(pid: Int32) throws -> String {
        let script = """
            tell application "System Events"
                set targetProcess to first process whose unix id is \(pid)
                return name of targetProcess
            end tell
            """
        let result = sysEvents.runAppleScript(script)

        switch result {
        case .success(let name):
            if name.isEmpty {
                throw LayerError.snapshotFailed(
                    pid: pid,
                    reason: "System Events returned empty process name for PID \(pid)"
                )
            }
            return name
        case .failure(let error):
            throw LayerError.snapshotFailed(
                pid: pid,
                reason: "Could not resolve PID \(pid) via System Events: \(error.localizedDescription)"
            )
        }
    }

    /// Parse the text output from `getUIElements` into `PilotElement` nodes.
    ///
    /// The output format is:
    /// ```
    /// Window: My Window
    ///   button: OK (press)
    ///   text field:  (input)
    /// ```
    private func parseUIElementOutput(
        _ output: String,
        appName: String
    ) -> [PilotElement] {
        let lines = output.components(separatedBy: .newlines)
        var windows: [PilotElement] = []
        var currentWindowChildren: [PilotElement] = []
        var currentWindowName: String?
        var windowIndex = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("Window: ") {
                // Save previous window if any
                if let windowName = currentWindowName {
                    let windowRef = elementCache.register(
                        appName: appName,
                        elementPath: "window \"\(escapeForAppleScript(windowName))\"",
                        role: "AXWindow",
                        displayName: windowName
                    )
                    windows.append(PilotElement(
                        ref: windowRef,
                        role: "AXWindow",
                        title: windowName,
                        value: nil,
                        description: nil,
                        enabled: true,
                        focused: false,
                        bounds: nil,
                        children: currentWindowChildren.isEmpty ? nil : currentWindowChildren
                    ))
                }

                currentWindowName = String(trimmed.dropFirst("Window: ".count))
                currentWindowChildren = []
                windowIndex += 1
            } else {
                // Parse element line: "  className: name (description)"
                let parsed = parseElementLine(
                    trimmed,
                    appName: appName,
                    windowIndex: windowIndex
                )
                if let element = parsed {
                    currentWindowChildren.append(element)
                }
            }
        }

        // Save last window
        if let windowName = currentWindowName {
            let windowRef = elementCache.register(
                appName: appName,
                elementPath: "window \"\(escapeForAppleScript(windowName))\"",
                role: "AXWindow",
                displayName: windowName
            )
            windows.append(PilotElement(
                ref: windowRef,
                role: "AXWindow",
                title: windowName,
                value: nil,
                description: nil,
                enabled: true,
                focused: false,
                bounds: nil,
                children: currentWindowChildren.isEmpty ? nil : currentWindowChildren
            ))
        }

        return windows
    }

    /// Parse a single element line from the System Events output.
    private func parseElementLine(
        _ line: String,
        appName: String,
        windowIndex: Int
    ) -> PilotElement? {
        // Expected format: "className: name (description)"
        let colonIndex = line.firstIndex(of: ":")
        guard let colonIdx = colonIndex else { return nil }

        let rawClass = String(line[line.startIndex..<colonIdx])
            .trimmingCharacters(in: .whitespaces)
        let remainder = String(line[line.index(after: colonIdx)...])
            .trimmingCharacters(in: .whitespaces)

        // Extract name and description from "name (description)"
        var elementName: String? = nil
        var elementDesc: String? = nil

        if let parenStart = remainder.lastIndex(of: "("),
           let parenEnd = remainder.lastIndex(of: ")"),
           parenStart < parenEnd {
            elementName = String(remainder[remainder.startIndex..<parenStart])
                .trimmingCharacters(in: .whitespaces)
            elementDesc = String(remainder[remainder.index(after: parenStart)..<parenEnd])
                .trimmingCharacters(in: .whitespaces)
        } else {
            elementName = remainder.isEmpty ? nil : remainder
        }

        if elementName?.isEmpty == true { elementName = nil }
        if elementDesc?.isEmpty == true { elementDesc = nil }

        let role = mapSystemEventsClass(rawClass)

        // Build the System Events element path for later interaction.
        // Use class + name when available for more reliable targeting.
        let elementPath: String
        if let name = elementName, !name.isEmpty {
            elementPath = "\(rawClass) \"\(escapeForAppleScript(name))\" of window \(windowIndex)"
        } else {
            // Positional reference -- less reliable but works for unnamed elements
            elementPath = "\(rawClass) 1 of window \(windowIndex)"
        }

        let ref = elementCache.register(
            appName: appName,
            elementPath: elementPath,
            role: role,
            displayName: elementName
        )

        return PilotElement(
            ref: ref,
            role: role,
            title: elementName,
            value: nil,
            description: elementDesc,
            enabled: true,
            focused: false,
            bounds: nil,
            children: nil
        )
    }

    /// Map a System Events class name to the closest AX role equivalent.
    private func mapSystemEventsClass(_ className: String) -> String {
        let lowered = className.lowercased()
        switch lowered {
        case "button":
            return "AXButton"
        case "text field":
            return "AXTextField"
        case "text area":
            return "AXTextArea"
        case "static text":
            return "AXStaticText"
        case "checkbox":
            return "AXCheckBox"
        case "radio button":
            return "AXRadioButton"
        case "pop up button":
            return "AXPopUpButton"
        case "menu button":
            return "AXMenuButton"
        case "slider":
            return "AXSlider"
        case "scroll area":
            return "AXScrollArea"
        case "scroll bar":
            return "AXScrollBar"
        case "table":
            return "AXTable"
        case "row":
            return "AXRow"
        case "column":
            return "AXColumn"
        case "cell":
            return "AXCell"
        case "group":
            return "AXGroup"
        case "toolbar":
            return "AXToolbar"
        case "tab group":
            return "AXTabGroup"
        case "tab":
            return "AXTab"
        case "image":
            return "AXImage"
        case "combo box":
            return "AXComboBox"
        case "list":
            return "AXList"
        case "outline":
            return "AXOutline"
        case "menu":
            return "AXMenu"
        case "menu item":
            return "AXMenuItem"
        case "window":
            return "AXWindow"
        case "sheet":
            return "AXSheet"
        case "splitter":
            return "AXSplitter"
        case "progress indicator":
            return "AXProgressIndicator"
        case "busy indicator":
            return "AXBusyIndicator"
        case "disclosure triangle":
            return "AXDisclosureTriangle"
        default:
            return "AX\(className.split(separator: " ").map { $0.capitalized }.joined())"
        }
    }

    /// Escape special characters for safe embedding in AppleScript strings.
    private func escapeForAppleScript(_ input: String) -> String {
        return input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - AppleScript Element Cache

/// Stores the mapping between "as" refs and System Events element paths.
///
/// Uses NSLock (not actor) so it can be called from synchronous
/// `InteractionLayer` protocol methods without crossing isolation boundaries.
private final class ASElementCache: @unchecked Sendable {

    private let lock = NSLock()
    private var entries: [String: ASElementEntry] = [:]
    private var counter: Int = 0

    /// Register an element and return its sequential ref.
    func register(
        appName: String,
        elementPath: String,
        role: String,
        displayName: String?
    ) -> String {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        let ref = "as\(counter)"
        entries[ref] = ASElementEntry(
            appName: appName,
            elementPath: elementPath,
            role: role,
            displayName: displayName
        )
        return ref
    }

    /// Look up a previously stored element by ref.
    func lookup(_ ref: String) -> ASElementEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[ref]
    }

    /// Remove all stored elements (call before a fresh snapshot).
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        counter = 0
    }
}

/// An entry in the AppleScript element cache.
private struct ASElementEntry: Sendable {
    let appName: String
    let elementPath: String
    let role: String
    let displayName: String?
}
