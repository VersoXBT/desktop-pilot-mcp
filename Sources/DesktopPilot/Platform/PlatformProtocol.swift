import Foundation

// MARK: - Platform Errors

/// Errors that can occur during platform operations.
enum PlatformError: Error, Sendable {
    case permissionDenied
    case elementNotFound(ref: String)
    case actionFailed(action: String, reason: String)
    case attributeReadFailed(attribute: String)
    case appNotFound(name: String)
    case menuNavigationFailed(path: [String])
    case unsupported(description: String)
}

// MARK: - Platform Bridge Protocol

/// Protocol for platform-specific UI automation.
/// macOS implementation uses AXUIElement; future Windows implementation
/// would use UI Automation.
protocol PlatformBridge: Sendable {

    /// Check if accessibility permissions are granted.
    func checkPermissions() -> Bool

    /// Request accessibility permissions (shows system dialog).
    func requestPermissions() -> Bool

    /// Get the frontmost application info.
    func getFrontmostApp() -> (name: String, bundleID: String?, pid: Int32)?

    /// List all running applications with windows.
    func listApps() -> [(name: String, bundleID: String?, pid: Int32, windowCount: Int)]

    /// Get the accessibility tree for an app by PID.
    func getAccessibilityTree(pid: Int32, maxDepth: Int) -> [PilotElement]

    /// Perform click on element.
    func clickElement(ref: String) throws

    /// Type text into element.
    func typeIntoElement(ref: String, text: String) throws

    /// Read value from element.
    func readElement(ref: String) throws -> String?

    /// Navigate menu bar.
    func navigateMenu(appPID: Int32, path: [String]) throws
}
