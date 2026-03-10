import Foundation

/// WebSocket protocol frame types.
public enum WSFrameType: String, Codable, Sendable {
    case request
    case response
    case event
}

/// WebSocket request frame.
public struct WSRequest: Codable, Sendable {
    public let seq: Int
    public let method: String
    public let params: [String: AnyCodableValue]?

    public init(seq: Int, method: String, params: [String: AnyCodableValue]? = nil) {
        self.seq = seq
        self.method = method
        self.params = params
    }
}

/// WebSocket response frame.
public struct WSResponse: Codable, Sendable {
    public let seq: Int
    public let ok: Bool
    public let result: AnyCodableValue?
    public let error: WSError?

    public init(seq: Int, ok: Bool, result: AnyCodableValue? = nil, error: WSError? = nil) {
        self.seq = seq
        self.ok = ok
        self.result = result
        self.error = error
    }
}

/// WebSocket event frame (push from Gateway).
public struct WSEvent: Codable, Sendable {
    public let event: String
    public let data: [String: AnyCodableValue]?

    public init(event: String, data: [String: AnyCodableValue]? = nil) {
        self.event = event
        self.data = data
    }
}

/// WebSocket error.
public struct WSError: Codable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// Type-erased Codable value for JSON interop.
public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode AnyCodableValue"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
