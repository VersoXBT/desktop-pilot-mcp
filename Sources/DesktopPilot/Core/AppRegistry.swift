import AppKit
import Foundation

// MARK: - App Registry

/// Discovers and tracks running macOS applications.
///
/// Uses `NSWorkspace` to enumerate GUI apps and provides lookup by
/// name, bundle ID, or PID. Window counts are not populated here
/// (they require AX access); callers should enrich via `AXBridge`
/// when needed.
struct AppRegistry: Sendable {

    // MARK: - List All Apps

    /// List all running apps that have a GUI (activation policy `.regular`).
    ///
    /// This filters out background daemons, menu bar extras, and other
    /// non-user-facing processes.
    func listApps() -> [AppInfo] {
        let apps = NSWorkspace.shared.runningApplications

        return apps
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let name = app.localizedName else { return nil }
                return AppInfo(
                    name: name,
                    bundleID: app.bundleIdentifier,
                    pid: app.processIdentifier,
                    isScriptable: false,
                    windowCount: 0
                )
            }
    }

    // MARK: - Frontmost App

    /// Get the currently frontmost (active) application.
    func frontmostApp() -> AppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let name = app.localizedName else {
            return nil
        }
        return AppInfo(
            name: name,
            bundleID: app.bundleIdentifier,
            pid: app.processIdentifier,
            isScriptable: false,
            windowCount: 0
        )
    }

    // MARK: - Find by Name

    /// Find an app by name using case-insensitive partial matching.
    ///
    /// Matches against both the display name and bundle identifier.
    /// Returns the first match found.
    func findApp(name: String) -> AppInfo? {
        let lower = name.lowercased()
        return listApps().first {
            $0.name.lowercased().contains(lower)
                || ($0.bundleID?.lowercased().contains(lower) ?? false)
        }
    }

    // MARK: - Find by PID

    /// Find an app by its process identifier.
    func findApp(pid: Int32) -> AppInfo? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let name = app.localizedName else {
            return nil
        }
        return AppInfo(
            name: name,
            bundleID: app.bundleIdentifier,
            pid: app.processIdentifier,
            isScriptable: false,
            windowCount: 0
        )
    }

    // MARK: - Enrich with Window Count

    /// Return an updated `AppInfo` with the actual window count from AX.
    ///
    /// This requires accessibility permissions. If the count cannot be
    /// read, the original info is returned unchanged.
    func enrichWithWindowCount(_ info: AppInfo, bridge: AXBridge) -> AppInfo {
        let appElement = bridge.appElement(pid: info.pid)
        let windows = bridge.getWindows(appElement)
        return AppInfo(
            name: info.name,
            bundleID: info.bundleID,
            pid: info.pid,
            isScriptable: info.isScriptable,
            windowCount: windows.count
        )
    }
}
