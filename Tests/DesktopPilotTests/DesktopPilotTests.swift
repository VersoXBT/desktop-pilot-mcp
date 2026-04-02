import XCTest
@testable import DesktopPilot

final class DesktopPilotTests: XCTestCase {

    // MARK: - Types Tests

    func testPilotElementEncoding() throws {
        let element = PilotElement(
            ref: "e1",
            role: "AXButton",
            title: "OK",
            value: nil,
            description: "Confirm button",
            enabled: true,
            focused: false,
            bounds: ElementBounds(x: 100, y: 200, width: 80, height: 30),
            children: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(element)
        let decoded = try JSONDecoder().decode(PilotElement.self, from: data)

        XCTAssertEqual(decoded.ref, "e1")
        XCTAssertEqual(decoded.role, "AXButton")
        XCTAssertEqual(decoded.title, "OK")
        XCTAssertNil(decoded.value)
        XCTAssertTrue(decoded.enabled)
        XCTAssertFalse(decoded.focused)
        XCTAssertEqual(decoded.bounds?.x, 100)
    }

    func testAppSnapshotEncoding() throws {
        let snapshot = AppSnapshot(
            app: "Finder",
            bundleID: "com.apple.finder",
            pid: 1234,
            timestamp: "2024-01-01T00:00:00Z",
            elementCount: 5,
            elements: []
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: data)

        XCTAssertEqual(decoded.app, "Finder")
        XCTAssertEqual(decoded.bundleID, "com.apple.finder")
        XCTAssertEqual(decoded.pid, 1234)
        XCTAssertEqual(decoded.elementCount, 5)
    }

    func testAppInfoEncoding() throws {
        let info = AppInfo(
            name: "Safari",
            bundleID: "com.apple.Safari",
            pid: 5678,
            isScriptable: true,
            windowCount: 3
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(AppInfo.self, from: data)

        XCTAssertEqual(decoded.name, "Safari")
        XCTAssertTrue(decoded.isScriptable)
        XCTAssertEqual(decoded.windowCount, 3)
    }

    // MARK: - JSON Value Tests

    func testJSONValueStringExtraction() {
        let json: JSONValue = .object([
            "name": .string("test"),
            "count": .number(42)
        ])

        XCTAssertEqual(json.stringValue(forKey: "name"), "test")
        XCTAssertNil(json.stringValue(forKey: "missing"))
        XCTAssertEqual(json.intValue(forKey: "count"), 42)
    }

    func testJSONValueCodingRoundTrip() throws {
        let original: JSONValue = .object([
            "string": .string("hello"),
            "number": .number(3.14),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.string("a"), .number(1)]),
            "nested": .object(["key": .string("value")])
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Element Store Tests

    func testElementStoreBasics() async {
        let store = ElementStore()

        // Initially empty
        let count = await store.count()
        XCTAssertEqual(count, 0)

        // Resolve unknown ref returns nil
        let result = await store.resolve("e1")
        XCTAssertNil(result)
    }

    func testElementStoreReset() async {
        let store = ElementStore()
        let count = await store.count()
        XCTAssertEqual(count, 0)

        await store.reset()
        let countAfter = await store.count()
        XCTAssertEqual(countAfter, 0)
    }

    // MARK: - Router Tests

    func testRouterCategorization() {
        let router = Router()

        // Known scriptable
        let finder = router.categorize(bundleID: "com.apple.finder", appName: "Finder")
        XCTAssertEqual(finder, .scriptable)

        // Known Electron
        let discord = router.categorize(bundleID: "com.hnc.Discord", appName: "Discord")
        XCTAssertEqual(discord, .electron)

        // Unknown app
        let unknown = router.categorize(bundleID: "com.example.unknown", appName: "SomeApp")
        XCTAssertTrue(unknown == .unknown || unknown == .nativeStandard)
    }

    func testRouterSnapshotAlwaysAccessibility() {
        let router = Router()

        let method = router.bestMethodForAction(
            action: "snapshot",
            appName: "Finder",
            bundleID: "com.apple.finder"
        )
        XCTAssertEqual(method, .accessibility)
    }

    func testRouterReadAlwaysAccessibility() {
        let router = Router()

        let method = router.bestMethodForAction(
            action: "read",
            appName: "Safari",
            bundleID: "com.apple.Safari"
        )
        XCTAssertEqual(method, .accessibility)
    }

    func testRouterTypingPrefersCGEvent() {
        let router = Router()

        let method = router.bestMethodForAction(
            action: "type",
            appName: "Notes",
            bundleID: "com.apple.Notes"
        )
        XCTAssertEqual(method, .cgevent)
    }

    func testRouterAllMethodsAvailable() {
        let router = Router()

        XCTAssertTrue(router.isAvailable(.accessibility))
        XCTAssertTrue(router.isAvailable(.applescript))
        XCTAssertTrue(router.isAvailable(.cgevent))
        XCTAssertTrue(router.isAvailable(.screenshot))
    }

    // MARK: - App Registry Tests

    func testAppRegistryListApps() {
        let registry = AppRegistry()
        let apps = registry.listApps()

        // Should always find at least a few running apps
        XCTAssertGreaterThan(apps.count, 0)

        // Each app should have a name
        for app in apps {
            XCTAssertFalse(app.name.isEmpty)
            XCTAssertGreaterThan(app.pid, 0)
        }
    }

    func testAppRegistryFrontmostApp() {
        let registry = AppRegistry()
        let frontmost = registry.frontmostApp()

        // Should always have a frontmost app
        XCTAssertNotNil(frontmost)
        XCTAssertFalse(frontmost!.name.isEmpty)
    }

    // MARK: - MCP Protocol Tests

    func testMCPToolResultSuccess() {
        let result = MCPToolResult.success("hello")
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content.count, 1)
        XCTAssertEqual(result.content[0].text, "hello")
    }

    func testMCPToolResultError() {
        let result = MCPToolResult.error("something failed")
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.content[0].text, "something failed")
    }

    func testMCPContentText() {
        let content = MCPContent.text("test")
        XCTAssertEqual(content.type, "text")
        XCTAssertEqual(content.text, "test")
        XCTAssertNil(content.data)
    }

    func testMCPContentImage() {
        let content = MCPContent.image(base64: "abc123", mimeType: "image/png")
        XCTAssertEqual(content.type, "image")
        XCTAssertNil(content.text)
        XCTAssertEqual(content.data, "abc123")
        XCTAssertEqual(content.mimeType, "image/png")
    }

    // MARK: - Tool Handler Tests

    func testToolHandlerListsAllTools() {
        let bridge = AXBridge()
        let store = ElementStore()
        let handler = PilotToolHandler(bridge: bridge, store: store)

        let tools = handler.listTools()
        XCTAssertEqual(tools.count, 10)

        let names = tools.map { $0.name }
        XCTAssertTrue(names.contains("pilot_snapshot"))
        XCTAssertTrue(names.contains("pilot_click"))
        XCTAssertTrue(names.contains("pilot_type"))
        XCTAssertTrue(names.contains("pilot_read"))
        XCTAssertTrue(names.contains("pilot_find"))
        XCTAssertTrue(names.contains("pilot_list_apps"))
        XCTAssertTrue(names.contains("pilot_menu"))
        XCTAssertTrue(names.contains("pilot_script"))
        XCTAssertTrue(names.contains("pilot_screenshot"))
        XCTAssertTrue(names.contains("pilot_batch"))
    }

    func testToolHandlerUnknownTool() async throws {
        let bridge = AXBridge()
        let store = ElementStore()
        let handler = PilotToolHandler(bridge: bridge, store: store)

        let result = try await handler.callTool(name: "nonexistent", arguments: nil)
        XCTAssertTrue(result.isError)
    }

    func testToolHandlerClickMissingRef() async throws {
        let bridge = AXBridge()
        let store = ElementStore()
        let handler = PilotToolHandler(bridge: bridge, store: store)

        let result = try await handler.callTool(name: "pilot_click", arguments: nil)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content[0].text?.contains("Missing") ?? false)
    }

    func testToolHandlerClickUnknownRef() async throws {
        let bridge = AXBridge()
        let store = ElementStore()
        let handler = PilotToolHandler(bridge: bridge, store: store)

        let args: JSONValue = .object(["ref": .string("e999")])
        let result = try await handler.callTool(name: "pilot_click", arguments: args)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content[0].text?.contains("Unknown ref") ?? false)
    }
}
