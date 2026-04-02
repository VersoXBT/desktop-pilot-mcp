import ApplicationServices
import AppKit
import Foundation

// MARK: - Layer-local Element Cache

/// Lock-based element cache used by AccessibilityLayer.
/// Unlike the actor-based `ElementStore` in Core, this uses NSLock so it
/// can be called from synchronous `InteractionLayer` protocol methods
/// without crossing isolation boundaries.
private final class LayerElementCache: @unchecked Sendable {

    private let lock = NSLock()
    private var elements: [String: AXElementWrapper] = [:]
    private var counter: Int = 0

    /// Register an element and return its sequential ref.
    func register(_ element: AXUIElement) -> String {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        let ref = "e\(counter)"
        elements[ref] = AXElementWrapper(element)
        return ref
    }

    /// Look up a previously stored element by ref.
    func lookup(_ ref: String) -> AXElementWrapper? {
        lock.lock()
        defer { lock.unlock() }
        return elements[ref]
    }

    /// Remove all stored elements (call before a fresh snapshot).
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        elements.removeAll()
        counter = 0
    }

    /// Current number of stored elements.
    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return elements.count
    }
}

// MARK: - Accessibility Layer

/// Primary interaction layer using the macOS Accessibility API.
/// Walks AXUIElement trees via `AXBridge`, builds `PilotElement`
/// snapshots, and performs actions (click, type, read).
final class AccessibilityLayer: @unchecked Sendable, InteractionLayer {

    let name: String = "Accessibility"
    let priority: Int = 0

    private let bridge: AXBridge
    private let cache: LayerElementCache

    init(bridge: AXBridge = AXBridge()) {
        self.bridge = bridge
        self.cache = LayerElementCache()
    }

    // MARK: - InteractionLayer Conformance

    func canHandle(bundleID: String?, appName: String) -> Bool {
        // The accessibility layer can handle any app that exposes an AX tree.
        // We optimistically return true; individual operations will fail
        // gracefully if the app doesn't cooperate.
        return true
    }

    func snapshot(pid: Int32, maxDepth: Int) throws -> [PilotElement] {
        guard bridge.isAccessibilityEnabled() else {
            throw PlatformError.permissionDenied
        }

        cache.clear()

        let appEl = bridge.appElement(pid: pid)
        let windows = bridge.getWindows(appEl)
        let sources = windows.isEmpty ? bridge.getChildren(appEl) : windows

        if sources.isEmpty {
            throw LayerError.snapshotFailed(
                pid: pid,
                reason: "App has no windows or accessible children"
            )
        }

        return sources.compactMap { buildElement($0, depth: 0, maxDepth: maxDepth) }
    }

    func click(ref: String) throws {
        let wrapper = try resolveRef(ref)
        let pressed = bridge.performAction(wrapper.element, kAXPressAction)
        if !pressed {
            throw PlatformError.actionFailed(
                action: "press",
                reason: "AXPress action failed for ref '\(ref)'"
            )
        }
    }

    func typeText(ref: String, text: String) throws {
        let wrapper = try resolveRef(ref)
        let element = wrapper.element

        // Focus the element first
        _ = bridge.setAttribute(element, kAXFocusedAttribute, kCFBooleanTrue)

        // Try setting the value directly
        let success = bridge.setAttribute(element, kAXValueAttribute, text as CFTypeRef)
        if !success {
            throw LayerError.typingFailed(
                ref: ref,
                reason: "Could not set AXValue on element -- it may not be an editable text field"
            )
        }
    }

    func readValue(ref: String) throws -> String? {
        let wrapper = try resolveRef(ref)
        return bridge.getValue(wrapper.element)
    }

    // MARK: - Public Helpers

    /// Look up a stored element wrapper by ref.
    func findElement(ref: String) -> AXElementWrapper? {
        return cache.lookup(ref)
    }

    // MARK: - Private Helpers

    /// Resolve a ref string to an AXElementWrapper, throwing if not found.
    private func resolveRef(_ ref: String) throws -> AXElementWrapper {
        guard let wrapper = cache.lookup(ref) else {
            throw PlatformError.elementNotFound(ref: ref)
        }
        return wrapper
    }

    /// Recursively build a PilotElement tree from an AXUIElement.
    private func buildElement(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int
    ) -> PilotElement? {
        guard let role = bridge.getRole(element) else { return nil }

        // Skip explicitly unknown roles
        if role == "AXUnknown" { return nil }

        let ref = cache.register(element)
        let title = bridge.getTitle(element)
        let value = bridge.getValue(element)
        let description = bridge.getDescription(element)
        let enabled = bridge.isEnabled(element)
        let focused = bridge.isFocused(element)
        let bounds = bridge.getBounds(element)

        var children: [PilotElement]?
        if depth < maxDepth {
            let axChildren = bridge.getChildren(element)
            if !axChildren.isEmpty {
                let built = axChildren.compactMap { child in
                    buildElement(child, depth: depth + 1, maxDepth: maxDepth)
                }
                children = built.isEmpty ? nil : built
            }
        }

        return PilotElement(
            ref: ref,
            role: role,
            title: title,
            value: value,
            description: description,
            enabled: enabled,
            focused: focused,
            bounds: bounds,
            children: children
        )
    }
}
