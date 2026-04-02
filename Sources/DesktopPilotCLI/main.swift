import DesktopPilot

let bridge = AXBridge()
let store = ElementStore()

// Check accessibility permissions on startup
if !bridge.isAccessibilityEnabled() {
    Log.error(
        "Accessibility permission not granted. "
        + "Go to System Settings > Privacy & Security > Accessibility "
        + "and add this application."
    )
    _ = bridge.promptForAccessibility()
}

let toolHandler = PilotToolHandler(bridge: bridge, store: store)
let server = MCPServer(toolHandler: toolHandler)

await server.run()
