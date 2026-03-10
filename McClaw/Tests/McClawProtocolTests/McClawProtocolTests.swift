import Testing
import Foundation
@testable import McClawProtocol

@Suite("McClaw Protocol Tests")
struct McClawProtocolTests {
    @Test("Protocol version is 3")
    func protocolVersion() {
        #expect(mcclawProtocolVersion == 3)
    }

    @Test("All gateway methods have values")
    func gatewayMethods() {
        for method in GatewayMethod.allCases {
            #expect(!method.rawValue.isEmpty)
        }
    }
}

@Suite("WSRequest Encoding/Decoding")
struct WSRequestTests {
    @Test("Encode request without params")
    func encodeWithoutParams() throws {
        let request = WSRequest(seq: 1, method: "hello")
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["seq"] as? Int == 1)
        #expect(json["method"] as? String == "hello")
    }

    @Test("Encode request with params")
    func encodeWithParams() throws {
        let request = WSRequest(seq: 2, method: "agent.send", params: [
            "message": .string("hello"),
            "model": .string("claude-3"),
        ])
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(WSRequest.self, from: data)
        #expect(decoded.seq == 2)
        #expect(decoded.method == "agent.send")
        #expect(decoded.params?["message"] == .string("hello"))
        #expect(decoded.params?["model"] == .string("claude-3"))
    }

    @Test("Roundtrip request preserves data")
    func roundtrip() throws {
        let original = WSRequest(seq: 42, method: "chat.history", params: [
            "limit": .int(50),
            "offset": .int(0),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WSRequest.self, from: data)
        #expect(decoded.seq == original.seq)
        #expect(decoded.method == original.method)
        #expect(decoded.params?["limit"] == .int(50))
    }
}

@Suite("WSResponse Encoding/Decoding")
struct WSResponseTests {
    @Test("Decode successful response")
    func decodeSuccess() throws {
        let json = #"{"seq":1,"ok":true,"result":"connected"}"#
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(WSResponse.self, from: data)
        #expect(response.seq == 1)
        #expect(response.ok == true)
        #expect(response.result == .string("connected"))
        #expect(response.error == nil)
    }

    @Test("Decode error response")
    func decodeError() throws {
        let json = #"{"seq":2,"ok":false,"error":{"code":404,"message":"Not found"}}"#
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(WSResponse.self, from: data)
        #expect(response.seq == 2)
        #expect(response.ok == false)
        #expect(response.error?.code == 404)
        #expect(response.error?.message == "Not found")
    }

    @Test("Encode response roundtrip")
    func roundtrip() throws {
        let original = WSResponse(seq: 5, ok: true, result: .dictionary([
            "status": .string("ok"),
            "count": .int(3),
        ]))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WSResponse.self, from: data)
        #expect(decoded.seq == 5)
        #expect(decoded.ok == true)
        #expect(decoded.result == .dictionary(["status": .string("ok"), "count": .int(3)]))
    }
}

@Suite("WSEvent Encoding/Decoding")
struct WSEventTests {
    @Test("Decode chat message event")
    func decodeChatMessage() throws {
        let json = #"{"event":"chat.message","data":{"text":"Hello","sessionId":"main"}}"#
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(WSEvent.self, from: data)
        #expect(event.event == "chat.message")
        #expect(event.data?["text"] == .string("Hello"))
        #expect(event.data?["sessionId"] == .string("main"))
    }

    @Test("Decode event without data")
    func decodeNoData() throws {
        let json = #"{"event":"agent.idle"}"#
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(WSEvent.self, from: data)
        #expect(event.event == "agent.idle")
        #expect(event.data == nil)
    }

    @Test("Encode event roundtrip")
    func roundtrip() throws {
        let original = WSEvent(event: "health.update", data: [
            "uptime": .double(3600.5),
            "connections": .int(2),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WSEvent.self, from: data)
        #expect(decoded.event == "health.update")
        #expect(decoded.data?["uptime"] == .double(3600.5))
        #expect(decoded.data?["connections"] == .int(2))
    }
}

@Suite("AnyCodableValue Encoding/Decoding")
struct AnyCodableValueTests {
    @Test("String value roundtrip")
    func stringValue() throws {
        let value = AnyCodableValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded == .string("hello"))
    }

    @Test("Int value roundtrip")
    func intValue() throws {
        let value = AnyCodableValue.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded == .int(42))
    }

    @Test("Bool value roundtrip")
    func boolValue() throws {
        let value = AnyCodableValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded == .bool(true))
    }

    @Test("Null value roundtrip")
    func nullValue() throws {
        let value = AnyCodableValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded == .null)
    }

    @Test("Array value roundtrip")
    func arrayValue() throws {
        let value = AnyCodableValue.array([.string("a"), .int(1), .bool(false)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded == .array([.string("a"), .int(1), .bool(false)]))
    }

    @Test("Dictionary value roundtrip")
    func dictionaryValue() throws {
        let value = AnyCodableValue.dictionary(["key": .string("val"), "num": .int(5)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded == .dictionary(["key": .string("val"), "num": .int(5)]))
    }

    @Test("Nested structures roundtrip")
    func nestedValue() throws {
        let value = AnyCodableValue.dictionary([
            "name": .string("test"),
            "items": .array([.int(1), .int(2)]),
            "meta": .dictionary(["active": .bool(true)]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Decode from raw JSON string")
    func decodeFromRawJSON() throws {
        let json = #"{"name":"test","count":3,"active":true,"tags":["a","b"]}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        if case .dictionary(let dict) = decoded {
            #expect(dict["name"] == .string("test"))
            #expect(dict["count"] == .int(3))
            #expect(dict["active"] == .bool(true))
            #expect(dict["tags"] == .array([.string("a"), .string("b")]))
        } else {
            Issue.record("Expected dictionary")
        }
    }
}
