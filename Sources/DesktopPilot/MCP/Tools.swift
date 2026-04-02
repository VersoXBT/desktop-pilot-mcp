import ApplicationServices
import Foundation

// MARK: - Tool Registry

/// Registers all Desktop Pilot tools and dispatches calls to real implementations.
public final class PilotToolHandler: ToolHandler, @unchecked Sendable {

    private let bridge: AXBridge
    private let store: ElementStore
    private let registry: AppRegistry
    private let snapshotBuilder: SnapshotBuilder
    private let screenshotLayer: ScreenshotLayer

    public init(bridge: AXBridge, store: ElementStore) {
        self.bridge = bridge
        self.store = store
        self.registry = AppRegistry()
        self.snapshotBuilder = SnapshotBuilder(bridge: bridge)
        self.screenshotLayer = ScreenshotLayer(bridge: bridge, store: store)
    }

    public func listTools() -> [ToolDefinition] {
        [
            snapshotTool,
            clickTool,
            typeTool,
            readTool,
            findTool,
            listAppsTool,
            menuTool,
            scriptTool,
            screenshotTool,
            batchTool,
        ]
    }

    public func callTool(name: String, arguments: JSONValue?) async throws -> MCPToolResult {
        switch name {
        case "pilot_snapshot":
            return await handleSnapshot(arguments)
        case "pilot_click":
            return await handleClick(arguments)
        case "pilot_type":
            return await handleType(arguments)
        case "pilot_read":
            return await handleRead(arguments)
        case "pilot_find":
            return await handleFind(arguments)
        case "pilot_list_apps":
            return await handleListApps(arguments)
        case "pilot_menu":
            return await handleMenu(arguments)
        case "pilot_script":
            return await handleScript(arguments)
        case "pilot_screenshot":
            return await handleScreenshot(arguments)
        case "pilot_batch":
            return await handleBatch(arguments)
        default:
            return .error("Unknown tool: \(name)")
        }
    }

    // MARK: - Tool Definitions

    private var snapshotTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_snapshot",
            description: """
                Get a structured snapshot of an app's UI element tree via the Accessibility API. \
                Use this as the FIRST step when interacting with any macOS app -- it returns every \
                visible element with a ref ID you can pass to other tools. Much faster and more \
                reliable than screenshots.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app": .object([
                        "type": .string("string"),
                        "description": .string(
                            "App name or bundle ID. Omit for frontmost app."
                        ),
                    ]),
                    "maxDepth": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum tree depth to traverse (default 10)."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    private var clickTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_click",
            description: """
                Click a UI element by its ref ID. Use after pilot_snapshot to interact with \
                buttons, checkboxes, menu items, and other clickable elements.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "ref": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Element reference ID from a snapshot (e.g., \"e1\")."
                        ),
                    ]),
                ]),
                "required": .array([.string("ref")]),
            ])
        )
    }

    private var typeTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_type",
            description: """
                Type text into a UI element (text field, search box, etc.) by its ref ID. \
                Focuses the element first, then inserts the text.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "ref": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Element reference ID from a snapshot."
                        ),
                    ]),
                    "text": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Text to type into the element."
                        ),
                    ]),
                ]),
                "required": .array([.string("ref"), .string("text")]),
            ])
        )
    }

    private var readTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_read",
            description: """
                Read the current value/content of a UI element by its ref ID. Use to get text \
                field contents, label text, checkbox state, or any element's value attribute.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "ref": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Element reference ID from a snapshot."
                        ),
                    ]),
                ]),
                "required": .array([.string("ref")]),
            ])
        )
    }

    private var findTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_find",
            description: """
                Search for UI elements matching criteria (role, title, value) across one or \
                all apps. Faster than taking a full snapshot when you know what you're looking for.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "role": .object([
                        "type": .string("string"),
                        "description": .string(
                            "AX role to match (e.g., \"AXButton\", \"AXTextField\")."
                        ),
                    ]),
                    "title": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Title/label substring to match (case-insensitive)."
                        ),
                    ]),
                    "value": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Value substring to match."
                        ),
                    ]),
                    "app": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Limit search to this app name or bundle ID."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    private var listAppsTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_list_apps",
            description: """
                List all running applications with their names, bundle IDs, PIDs, and window \
                counts. Use to discover what apps are available before taking a snapshot.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
            ])
        )
    }

    private var menuTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_menu",
            description: """
                Activate a menu bar item by its path (e.g., \"File > Save As...\"). Works by \
                traversing the app's menu bar hierarchy.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Menu path using \" > \" separator (e.g., \"File > Save As...\")."
                        ),
                    ]),
                    "app": .object([
                        "type": .string("string"),
                        "description": .string(
                            "App name or bundle ID. Omit for frontmost app."
                        ),
                    ]),
                ]),
                "required": .array([.string("path")]),
            ])
        )
    }

    private var scriptTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_script",
            description: """
                Run an AppleScript or JXA script targeting a specific app. Use for operations \
                that are easier to express in script form than through individual UI actions.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Target app name."
                        ),
                    ]),
                    "code": .object([
                        "type": .string("string"),
                        "description": .string(
                            "AppleScript or JXA code to execute."
                        ),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Script language: \"applescript\" (default) or \"jxa\"."
                        ),
                        "enum": .array([
                            .string("applescript"),
                            .string("jxa"),
                        ]),
                    ]),
                ]),
                "required": .array([.string("app"), .string("code")]),
            ])
        )
    }

    private var screenshotTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_screenshot",
            description: """
                Capture a screenshot of a specific element or the full screen. Returns a \
                base64-encoded PNG. Use sparingly -- pilot_snapshot is usually better for \
                understanding UI state.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "ref": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Element ref to screenshot. Omit for full screen."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    private var batchTool: ToolDefinition {
        ToolDefinition(
            name: "pilot_batch",
            description: """
                Execute multiple tool calls in sequence. Reduces round-trips when you need \
                to perform several actions in a row (e.g., click a field, type text, click \
                a button).
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "actions": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Array of actions to execute in order."
                        ),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "tool": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "Tool name (e.g., \"pilot_click\")."
                                    ),
                                ]),
                                "params": .object([
                                    "type": .string("object"),
                                    "description": .string(
                                        "Tool parameters as key-value pairs."
                                    ),
                                    "additionalProperties": .object([
                                        "type": .string("string"),
                                    ]),
                                ]),
                            ]),
                            "required": .array([
                                .string("tool"),
                                .string("params"),
                            ]),
                        ]),
                    ]),
                ]),
                "required": .array([.string("actions")]),
            ])
        )
    }

    // MARK: - Real Handlers

    private func resolveApp(_ appName: String?) -> (name: String, pid: Int32)? {
        if let appName = appName {
            if let info = registry.findApp(name: appName) {
                return (info.name, info.pid)
            }
            return nil
        }
        if let info = registry.frontmostApp() {
            return (info.name, info.pid)
        }
        return nil
    }

    private func handleSnapshot(_ arguments: JSONValue?) async -> MCPToolResult {
        guard bridge.isAccessibilityEnabled() else {
            return .error(
                "Accessibility permission not granted. "
                + "Go to System Settings > Privacy & Security > Accessibility "
                + "and add this application."
            )
        }

        let appName = arguments?.stringValue(forKey: "app")
        let maxDepth = arguments?.intValue(forKey: "maxDepth") ?? 10

        guard let app = resolveApp(appName) else {
            return .error("Could not find app: \(appName ?? "frontmost"). Is it running?")
        }

        let appElement = bridge.appElement(pid: app.pid)
        let appInfo = registry.findApp(pid: app.pid)

        let snapshot = await snapshotBuilder.buildSnapshot(
            appElement: appElement,
            appName: app.name,
            bundleID: appInfo?.bundleID,
            pid: app.pid,
            store: store,
            maxDepth: maxDepth
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(snapshot)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return .success(json)
        } catch {
            return .error("Failed to encode snapshot: \(error)")
        }
    }

    private func handleClick(_ arguments: JSONValue?) async -> MCPToolResult {
        guard let ref = arguments?.stringValue(forKey: "ref") else {
            return .error("Missing required parameter: ref")
        }

        guard let wrapper = await store.resolve(ref) else {
            return .error("Unknown ref '\(ref)'. Take a new snapshot first.")
        }

        let success = bridge.performAction(wrapper.element, kAXPressAction)
        if success {
            return .success("Clicked element \(ref)")
        } else {
            return .error("Failed to click element \(ref). It may not be clickable.")
        }
    }

    private func handleType(_ arguments: JSONValue?) async -> MCPToolResult {
        guard let ref = arguments?.stringValue(forKey: "ref"),
              let text = arguments?.stringValue(forKey: "text") else {
            return .error("Missing required parameters: ref, text")
        }

        guard let wrapper = await store.resolve(ref) else {
            return .error("Unknown ref '\(ref)'. Take a new snapshot first.")
        }

        // Focus the element first
        _ = bridge.setAttribute(
            wrapper.element,
            kAXFocusedAttribute,
            true as CFTypeRef
        )

        // Try to set value directly
        let success = bridge.setAttribute(
            wrapper.element,
            kAXValueAttribute,
            text as CFTypeRef
        )

        if success {
            return .success("Typed \"\(text)\" into element \(ref)")
        } else {
            return .error(
                "Failed to type into element \(ref). "
                + "It may not be a text input field."
            )
        }
    }

    private func handleRead(_ arguments: JSONValue?) async -> MCPToolResult {
        guard let ref = arguments?.stringValue(forKey: "ref") else {
            return .error("Missing required parameter: ref")
        }

        guard let wrapper = await store.resolve(ref) else {
            return .error("Unknown ref '\(ref)'. Take a new snapshot first.")
        }

        let value = bridge.getValue(wrapper.element)
        let title = bridge.getTitle(wrapper.element)
        let role = bridge.getRole(wrapper.element)
        let description = bridge.getDescription(wrapper.element)

        var parts: [String] = []
        if let role = role { parts.append("role: \(role)") }
        if let title = title { parts.append("title: \(title)") }
        if let value = value { parts.append("value: \(value)") }
        if let description = description { parts.append("description: \(description)") }

        if parts.isEmpty {
            return .success("Element \(ref) has no readable attributes.")
        }
        return .success(parts.joined(separator: "\n"))
    }

    private func handleFind(_ arguments: JSONValue?) async -> MCPToolResult {
        guard bridge.isAccessibilityEnabled() else {
            return .error("Accessibility permission not granted.")
        }

        let roleFilter = arguments?.stringValue(forKey: "role")
        let titleFilter = arguments?.stringValue(forKey: "title")
        let valueFilter = arguments?.stringValue(forKey: "value")
        let appName = arguments?.stringValue(forKey: "app")

        guard let app = resolveApp(appName) else {
            return .error("Could not find app: \(appName ?? "frontmost")")
        }

        let appElement = bridge.appElement(pid: app.pid)
        let appInfo = registry.findApp(pid: app.pid)

        // Build a snapshot to search through
        let snapshot = await snapshotBuilder.buildSnapshot(
            appElement: appElement,
            appName: app.name,
            bundleID: appInfo?.bundleID,
            pid: app.pid,
            store: store,
            maxDepth: 10
        )

        // Flatten and filter
        var matches: [PilotElement] = []
        flattenAndFilter(
            elements: snapshot.elements,
            role: roleFilter,
            title: titleFilter,
            value: valueFilter,
            into: &matches,
            limit: 50
        )

        if matches.isEmpty {
            return .success("No elements found matching the criteria.")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(matches)
            let json = String(data: data, encoding: .utf8) ?? "[]"
            return .success(json)
        } catch {
            return .error("Failed to encode results: \(error)")
        }
    }

    private func flattenAndFilter(
        elements: [PilotElement],
        role: String?,
        title: String?,
        value: String?,
        into matches: inout [PilotElement],
        limit: Int
    ) {
        for element in elements {
            guard matches.count < limit else { return }

            var isMatch = true

            if let role = role {
                let elementRole = element.role.lowercased()
                let searchRole = role.lowercased()
                if !elementRole.contains(searchRole) {
                    isMatch = false
                }
            }

            if let title = title, isMatch {
                let elementTitle = (element.title ?? "").lowercased()
                if !elementTitle.contains(title.lowercased()) {
                    isMatch = false
                }
            }

            if let value = value, isMatch {
                let elementValue = (element.value ?? "").lowercased()
                if !elementValue.contains(value.lowercased()) {
                    isMatch = false
                }
            }

            if isMatch {
                // Return without children to keep output compact
                matches.append(PilotElement(
                    ref: element.ref,
                    role: element.role,
                    title: element.title,
                    value: element.value,
                    description: element.description,
                    enabled: element.enabled,
                    focused: element.focused,
                    bounds: element.bounds,
                    children: nil
                ))
            }

            if let children = element.children {
                flattenAndFilter(
                    elements: children,
                    role: role,
                    title: title,
                    value: value,
                    into: &matches,
                    limit: limit
                )
            }
        }
    }

    private func handleListApps(_ arguments: JSONValue?) async -> MCPToolResult {
        var apps = registry.listApps()

        // Enrich with window counts if accessibility is enabled
        if bridge.isAccessibilityEnabled() {
            apps = apps.map { registry.enrichWithWindowCount($0, bridge: bridge) }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(apps)
            let json = String(data: data, encoding: .utf8) ?? "[]"
            return .success(json)
        } catch {
            return .error("Failed to encode app list: \(error)")
        }
    }

    private func handleMenu(_ arguments: JSONValue?) async -> MCPToolResult {
        guard let pathStr = arguments?.stringValue(forKey: "path") else {
            return .error("Missing required parameter: path")
        }

        let appName = arguments?.stringValue(forKey: "app")
        guard let app = resolveApp(appName) else {
            return .error("Could not find app: \(appName ?? "frontmost")")
        }

        let pathComponents = pathStr
            .components(separatedBy: " > ")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard !pathComponents.isEmpty else {
            return .error("Invalid menu path: \(pathStr)")
        }

        let appElement = bridge.appElement(pid: app.pid)
        let success = bridge.navigateMenu(appElement, path: pathComponents)

        if success {
            return .success("Activated menu: \(pathStr)")
        } else {
            return .error(
                "Failed to navigate menu path: \(pathStr). "
                + "Check that the menu items exist in \(app.name)."
            )
        }
    }

    private func handleScript(_ arguments: JSONValue?) async -> MCPToolResult {
        guard let code = arguments?.stringValue(forKey: "code") else {
            return .error("Missing required parameter: code")
        }

        let language = arguments?.stringValue(forKey: "language") ?? "applescript"

        let process = Process()
        let pipe = Pipe()

        if language == "jxa" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", "-e", code]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", code]
        }

        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""

            if process.terminationStatus == 0 {
                return .success(output.isEmpty ? "Script executed successfully." : output)
            } else {
                return .error("Script failed (exit \(process.terminationStatus)): \(output)")
            }
        } catch {
            return .error("Failed to run script: \(error)")
        }
    }

    private func handleScreenshot(_ arguments: JSONValue?) async -> MCPToolResult {
        let ref = arguments?.stringValue(forKey: "ref")

        // If a ref is provided, capture that element's bounds
        if let ref {
            guard let wrapper = await store.resolve(ref) else {
                return .error("Unknown ref '\(ref)'. Take a new snapshot first.")
            }

            guard let bounds = bridge.getBounds(wrapper.element) else {
                return .error(
                    "Could not determine bounds for element \(ref). "
                    + "The element may not have a visible frame."
                )
            }

            guard let base64 = screenshotLayer.captureElementBase64(bounds: bounds) else {
                return .error(
                    "Failed to capture screenshot of element \(ref). "
                    + "Screen recording permission may not be granted."
                )
            }

            return MCPToolResult(
                content: [.image(base64: base64, mimeType: "image/png")],
                isError: false
            )
        }

        // No ref -- capture full screen
        guard let base64 = screenshotLayer.captureFullScreenBase64() else {
            return .error(
                "Failed to capture full screen screenshot. "
                + "Screen recording permission may not be granted. "
                + "Go to System Settings > Privacy & Security > Screen Recording "
                + "and add this application."
            )
        }

        return MCPToolResult(
            content: [.image(base64: base64, mimeType: "image/png")],
            isError: false
        )
    }

    private func handleBatch(_ arguments: JSONValue?) async -> MCPToolResult {
        guard case .object(let dict) = arguments,
              case .array(let actions) = dict["actions"] else {
            return .error("Missing required parameter: actions")
        }

        var results: [String] = []
        for (index, action) in actions.enumerated() {
            guard case .object(let actionDict) = action,
                  case .string(let toolName) = actionDict["tool"] else {
                results.append("action[\(index)]: invalid format")
                continue
            }
            do {
                let toolResult = try await callTool(
                    name: toolName,
                    arguments: actionDict["params"]
                )
                let text = toolResult.content.first?.text ?? "(no output)"
                results.append("action[\(index)] \(toolName): \(text)")
            } catch {
                results.append("action[\(index)] \(toolName): error - \(error)")
            }
        }

        return .success(results.joined(separator: "\n"))
    }
}
