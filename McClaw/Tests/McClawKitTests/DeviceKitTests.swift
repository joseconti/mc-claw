import Foundation
import Testing
@testable import McClawKit

// MARK: - QR Payload Tests

@Suite("DeviceKit.QRPayload")
struct QRPayloadTests {
    @Test("Encode and decode roundtrip")
    func encodeDecodeRoundtrip() {
        let payload = DeviceKit.QRPayload(
            gateway: "ws://127.0.0.1:3577/ws",
            gatewayRemote: "wss://gateway.example.com/ws",
            code: "A1B2-C3D4-E5F6",
            expires: 1700000000
        )
        let data = DeviceKit.encodeQRPayload(payload)
        #expect(data != nil)
        let decoded = DeviceKit.decodeQRPayload(data!)
        #expect(decoded != nil)
        #expect(decoded == payload)
    }

    @Test("Encode includes all fields")
    func encodeAllFields() {
        let payload = DeviceKit.QRPayload(
            v: 1,
            gateway: "ws://192.168.1.10:3577/ws",
            gatewayRemote: nil,
            code: "AAAA-BBBB-CCCC",
            expires: 1700000000
        )
        let data = DeviceKit.encodeQRPayload(payload)!
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"v\":1"))
        #expect(json.contains("\"gateway\":"))
        #expect(json.contains("\"code\":\"AAAA-BBBB-CCCC\""))
        #expect(json.contains("\"expires\":1700000000"))
    }

    @Test("Decode with nil gatewayRemote")
    func decodeNilRemote() {
        let json = """
        {"v":1,"gateway":"ws://localhost:3577","code":"1234-5678-ABCD","expires":9999999999}
        """
        let data = json.data(using: .utf8)!
        let payload = DeviceKit.decodeQRPayload(data)
        #expect(payload != nil)
        #expect(payload?.gatewayRemote == nil)
        #expect(payload?.code == "1234-5678-ABCD")
    }

    @Test("Decode invalid JSON returns nil")
    func decodeInvalid() {
        let data = "not json".data(using: .utf8)!
        #expect(DeviceKit.decodeQRPayload(data) == nil)
    }

    @Test("Decode missing fields returns nil")
    func decodeMissingFields() {
        let json = """
        {"v":1,"gateway":"ws://localhost"}
        """
        let data = json.data(using: .utf8)!
        #expect(DeviceKit.decodeQRPayload(data) == nil)
    }
}

// MARK: - Pairing Code Validation Tests

@Suite("DeviceKit.PairingCode")
struct PairingCodeTests {
    @Test("Valid pairing codes")
    func validCodes() {
        #expect(DeviceKit.isValidPairingCode("A1B2-C3D4-E5F6"))
        #expect(DeviceKit.isValidPairingCode("0000-0000-0000"))
        #expect(DeviceKit.isValidPairingCode("FFFF-FFFF-FFFF"))
        #expect(DeviceKit.isValidPairingCode("1234-ABCD-5678"))
    }

    @Test("Invalid pairing codes")
    func invalidCodes() {
        #expect(!DeviceKit.isValidPairingCode(""))
        #expect(!DeviceKit.isValidPairingCode("ABCD-EFGH-IJKL"))  // G, H, I... not hex
        #expect(!DeviceKit.isValidPairingCode("a1b2-c3d4-e5f6"))  // lowercase
        #expect(!DeviceKit.isValidPairingCode("ABCD-1234"))        // too short
        #expect(!DeviceKit.isValidPairingCode("ABCD-1234-5678-9ABC"))  // too long
        #expect(!DeviceKit.isValidPairingCode("ABCD12345678"))     // no dashes
        #expect(!DeviceKit.isValidPairingCode("ABCD 1234 5678"))   // spaces
    }
}

// MARK: - Expiration Tests

@Suite("DeviceKit.Expiration")
struct ExpirationTests {
    @Test("Future timestamp is not expired")
    func futureNotExpired() {
        let future = Int(Date().timeIntervalSince1970) + 3600
        #expect(!DeviceKit.isExpired(timestamp: future))
    }

    @Test("Past timestamp is expired")
    func pastIsExpired() {
        let past = Int(Date().timeIntervalSince1970) - 3600
        #expect(DeviceKit.isExpired(timestamp: past))
    }

    @Test("Zero timestamp is expired")
    func zeroExpired() {
        #expect(DeviceKit.isExpired(timestamp: 0))
    }
}

// MARK: - Permissions Tests

@Suite("DeviceKit.Permissions")
struct PermissionsTests {
    @Test("Default permissions have correct values")
    func defaultPermissions() {
        let defaults = DeviceKit.defaultPermissions()
        #expect(defaults["chat"] == true)
        #expect(defaults["cron.read"] == true)
        #expect(defaults["cron.write"] == true)
        #expect(defaults["channels.read"] == true)
        #expect(defaults["channels.write"] == true)
        #expect(defaults["plugins.read"] == true)
        #expect(defaults["plugins.write"] == true)
        #expect(defaults["exec.approve"] == true)
        #expect(defaults["config.read"] == true)
        #expect(defaults["config.write"] == false)
        #expect(defaults["node.invoke"] == false)
    }

    @Test("Permission keys count matches defaults")
    func keysMatchDefaults() {
        let keys = DeviceKit.permissionKeys()
        let defaults = DeviceKit.defaultPermissions()
        #expect(keys.count == defaults.count)
        for key in keys {
            #expect(defaults[key] != nil, "Missing default for key: \(key)")
        }
    }

    @Test("All keys have labels")
    func allKeysHaveLabels() {
        for key in DeviceKit.permissionKeys() {
            let label = DeviceKit.permissionLabel(for: key)
            #expect(label != key, "Key \(key) should have a human-readable label")
        }
    }

    @Test("All keys have descriptions")
    func allKeysHaveDescriptions() {
        for key in DeviceKit.permissionKeys() {
            let desc = DeviceKit.permissionDescription(for: key)
            #expect(desc != key, "Key \(key) should have a description")
        }
    }

    @Test("Unknown key returns key as label")
    func unknownKeyReturnsKey() {
        #expect(DeviceKit.permissionLabel(for: "unknown.perm") == "unknown.perm")
        #expect(DeviceKit.permissionDescription(for: "unknown.perm") == "unknown.perm")
    }
}

// MARK: - Platform Display Tests

@Suite("DeviceKit.Platform")
struct PlatformTests {
    @Test("Platform display names")
    func displayNames() {
        #expect(DeviceKit.platformDisplayName(.ios) == "iOS")
        #expect(DeviceKit.platformDisplayName(.android) == "Android")
    }
}

// MARK: - Last Seen Tests

@Suite("DeviceKit.LastSeen")
struct LastSeenTests {
    @Test("Just now for recent dates")
    func justNow() {
        let now = Date()
        let text = DeviceKit.lastSeenText(from: now, now: now)
        #expect(text == "Just now")
    }

    @Test("Minutes ago")
    func minutesAgo() {
        let now = Date()
        let fiveMinAgo = now.addingTimeInterval(-300)
        let text = DeviceKit.lastSeenText(from: fiveMinAgo, now: now)
        #expect(text == "5m ago")
    }

    @Test("Hours ago")
    func hoursAgo() {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-7200)
        let text = DeviceKit.lastSeenText(from: twoHoursAgo, now: now)
        #expect(text == "2h ago")
    }

    @Test("Yesterday")
    func yesterday() {
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-86400)
        let text = DeviceKit.lastSeenText(from: oneDayAgo, now: now)
        #expect(text == "Yesterday")
    }

    @Test("Days ago")
    func daysAgo() {
        let now = Date()
        let threeDaysAgo = now.addingTimeInterval(-259200)
        let text = DeviceKit.lastSeenText(from: threeDaysAgo, now: now)
        #expect(text == "3d ago")
    }
}
