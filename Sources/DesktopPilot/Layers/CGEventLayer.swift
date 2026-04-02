import CoreGraphics
import ApplicationServices
import Foundation

// MARK: - Virtual Key Codes

/// Common macOS virtual key codes for CGEvent keyboard events.
/// Based on Events.h / HIToolbox kVK constants.
enum VirtualKeyCode {
    static let returnKey: CGKeyCode     = 36
    static let tab: CGKeyCode           = 48
    static let space: CGKeyCode         = 49
    static let delete: CGKeyCode        = 51
    static let escape: CGKeyCode        = 53
    static let forwardDelete: CGKeyCode = 117

    // Arrow keys
    static let leftArrow: CGKeyCode     = 123
    static let rightArrow: CGKeyCode    = 124
    static let downArrow: CGKeyCode     = 125
    static let upArrow: CGKeyCode       = 126

    // Modifier keys (for reference; typically used via CGEventFlags)
    static let command: CGKeyCode       = 55
    static let shift: CGKeyCode         = 56
    static let option: CGKeyCode        = 58
    static let control: CGKeyCode       = 59
    static let capsLock: CGKeyCode      = 57

    // Function keys
    static let f1: CGKeyCode            = 122
    static let f2: CGKeyCode            = 120
    static let f3: CGKeyCode            = 99
    static let f4: CGKeyCode            = 118
    static let f5: CGKeyCode            = 96
    static let f6: CGKeyCode            = 97
    static let f7: CGKeyCode            = 98
    static let f8: CGKeyCode            = 100
    static let f9: CGKeyCode            = 101
    static let f10: CGKeyCode           = 109
    static let f11: CGKeyCode           = 103
    static let f12: CGKeyCode           = 111

    // Navigation
    static let home: CGKeyCode          = 115
    static let end: CGKeyCode           = 119
    static let pageUp: CGKeyCode        = 116
    static let pageDown: CGKeyCode      = 121

    // Common letter keys (virtual key codes for Cmd+key combos)
    static let a: CGKeyCode             = 0
    static let c: CGKeyCode             = 8
    static let v: CGKeyCode             = 9
    static let x: CGKeyCode             = 7
    static let z: CGKeyCode             = 6
    static let s: CGKeyCode             = 1
    static let w: CGKeyCode             = 13
    static let q: CGKeyCode             = 12
    static let n: CGKeyCode             = 45
    static let t: CGKeyCode             = 17
}

// MARK: - CGEventLayer

/// Ultra-fast input injection via CGEvent.
/// Used for keyboard input and coordinate-based clicking when other methods fail.
///
/// CGEvent provides 1-5ms latency for mouse and keyboard events, making it
/// the fastest way to simulate user input on macOS. Unlike the Accessibility
/// layer, CGEvent cannot read UI state -- it can only inject input events.
final class CGEventLayer: @unchecked Sendable {

    private let bridge: AXBridge
    private let store: ElementStore

    init(bridge: AXBridge, store: ElementStore) {
        self.bridge = bridge
        self.store = store
    }

    // MARK: - Mouse Events

    /// Click at screen coordinates.
    func clickAt(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)

        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )

        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }

    /// Click at the center of an element's bounding rectangle.
    func clickElement(bounds: ElementBounds) {
        let centerX = bounds.x + bounds.width / 2.0
        let centerY = bounds.y + bounds.height / 2.0
        clickAt(x: centerX, y: centerY)
    }

    /// Double-click at screen coordinates.
    func doubleClickAt(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)

        for _ in 0..<2 {
            let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            )
            let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
            mouseDown?.setIntegerValueField(.mouseEventClickState, value: 2)
            mouseUp?.setIntegerValueField(.mouseEventClickState, value: 2)
            mouseDown?.post(tap: .cghidEventTap)
            mouseUp?.post(tap: .cghidEventTap)
        }
    }

    /// Right-click at screen coordinates.
    func rightClickAt(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)

        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        )

        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }

    /// Move mouse to coordinates.
    func moveTo(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)
        let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        moveEvent?.post(tap: .cghidEventTap)
    }

    /// Drag from one point to another using left mouse button.
    func drag(from start: CGPoint, to end: CGPoint) {
        // Press down at start
        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: start,
            mouseButton: .left
        )
        mouseDown?.post(tap: .cghidEventTap)

        // Drag to end point
        let dragEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: end,
            mouseButton: .left
        )
        dragEvent?.post(tap: .cghidEventTap)

        // Release at end
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: end,
            mouseButton: .left
        )
        mouseUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard Events

    /// Type a string character by character using CGEvent keyboard events.
    /// This is the fastest and most reliable typing method.
    func typeString(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            let str = String(char)
            for scalar in str.unicodeScalars {
                var unichar = UniChar(scalar.value)
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

                keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)

                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
            }
        }
    }

    /// Press a virtual key with optional modifiers.
    func pressKey(virtualKey: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)

        keyDown?.flags = flags
        keyUp?.flags = flags

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Press Return/Enter.
    func pressReturn() { pressKey(virtualKey: VirtualKeyCode.returnKey) }

    /// Press Tab.
    func pressTab() { pressKey(virtualKey: VirtualKeyCode.tab) }

    /// Press Escape.
    func pressEscape() { pressKey(virtualKey: VirtualKeyCode.escape) }

    /// Press Delete/Backspace.
    func pressDelete() { pressKey(virtualKey: VirtualKeyCode.delete) }

    /// Cmd+A (Select All).
    func selectAll() { pressKey(virtualKey: VirtualKeyCode.a, flags: .maskCommand) }

    /// Cmd+C (Copy).
    func copy() { pressKey(virtualKey: VirtualKeyCode.c, flags: .maskCommand) }

    /// Cmd+V (Paste).
    func paste() { pressKey(virtualKey: VirtualKeyCode.v, flags: .maskCommand) }

    /// Cmd+X (Cut).
    func cut() { pressKey(virtualKey: VirtualKeyCode.x, flags: .maskCommand) }

    /// Cmd+Z (Undo).
    func undo() { pressKey(virtualKey: VirtualKeyCode.z, flags: .maskCommand) }

    /// Cmd+Shift+Z (Redo).
    func redo() { pressKey(virtualKey: VirtualKeyCode.z, flags: [.maskCommand, .maskShift]) }

    // MARK: - Scroll

    /// Scroll at current mouse position.
    func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }
}

// MARK: - InteractionLayer Conformance

extension CGEventLayer: InteractionLayer {
    var name: String { "CGEvent" }
    var priority: Int { 40 }

    func canHandle(bundleID: String?, appName: String) -> Bool {
        // CGEvent works with any app for input injection
        return true
    }

    func snapshot(pid: Int32, maxDepth: Int) throws -> [PilotElement] {
        throw LayerError.notSupported(
            layer: name,
            reason: "CGEvent cannot read UI state. Use Accessibility layer for snapshots."
        )
    }

    func click(ref: String) throws {
        // CGEvent click requires screen coordinates, not an element ref.
        // Use clickAt(x:y:) or clickElement(bounds:) directly instead.
        throw LayerError.notSupported(
            layer: name,
            reason: "Use clickAt(x:y:) directly with coordinates from element bounds."
        )
    }

    func typeText(ref: String, text: String) throws {
        // CGEvent typing doesn't target a specific element -- it types to whatever is focused
        typeString(text)
    }

    func readValue(ref: String) throws -> String? {
        throw LayerError.notSupported(
            layer: name,
            reason: "CGEvent cannot read UI state. Use Accessibility layer for reading."
        )
    }
}
