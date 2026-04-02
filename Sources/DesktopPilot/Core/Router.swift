import Foundation

// MARK: - Interaction Method

/// The layer used to interact with a macOS application.
///
/// Phase 1 uses accessibility exclusively. Future phases will add
/// AppleScript for scriptable apps, CGEvent for low-level input,
/// and screenshot-based fallback for apps with poor AX support.
enum InteractionMethod: Sendable {
    case accessibility
    case applescript
    case cgevent
    case screenshot
}

// MARK: - Router

/// Routes operations to the best available interaction layer for a given
/// app and action.
///
/// Designed for extensibility: the Phase 1 implementation always returns
/// `.accessibility`, but the interface supports richer routing logic
/// in later phases (e.g. preferring AppleScript for scriptable apps,
/// falling back to CGEvent for apps with broken AX trees).
final class Router: Sendable {

    // MARK: - App-level Routing

    /// Determine the best general interaction method for an app.
    ///
    /// - Parameters:
    ///   - appName: The display name of the target application.
    ///   - bundleID: The bundle identifier, if known.
    /// - Returns: The recommended interaction method.
    func bestMethod(appName: String, bundleID: String?) -> InteractionMethod {
        // Phase 1: always use accessibility
        return .accessibility
    }

    // MARK: - Action-level Routing

    /// Determine the best method for a specific operation on an app.
    ///
    /// Some actions may benefit from different layers even within the same
    /// app. For example, text input might use CGEvent for better reliability
    /// in some contexts, while tree reading always uses accessibility.
    ///
    /// - Parameters:
    ///   - action: The action being performed (e.g. "click", "type", "read").
    ///   - appName: The display name of the target application.
    ///   - bundleID: The bundle identifier, if known.
    /// - Returns: The recommended interaction method.
    func bestMethodForAction(
        action: String,
        appName: String,
        bundleID: String?
    ) -> InteractionMethod {
        // Phase 1: always use accessibility
        return .accessibility
    }

    // MARK: - Capability Check

    /// Check whether a given method is available on this system.
    ///
    /// - Parameter method: The interaction method to check.
    /// - Returns: `true` if the method can be used.
    func isAvailable(_ method: InteractionMethod) -> Bool {
        switch method {
        case .accessibility:
            return true
        case .applescript:
            return false // Phase 2
        case .cgevent:
            return false // Phase 2
        case .screenshot:
            return false // Phase 2
        }
    }
}
