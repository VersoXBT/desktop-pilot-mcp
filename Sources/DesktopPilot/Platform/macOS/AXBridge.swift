import ApplicationServices
import AppKit
import Foundation

// MARK: - Sendable Wrapper

/// Wraps an AXUIElement so it can cross concurrency boundaries.
/// AXUIElement is a CFTypeRef (thread-safe by Apple's AX implementation)
/// but Swift 6 does not know that, so we use @unchecked Sendable.
public final class AXElementWrapper: @unchecked Sendable {
    public let element: AXUIElement

    public init(_ element: AXUIElement) {
        self.element = element
    }
}

// MARK: - AXBridge

/// Low-level wrapper around the macOS AXUIElement C API.
/// Every public method is pure — no shared mutable state — so the
/// type is safe to use from any isolation context.
public final class AXBridge: @unchecked Sendable {

    public init() {}

    // MARK: - Element Creation

    /// Create the root accessibility element for a running app.
    func appElement(pid: pid_t) -> AXUIElement {
        return AXUIElementCreateApplication(pid)
    }

    // MARK: - Attribute Reading

    /// Read a single attribute from an element.
    func getAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    /// Read multiple attributes in one call (faster than individual reads).
    func getAttributes(_ element: AXUIElement, _ attributes: [String]) -> [CFTypeRef?] {
        let cfAttributes = attributes.map { $0 as CFString } as CFArray
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element,
            cfAttributes,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &values
        )
        guard error == .success, let cfArray = values else {
            return Array(repeating: nil, count: attributes.count)
        }
        let count = CFArrayGetCount(cfArray)
        var result: [CFTypeRef?] = []
        for i in 0..<count {
            let raw = CFArrayGetValueAtIndex(cfArray, i)
            if let raw = raw {
                let ref = Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue()
                // AXError sentinel values come back as kCFNull
                if CFGetTypeID(ref) == CFNullGetTypeID() {
                    result.append(nil)
                } else {
                    result.append(ref)
                }
            } else {
                result.append(nil)
            }
        }
        return result
    }

    // MARK: - Attribute Writing

    /// Set an attribute value on an element.
    func setAttribute(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        return error == .success
    }

    // MARK: - Actions

    /// Perform a named action on an element (e.g. kAXPressAction).
    func performAction(_ element: AXUIElement, _ action: String) -> Bool {
        let error = AXUIElementPerformAction(element, action as CFString)
        return error == .success
    }

    // MARK: - Convenience Readers

    /// Get children of an element.
    func getChildren(_ element: AXUIElement) -> [AXUIElement] {
        guard let value = getAttribute(element, kAXChildrenAttribute) else { return [] }
        guard let children = value as? [AXUIElement] else { return [] }
        return children
    }

    /// Get the role of an element (e.g. "AXButton").
    func getRole(_ element: AXUIElement) -> String? {
        guard let value = getAttribute(element, kAXRoleAttribute) else { return nil }
        return value as? String
    }

    /// Get the title of an element.
    func getTitle(_ element: AXUIElement) -> String? {
        guard let value = getAttribute(element, kAXTitleAttribute) else { return nil }
        return value as? String
    }

    /// Get the value of an element as a string.
    func getValue(_ element: AXUIElement) -> String? {
        guard let value = getAttribute(element, kAXValueAttribute) else { return nil }
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return String(describing: value)
    }

    /// Get the accessibility description of an element.
    func getDescription(_ element: AXUIElement) -> String? {
        guard let value = getAttribute(element, kAXDescriptionAttribute) else { return nil }
        return value as? String
    }

    /// Check if element is enabled.
    func isEnabled(_ element: AXUIElement) -> Bool {
        guard let value = getAttribute(element, kAXEnabledAttribute) else { return true }
        return (value as? Bool) ?? true
    }

    /// Check if element has keyboard focus.
    func isFocused(_ element: AXUIElement) -> Bool {
        guard let value = getAttribute(element, kAXFocusedAttribute) else { return false }
        return (value as? Bool) ?? false
    }

    /// Get the bounding rectangle of an element in screen coordinates.
    func getBounds(_ element: AXUIElement) -> ElementBounds? {
        guard let posValue = getAttribute(element, kAXPositionAttribute),
              CFGetTypeID(posValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point) else { return nil }

        guard let sizeValue = getAttribute(element, kAXSizeAttribute),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return ElementBounds(
            x: Double(point.x),
            y: Double(point.y),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    // MARK: - App-level Queries

    /// Get the currently focused UI element inside an app.
    func getFocusedElement(_ appElement: AXUIElement) -> AXUIElement? {
        guard let value = getAttribute(appElement, kAXFocusedUIElementAttribute) else { return nil }
        // AXFocusedUIElement always returns AXUIElement when the attribute exists
        return (value as! AXUIElement) // swiftlint:disable:this force_cast
    }

    /// Get all windows belonging to an app.
    func getWindows(_ appElement: AXUIElement) -> [AXUIElement] {
        guard let value = getAttribute(appElement, kAXWindowsAttribute) else { return [] }
        guard let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    /// Get the menu bar element for an app.
    func getMenuBar(_ appElement: AXUIElement) -> AXUIElement? {
        guard let value = getAttribute(appElement, kAXMenuBarAttribute) else { return nil }
        // AXMenuBar always returns AXUIElement when the attribute exists
        return (value as! AXUIElement) // swiftlint:disable:this force_cast
    }

    // MARK: - Menu Navigation

    /// Walk a menu path like ["File", "Save As..."] and press the final item.
    func navigateMenu(_ appElement: AXUIElement, path: [String]) -> Bool {
        guard let menuBar = getMenuBar(appElement), !path.isEmpty else { return false }

        var current: AXUIElement = menuBar

        for (index, menuName) in path.enumerated() {
            let children = getChildren(current)
            var matched = false

            for child in children {
                let title = getTitle(child)
                guard title == menuName else { continue }

                let isLast = index == path.count - 1
                if isLast {
                    return performAction(child, kAXPressAction)
                }

                // Intermediate menu — drill into its submenu children
                let subChildren = getChildren(child)
                if let submenu = subChildren.first {
                    current = submenu
                    matched = true
                    break
                }
            }

            if !matched {
                return false
            }
        }

        return false
    }

    // MARK: - Permissions

    /// Check if the current process is trusted for accessibility.
    public func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Prompt the user to grant accessibility access if not already trusted.
    public func promptForAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
