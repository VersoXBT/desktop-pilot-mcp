import Foundation

// MARK: - Layer Errors

/// Errors specific to interaction layers.
enum LayerError: Error, Sendable {
    case notSupported(layer: String, reason: String)
    case elementNotInteractable(ref: String)
    case typingFailed(ref: String, reason: String)
    case readFailed(ref: String, reason: String)
    case snapshotFailed(pid: Int32, reason: String)
}

// MARK: - Interaction Layer Protocol

/// An interaction method (accessibility, applescript, cgevent, screenshot).
/// The Router picks the highest-priority layer that can handle a given app.
protocol InteractionLayer: Sendable {

    /// Human-readable name of this layer (e.g. "Accessibility", "AppleScript").
    var name: String { get }

    /// Priority (lower number = preferred). The Router tries layers in order.
    var priority: Int { get }

    /// Can this layer handle the given app?
    func canHandle(bundleID: String?, appName: String) -> Bool

    /// Capture a UI snapshot tree for the given app.
    func snapshot(pid: Int32, maxDepth: Int) throws -> [PilotElement]

    /// Click an element identified by ref.
    func click(ref: String) throws

    /// Type text into an element identified by ref.
    func typeText(ref: String, text: String) throws

    /// Read the current value of an element identified by ref.
    func readValue(ref: String) throws -> String?
}
