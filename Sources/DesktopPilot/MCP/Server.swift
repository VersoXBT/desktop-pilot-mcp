import Foundation

// MARK: - JSON Value

/// A flexible JSON value type for handling arbitrary MCP params.
enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
            return
        }
        if let intVal = try? container.decode(Int.self) {
            self = .number(Double(intVal))
            return
        }
        if let doubleVal = try? container.decode(Double.self) {
            self = .number(doubleVal)
            return
        }
        if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
            return
        }
        if let arrVal = try? container.decode([JSONValue].self) {
            self = .array(arrVal)
            return
        }
        if let objVal = try? container.decode([String: JSONValue].self) {
            self = .object(objVal)
            return
        }

        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Cannot decode JSONValue"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val):
            try container.encode(val)
        case .number(let val):
            try container.encode(val)
        case .bool(let val):
            try container.encode(val)
        case .null:
            try container.encodeNil()
        case .array(let val):
            try container.encode(val)
        case .object(let val):
            try container.encode(val)
        }
    }

    /// Extract a string value for the given key (object only).
    func stringValue(forKey key: String) -> String? {
        guard case .object(let dict) = self,
              case .string(let val) = dict[key] else {
            return nil
        }
        return val
    }

    /// Extract an integer value for the given key (object only).
    func intValue(forKey key: String) -> Int? {
        guard case .object(let dict) = self,
              case .number(let val) = dict[key] else {
            return nil
        }
        return Int(val)
    }

    /// Return the underlying dictionary if this is an object.
    var objectValue: [String: JSONValue]? {
        guard case .object(let dict) = self else { return nil }
        return dict
    }
}

// MARK: - JSON-RPC Types

/// Flexible request ID that can be Int or String.
enum RequestID: Codable, Sendable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
            return
        }
        if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
            return
        }
        throw DecodingError.typeMismatch(
            RequestID.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Request ID must be Int or String"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let val):
            try container.encode(val)
        case .string(let val):
            try container.encode(val)
        }
    }
}

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: RequestID?
    let method: String
    let params: JSONValue?
}

struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: RequestID?
    let result: JSONValue?
    let error: JSONRPCError?

    init(id: RequestID?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: RequestID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct JSONRPCError: Codable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?

    init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)")
    }

    static func invalidParams(_ detail: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: "Invalid params: \(detail)")
    }

    static func internalError(_ detail: String) -> JSONRPCError {
        JSONRPCError(code: -32603, message: "Internal error: \(detail)")
    }

    static let parseError = JSONRPCError(code: -32700, message: "Parse error")
}

// MARK: - MCP Content Types

/// A content block returned by a tool call.
struct MCPContent: Codable, Sendable {
    let type: String
    let text: String?
    let data: String?
    let mimeType: String?

    static func text(_ value: String) -> MCPContent {
        MCPContent(type: "text", text: value, data: nil, mimeType: nil)
    }

    static func image(base64 data: String, mimeType: String) -> MCPContent {
        MCPContent(type: "image", text: nil, data: data, mimeType: mimeType)
    }
}

/// The result envelope for a tools/call response.
struct MCPToolResult: Sendable {
    let content: [MCPContent]
    let isError: Bool

    static func success(_ text: String) -> MCPToolResult {
        MCPToolResult(content: [.text(text)], isError: false)
    }

    static func error(_ text: String) -> MCPToolResult {
        MCPToolResult(content: [.text(text)], isError: true)
    }

    func toJSONValue() -> JSONValue {
        let contentArray: [JSONValue] = content.map { item in
            var dict: [String: JSONValue] = ["type": .string(item.type)]
            if let text = item.text {
                dict["text"] = .string(text)
            }
            if let data = item.data {
                dict["data"] = .string(data)
            }
            if let mimeType = item.mimeType {
                dict["mimeType"] = .string(mimeType)
            }
            return .object(dict)
        }
        return .object([
            "content": .array(contentArray),
            "isError": .bool(isError)
        ])
    }
}

// MARK: - Tool Handler Protocol

/// Protocol for handling MCP tool calls.
protocol ToolHandler: Sendable {
    /// Return all tool definitions for tools/list.
    func listTools() -> [ToolDefinition]

    /// Handle a tool call and return the result.
    func callTool(name: String, arguments: JSONValue?) async throws -> MCPToolResult
}

/// A tool definition with name, description, and JSON Schema for inputs.
struct ToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    func toJSONValue() -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema
        ])
    }
}

// MARK: - Logger

/// Logs messages to stderr so stdout stays clean for MCP protocol.
enum Log {
    static func info(_ message: String) {
        write("[INFO] \(message)")
    }

    static func error(_ message: String) {
        write("[ERROR] \(message)")
    }

    static func debug(_ message: String) {
        write("[DEBUG] \(message)")
    }

    private static func write(_ message: String) {
        let line = message + "\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

// MARK: - MCP Server

/// MCP server that communicates over stdin/stdout using JSON-RPC with
/// Content-Length framing.
final class MCPServer: Sendable {
    private let toolHandler: ToolHandler
    private let serverName: String
    private let serverVersion: String

    init(
        toolHandler: ToolHandler,
        serverName: String = "desktop-pilot-mcp",
        serverVersion: String = "0.1.0"
    ) {
        self.toolHandler = toolHandler
        self.serverName = serverName
        self.serverVersion = serverVersion
    }

    /// Start the server and process messages from stdin until EOF.
    func run() async {
        Log.info("Starting \(serverName) v\(serverVersion)")

        let stdin = FileHandle.standardInput

        var buffer = Data()

        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                Log.info("stdin closed, shutting down")
                break
            }

            buffer.append(chunk)

            while let (messageData, remainder) = extractMessage(from: buffer) {
                buffer = remainder
                await processMessage(messageData)
            }
        }
    }

    // MARK: - Message Framing

    /// Extract one complete message from the buffer if a full Content-Length
    /// framed message is available.
    /// Returns the message body data and the remaining buffer, or nil.
    private func extractMessage(from buffer: Data) -> (Data, Data)? {
        guard let headerEnd = findHeaderEnd(in: buffer) else {
            return nil
        }

        let headerData = buffer[buffer.startIndex..<headerEnd]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        guard let contentLength = parseContentLength(from: headerString) else {
            Log.error("Missing Content-Length in header: \(headerString)")
            return nil
        }

        let bodyStart = headerEnd + 4 // skip \r\n\r\n
        let bodyEnd = bodyStart + contentLength

        guard buffer.count >= bodyEnd else {
            return nil
        }

        let body = buffer[bodyStart..<bodyEnd]
        let remainder = buffer[bodyEnd...]

        return (Data(body), Data(remainder))
    }

    /// Find the position of \r\n\r\n in the data.
    private func findHeaderEnd(in data: Data) -> Int? {
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        let bytes = [UInt8](data)

        guard bytes.count >= 4 else { return nil }

        for i in 0...(bytes.count - 4) {
            if bytes[i] == separator[0]
                && bytes[i + 1] == separator[1]
                && bytes[i + 2] == separator[2]
                && bytes[i + 3] == separator[3]
            {
                return i
            }
        }

        return nil
    }

    /// Parse "Content-Length: N" from the header string.
    private func parseContentLength(from header: String) -> Int? {
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length",
               let length = Int(parts[1].trimmingCharacters(in: .whitespaces))
            {
                return length
            }
        }
        return nil
    }

    // MARK: - Message Processing

    private func processMessage(_ data: Data) async {
        let decoder = JSONDecoder()

        let request: JSONRPCRequest
        do {
            request = try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            Log.error("Failed to parse JSON-RPC request: \(error)")
            sendResponse(JSONRPCResponse(id: nil, error: .parseError))
            return
        }

        Log.debug("Received method: \(request.method)")

        // Notifications (no id) don't get a response
        if request.id == nil {
            handleNotification(request)
            return
        }

        let response = await handleRequest(request)
        sendResponse(response)
    }

    private func handleNotification(_ request: JSONRPCRequest) {
        switch request.method {
        case "notifications/initialized":
            Log.info("Client initialized")
        default:
            Log.debug("Unhandled notification: \(request.method)")
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(request)
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return await handleToolsCall(request)
        case "ping":
            return JSONRPCResponse(id: request.id, result: .object([:]))
        default:
            return JSONRPCResponse(
                id: request.id,
                error: .methodNotFound(request.method)
            )
        }
    }

    // MARK: - Method Handlers

    private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
        Log.info("Handling initialize")

        let result: JSONValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([
                "tools": .object([:])
            ]),
            "serverInfo": .object([
                "name": .string(serverName),
                "version": .string(serverVersion)
            ])
        ])

        return JSONRPCResponse(id: request.id, result: result)
    }

    private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let tools = toolHandler.listTools()
        let toolsJSON: [JSONValue] = tools.map { $0.toJSONValue() }

        let result: JSONValue = .object([
            "tools": .array(toolsJSON)
        ])

        return JSONRPCResponse(id: request.id, result: result)
    }

    private func handleToolsCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let params = request.params,
              let name = params.stringValue(forKey: "name") else {
            return JSONRPCResponse(
                id: request.id,
                error: .invalidParams("Missing 'name' in tools/call params")
            )
        }

        let arguments: JSONValue?
        if case .object(let paramsDict) = params {
            arguments = paramsDict["arguments"]
        } else {
            arguments = nil
        }

        do {
            let result = try await toolHandler.callTool(name: name, arguments: arguments)
            return JSONRPCResponse(id: request.id, result: result.toJSONValue())
        } catch {
            Log.error("Tool '\(name)' failed: \(error)")
            let errorResult = MCPToolResult.error("Tool execution failed: \(error)")
            return JSONRPCResponse(id: request.id, result: errorResult.toJSONValue())
        }
    }

    // MARK: - Response Writing

    private func sendResponse(_ response: JSONRPCResponse) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(response)
            let header = "Content-Length: \(data.count)\r\n\r\n"

            guard let headerData = header.data(using: .utf8) else {
                Log.error("Failed to encode response header")
                return
            }

            FileHandle.standardOutput.write(headerData)
            FileHandle.standardOutput.write(data)
        } catch {
            Log.error("Failed to encode response: \(error)")
        }
    }
}
