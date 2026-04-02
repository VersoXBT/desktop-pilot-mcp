import ApplicationServices
import Foundation

// MARK: - Permission Manager

/// Handles accessibility permission checking and requesting.
struct PermissionManager: Sendable {

    /// Check if the current process has accessibility permissions.
    static func isGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Check permissions and optionally prompt the user via the system dialog.
    /// Returns `true` if already granted; if not, shows the dialog and returns
    /// the (likely still-false) current state — the user must toggle the setting
    /// in System Settings and restart the process.
    static func checkOrPrompt() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Write a human-readable permission status to stderr.
    static func logPermissionStatus() {
        let granted = isGranted()
        let message = granted
            ? "[DesktopPilot] Accessibility permissions: GRANTED"
            : "[DesktopPilot] Accessibility permissions: NOT GRANTED — open System Settings > Privacy & Security > Accessibility"
        if let data = (message + "\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
