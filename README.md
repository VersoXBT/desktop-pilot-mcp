<div align="center">

[![Stars](https://img.shields.io/github/stars/VersoXBT/desktop-pilot-mcp?style=flat-square&logo=github&label=Stars)](https://github.com/VersoXBT/desktop-pilot-mcp)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange?style=flat-square&logo=swift)](https://swift.org)
[![MCP Server](https://img.shields.io/badge/MCP-Server-blueviolet?style=flat-square)]()
[![macOS](https://img.shields.io/badge/macOS-native-black?style=flat-square&logo=apple)]()
[![Speed](https://img.shields.io/badge/Speed-30--100x%20faster-brightgreen?style=flat-square)]()

</div>

<p align="center">
  <h1 align="center">Desktop Pilot MCP</h1>
  <p align="center">Native macOS automation for Claude. 30-100x faster than screenshots.</p>
</p>

<p align="center">
  <a href="#"><img alt="Version" src="https://img.shields.io/badge/version-1.0.0-blue.svg" /></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg" /></a>
  <a href="#"><img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg" /></a>
  <a href="#"><img alt="Swift 6" src="https://img.shields.io/badge/swift-6.0-orange.svg" /></a>
  <a href="#"><img alt="Tests" src="https://img.shields.io/badge/tests-22%20passing-brightgreen.svg" /></a>
  <a href="#"><img alt="Binary Size" src="https://img.shields.io/badge/binary-427KB-purple.svg" /></a>
  <a href="#"><img alt="Dependencies" src="https://img.shields.io/badge/dependencies-0-blue.svg" /></a>
</p>

---

Desktop Pilot is an MCP server that gives Claude direct access to any macOS application through the Accessibility API, AppleScript, and CGEvent -- no screenshots, no pixel coordinates, no vision model overhead. It reads the actual UI tree and acts on semantic element references, the same way Playwright works for browsers.

**One snapshot of Telegram takes 20ms and returns structured data. The same operation with screenshot-based computer-use takes ~3 seconds and returns pixels.**

```
pilot_snapshot { "app": "Telegram" }

[e1] Window "Saved Messages"
  [e2] MenuButton "Main menu"
  [e3] Button "All chats (111 unread chats)"
  [e7] Button "Code (4 unread chats)"
  [e18] TextField "Write a message..."
  [e20] Button "Record Voice Message"

pilot_click { "ref": "e18" }       // focus the text field
pilot_type  { "ref": "e18", "text": "Hello from Claude" }
pilot_click { "ref": "e20" }       // send
```

No coordinates. No screenshots. No guessing. Just refs.

---

## Quick Start (2 minutes)

```bash
npx desktop-pilot-mcp
```

**Step 1.** Add to your Claude config and restart Claude:

For **Claude Code**, add to `~/.claude.json` under your project's `mcpServers`:

```json
{
  "desktop-pilot": {
    "command": "npx",
    "args": ["-y", "desktop-pilot-mcp"]
  }
}
```

For **Claude Desktop**, add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "desktop-pilot": {
      "command": "npx",
      "args": ["-y", "desktop-pilot-mcp"]
    }
  }
}
```

**Step 2.** Grant Accessibility permission when macOS prompts you (one-time).

If the prompt doesn't appear: **System Settings > Privacy & Security > Accessibility** -- add your terminal app or Claude Desktop.

**Step 3.** Ask Claude to interact with any app:

> "Take a snapshot of Telegram and show me what's on screen"

That's it. No API keys, no accounts, no configuration files.

<details>
<summary>Alternative: build from source</summary>

Requires Swift 6.0+ (included with Xcode 16+).

```bash
git clone https://github.com/VersoXBT/desktop-pilot-mcp.git
cd desktop-pilot-mcp
swift build -c release
```

Then use the binary path directly in your Claude config:

```json
{
  "desktop-pilot": {
    "command": "/absolute/path/to/desktop-pilot-mcp/.build/release/desktop-pilot-mcp",
    "args": []
  }
}
```

</details>

---

## Benchmarks

Real measurements from testing against Telegram, Finder, and other macOS apps:

| Operation | computer-use (screenshots) | Desktop Pilot | Speedup |
|-----------|---------------------------|---------------|---------|
| Snapshot (read full UI tree) | ~3000ms | 20ms | **150x** |
| Snapshot (Finder, 45 elements) | ~3000ms | 78ms | **38x** |
| Click element | ~3000ms | ~50ms | **60x** |
| Read element value | ~3000ms | <1ms | **3000x** |
| Find buttons by role | ~3000ms | 4ms | **750x** |
| Type text | ~4000ms | ~20ms | **200x** |
| Full flow (click + type + send) | ~14s | ~450ms | **30x** |

Screenshot-based approaches (computer-use, etc.) pay the cost of a full screen capture, a vision model call, and coordinate calculation on every single operation. Desktop Pilot reads and acts on the live UI tree directly.

---

## How It Works

Desktop Pilot uses four interaction layers with a smart router that picks the fastest method for each app and action:

```
                         +-------------------+
                         |   Smart Router    |
                         | (per-app + per-   |
                         |  action routing)  |
                         +--------+----------+
                                  |
                  +-------+-------+-------+--------+
                  |       |               |        |
           +------+--+ +--+------+ +-----+---+ +--+--------+
           |AppleScript| |  AX   | | CGEvent | |Screenshot |
           | Layer    | | Layer  | |  Layer  | |  Layer    |
           +----------+ +--------+ +---------+ +-----------+
           Priority: 20  Pri: 0    Pri: 40     Pri: 50
           Scriptable   Universal  Raw input   Fallback
           apps only    all apps   injection   (vision)
```

**Layer 1 -- Accessibility API** (priority 0, universal)
Reads the structured UI tree of any macOS app. Every button, text field, menu item, and label is exposed as a node with a semantic ref ID. This is the primary layer for reading state, clicking, and finding elements.

**Layer 2 -- AppleScript / System Events** (priority 20, scriptable apps)
Deep scripting for apps with AppleScript dictionaries (Finder, Safari, Mail, Keynote, Music, etc.). The router detects scriptable apps via `sdef` and routes script-based operations here automatically.

**Layer 3 -- CGEvent** (priority 40, input injection)
Ultra-fast keyboard and mouse input at 1-5ms latency. Used for typing text (more reliable than AXSetValue for most apps), keyboard shortcuts, mouse clicks at coordinates, and drag operations.

**Layer 4 -- Screenshot** (priority 50, last resort)
Captures screen regions or specific element bounds as base64 PNG. Only used when Accessibility can't see the content -- game viewports, canvas elements, custom-rendered UI.

The **Smart Router** classifies each app (scriptable, Electron, native, unknown) and picks the optimal layer per action:

| Action | Scriptable apps | Electron apps | Native apps |
|--------|----------------|---------------|-------------|
| Snapshot / Read / Find | Accessibility | Accessibility | Accessibility |
| Click | Accessibility | Accessibility | Accessibility |
| Type | CGEvent | Accessibility | CGEvent |
| Script | AppleScript | Accessibility | Accessibility |
| Menu | Accessibility | Accessibility | Accessibility |

---

## Comparison

| Feature | Desktop Pilot | computer-use (built-in) | Playwright MCP | adamrdrew/macos-accessibility-mcp | steipete/macos-automator-mcp |
|---------|:------------:|:-----------------------:|:--------------:|:---------------------------------:|:----------------------------:|
| Speed | 20-100ms | 2-5s | 50-200ms | ~200ms | ~500ms |
| Native macOS apps | Yes | Yes | No | Yes | Yes |
| Web apps / browsers | Yes | Yes | Yes | No | No |
| Electron apps | Yes | Yes | Yes | Partial | No |
| Accessibility API | Yes | No | No | Yes | No |
| AppleScript integration | Yes | No | No | No | Yes |
| CGEvent (raw input) | Yes | No | No | No | No |
| Screenshot fallback | Yes | Yes (primary) | Yes | No | No |
| Smart layer routing | Yes | No | No | No | No |
| Semantic element refs | Yes | No | Yes | Basic | No |
| Batch operations | Yes | No | No | No | No |
| Menu bar navigation | Yes | No | No | No | Via script |
| Zero dependencies | Yes | N/A | Node.js | Node.js | Node.js |
| Binary size | 427KB | N/A | ~50MB+ | ~30MB+ | ~30MB+ |

---

## Tool Reference

Desktop Pilot exposes 10 tools through the MCP protocol. All tools use the `pilot_` prefix.

### `pilot_snapshot`

Get a structured snapshot of an app's UI element tree. This is the starting point for any interaction -- it returns every visible element with a ref ID you can pass to other tools.

```json
{ "app": "Telegram" }
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `app` | string | No | App name or bundle ID. Omit for frontmost app. |
| `maxDepth` | integer | No | Maximum tree depth to traverse (default 10). |

Returns a tree of elements, each with a `ref` (e.g. `e1`, `e2`), role, title, value, enabled/focused state, and bounding rectangle.

---

### `pilot_click`

Click a UI element by its ref ID. Works with buttons, checkboxes, menu items, and any clickable element.

```json
{ "ref": "e5" }
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ref` | string | Yes | Element reference ID from a snapshot. |

---

### `pilot_type`

Type text into a text field, search box, or any editable element. Focuses the element first, then inserts the text.

```json
{ "ref": "e18", "text": "Hello from Claude" }
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ref` | string | Yes | Element reference ID from a snapshot. |
| `text` | string | Yes | Text to type into the element. |

---

### `pilot_read`

Read the current value, title, role, and description of a UI element. Use to check text field contents, checkbox state, or label text.

```json
{ "ref": "e3" }
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ref` | string | Yes | Element reference ID from a snapshot. |

---

### `pilot_find`

Search for UI elements matching criteria across an app's UI tree. Faster than a full snapshot when you know what you're looking for.

```json
{ "role": "AXButton", "title": "Save", "app": "Finder" }
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `role` | string | No | AX role to match (e.g. `AXButton`, `AXTextField`). |
| `title` | string | No | Title/label substring, case-insensitive. |
| `value` | string | No | Value substring to match. |
| `app` | string | No | Limit search to this app. Omit for frontmost. |

---

### `pilot_menu`

Activate a menu bar item by path. Traverses the app's menu bar hierarchy directly.

```json
{ "path": "File > Save As...", "app": "TextEdit" }
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | Yes | Menu path with ` > ` separator. |
| `app` | string | No | App name or bundle ID. Omit for frontmost. |

---

### `pilot_script`

Run AppleScript or JXA (JavaScript for Automation) code targeting a specific app.

```json
{
  "app": "Finder",
  "code": "tell application \"Finder\" to get name of every window",
  "language": "applescript"
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `app` | string | Yes | Target app name. |
| `code` | string | Yes | AppleScript or JXA code to execute. |
| `language` | string | No | `applescript` (default) or `jxa`. |

---

### `pilot_screenshot`

Capture a screenshot of a specific element or the full screen. Returns base64 PNG. Use sparingly -- `pilot_snapshot` is usually better for understanding UI state.

```json
{ "ref": "e1" }
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ref` | string | No | Element ref to screenshot. Omit for full screen. |

---

### `pilot_batch`

Execute multiple tool calls in sequence within a single MCP round-trip. Use to reduce latency when performing multi-step actions.

```json
{
  "actions": [
    { "tool": "pilot_click", "params": { "ref": "e18" } },
    { "tool": "pilot_type",  "params": { "ref": "e18", "text": "Hello" } },
    { "tool": "pilot_click", "params": { "ref": "e20" } }
  ]
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `actions` | array | Yes | Array of `{ tool, params }` objects to execute in order. |

---

### `pilot_list_apps`

List all running macOS applications with their names, bundle IDs, PIDs, and window counts. Use to discover available apps before taking a snapshot.

```json
{}
```

No parameters required.

---

## Architecture

```
Sources/
  DesktopPilot/
    Core/
      AppRegistry.swift     # App discovery via NSWorkspace
      ElementStore.swift    # Actor-based ref-to-element mapping
      Router.swift          # Smart per-app, per-action routing
      Snapshot.swift        # Batch AX tree traversal
    Layers/
      LayerProtocol.swift   # InteractionLayer protocol
      AccessibilityLayer.swift  # AXUIElement tree reading + actions
      AppleScriptLayer.swift    # System Events + sdef scripting
      CGEventLayer.swift        # Raw keyboard/mouse injection
      ScreenshotLayer.swift     # Screen capture fallback
    MCP/
      Server.swift          # JSON-RPC 2.0 with Content-Length framing
      Tools.swift           # 10 tool definitions + dispatch
      Types.swift           # PilotElement, AppSnapshot, AppInfo
    Platform/
      PlatformProtocol.swift    # Cross-platform bridge interface
      macOS/
        AXBridge.swift          # Low-level AXUIElement C API wrapper
        Permissions.swift       # Accessibility permission management
        SystemEvents.swift      # AppleScript/JXA execution helper
  DesktopPilotCLI/
    main.swift              # Entry point: permission check + server start
Tests/
  DesktopPilotTests/
    DesktopPilotTests.swift # 22 tests: types, router, registry, MCP, tools
```

**Key design decisions:**

- **Zero dependencies.** The entire server is built on Apple frameworks only (ApplicationServices, AppKit, CoreGraphics). No SwiftNIO, no Vapor, no third-party JSON library. This keeps the binary at 427KB.
- **Actor-based element store.** Refs are ephemeral -- they reset on each snapshot. The `ElementStore` actor guarantees thread-safe access to the AXUIElement-to-ref mapping across concurrent tool calls.
- **Content-Length framing.** The MCP server uses the standard JSON-RPC 2.0 protocol with `Content-Length` header framing over stdin/stdout, matching the MCP specification exactly.
- **Batch attribute reading.** Instead of N individual AXUIElementCopyAttributeValue calls per element, the snapshot builder uses `AXUIElementCopyMultipleAttributeValues` to read 6 attributes in a single call. This is why snapshots are fast.

---

## Supported Apps

Desktop Pilot works with any macOS application that exposes an accessibility tree (which is virtually all of them):

| Category | Examples | Primary Layer |
|----------|----------|---------------|
| Apple native | Finder, Safari, Mail, Notes, Calendar, Music | AppleScript + Accessibility |
| Productivity | Microsoft Office, Google Chrome, Firefox | Accessibility |
| Electron | VS Code, Discord, Slack, Spotify, Signal | Accessibility |
| Creative | Final Cut Pro, Logic Pro, Xcode | AppleScript + Accessibility |
| Communication | Telegram, iMessage, WhatsApp | Accessibility |
| System | System Settings, Activity Monitor, Terminal | Accessibility |

---

## Use Cases

- **Automate any macOS workflow** -- file management, app configuration, data entry across apps
- **Build AI agents** that operate native desktop applications Claude can't reach through web APIs
- **Test macOS apps** by driving the UI through structured element refs instead of fragile pixel coordinates
- **Cross-app orchestration** -- copy data from one app, process it, paste into another, all in a single Claude session
- **Accessibility auditing** -- inspect the full UI tree of any app to verify accessibility compliance

---

## Troubleshooting

**"Accessibility permission not granted"**
Open System Settings > Privacy & Security > Accessibility and add the binary or your terminal app. Restart the MCP server after granting.

**"Failed to capture screenshot"**
Grant Screen Recording permission in System Settings > Privacy & Security > Screen Recording. Required only for `pilot_screenshot`.

**Stale refs (`Unknown ref 'e5'`)**
Refs reset on every `pilot_snapshot` call. Always take a fresh snapshot before interacting with elements. If an app's UI has changed since the last snapshot, the old refs are invalid.

**Electron apps not responding to `pilot_type`**
Some Electron apps (VS Code, Discord) swallow raw key events. The router handles this by using Accessibility (AXSetValue) instead of CGEvent for Electron apps. If typing still fails, try `pilot_script` with a System Events keystroke.

**Empty snapshots**
The app may not have any open windows, or it may use a non-standard UI framework (games, OpenGL/Metal renderers). Use `pilot_screenshot` as a fallback for custom-rendered content.

---

## Development

```bash
# Build debug
swift build

# Build release
swift build -c release

# Run tests
swift test

# Run the server directly
swift run desktop-pilot-mcp
```

The project is split into a library target (`DesktopPilot`) and an executable target (`DesktopPilotCLI`) for testability. All core logic lives in the library; the CLI is a thin entry point.

---

## License

MIT

## Contributors

<!-- ALL-CONTRIBUTORS-LIST:START -->
<table>
  <tr>
    <td align="center"><a href="https://github.com/VersoXBT"><img src="https://avatars.githubusercontent.com/u/202813801?v=4" width="80px;" alt=""/><br /><sub><b>VersoXBT</b></sub></a><br />💻 📖</td>
    <td align="center"><a href="https://github.com/claude"><img src="https://avatars.githubusercontent.com/u/81847?v=4" width="80px;" alt=""/><br /><sub><b>Claude</b></sub></a><br />🤖 💡</td>
  </tr>
</table>
<!-- ALL-CONTRIBUTORS-LIST:END -->
