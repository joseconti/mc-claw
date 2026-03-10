import Foundation
import Testing
@testable import McClawKit

// MARK: - SSH Target Parsing Tests

@Suite("RemoteSSHTarget")
struct RemoteSSHTargetTests {
    @Test("Parse user@host:port")
    func parseFullTarget() {
        let target = RemoteSSHTarget.parse("user@gateway.example.com:2222")
        #expect(target != nil)
        #expect(target?.user == "user")
        #expect(target?.host == "gateway.example.com")
        #expect(target?.port == 2222)
    }

    @Test("Parse user@host")
    func parseUserHost() {
        let target = RemoteSSHTarget.parse("admin@10.0.1.5")
        #expect(target != nil)
        #expect(target?.user == "admin")
        #expect(target?.host == "10.0.1.5")
        #expect(target?.port == nil)
    }

    @Test("Parse host:port")
    func parseHostPort() {
        let target = RemoteSSHTarget.parse("myserver.local:22")
        #expect(target != nil)
        #expect(target?.user == nil)
        #expect(target?.host == "myserver.local")
        #expect(target?.port == 22)
    }

    @Test("Parse host only")
    func parseHostOnly() {
        let target = RemoteSSHTarget.parse("192.168.1.100")
        #expect(target != nil)
        #expect(target?.user == nil)
        #expect(target?.host == "192.168.1.100")
        #expect(target?.port == nil)
    }

    @Test("Parse empty returns nil")
    func parseEmpty() {
        #expect(RemoteSSHTarget.parse("") == nil)
        #expect(RemoteSSHTarget.parse("   ") == nil)
    }

    @Test("Parse trims whitespace")
    func parseTrimmed() {
        let target = RemoteSSHTarget.parse("  user@host  ")
        #expect(target != nil)
        #expect(target?.user == "user")
        #expect(target?.host == "host")
    }

    @Test("Parse invalid port ignored")
    func parseInvalidPort() {
        let target = RemoteSSHTarget.parse("host:abc")
        #expect(target != nil)
        #expect(target?.host == "host:abc")
        #expect(target?.port == nil)
    }

    @Test("Parse port out of range ignored")
    func parsePortOutOfRange() {
        let target = RemoteSSHTarget.parse("host:99999")
        #expect(target != nil)
        #expect(target?.port == nil)
    }

    @Test("Format roundtrip")
    func formatRoundtrip() {
        let target = RemoteSSHTarget(user: "joe", host: "server.com", port: 2222)
        #expect(target.formatted == "joe@server.com:2222")

        let simple = RemoteSSHTarget(host: "localhost")
        #expect(simple.formatted == "localhost")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = RemoteSSHTarget(user: "deploy", host: "prod.example.com", port: 3577)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteSSHTarget.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - URL Validator Tests

@Suite("RemoteURLValidator")
struct RemoteURLValidatorTests {
    @Test("Valid wss URL")
    func validWss() {
        let url = RemoteURLValidator.normalize("wss://gateway.example.com:443/ws")
        #expect(url != nil)
        #expect(url?.scheme == "wss")
        #expect(url?.host == "gateway.example.com")
    }

    @Test("Valid ws loopback")
    func validWsLoopback() {
        let url = RemoteURLValidator.normalize("ws://127.0.0.1:3577/ws")
        #expect(url != nil)
    }

    @Test("ws on non-loopback rejected")
    func wsNonLoopbackRejected() {
        let url = RemoteURLValidator.normalize("ws://remote-host.com:3577/ws")
        #expect(url == nil)
    }

    @Test("http rejected")
    func httpRejected() {
        let url = RemoteURLValidator.normalize("http://example.com:3577/ws")
        #expect(url == nil)
    }

    @Test("Empty host rejected")
    func emptyHostRejected() {
        let url = RemoteURLValidator.normalize("wss:///ws")
        #expect(url == nil)
    }

    @Test("Empty string rejected")
    func emptyStringRejected() {
        #expect(RemoteURLValidator.normalize("") == nil)
        #expect(RemoteURLValidator.normalize("   ") == nil)
    }

    @Test("Default port added for wss")
    func defaultPortWss() {
        let url = RemoteURLValidator.normalize("wss://example.com/ws")
        #expect(url?.port == 443)
    }

    @Test("Default port added for ws")
    func defaultPortWs() {
        let url = RemoteURLValidator.normalize("ws://localhost/ws")
        #expect(url?.port == 3577)
    }

    @Test("Existing port preserved")
    func existingPortPreserved() {
        let url = RemoteURLValidator.normalize("wss://example.com:8443/ws")
        #expect(url?.port == 8443)
    }

    @Test("isLoopback")
    func loopbackCheck() {
        #expect(RemoteURLValidator.isLoopback("127.0.0.1"))
        #expect(RemoteURLValidator.isLoopback("localhost"))
        #expect(RemoteURLValidator.isLoopback("::1"))
        #expect(RemoteURLValidator.isLoopback("LOCALHOST"))
        #expect(!RemoteURLValidator.isLoopback("192.168.1.1"))
        #expect(!RemoteURLValidator.isLoopback("example.com"))
    }

    @Test("Local URL builder")
    func localURL() {
        let url = RemoteURLValidator.localURL(port: 3577)
        #expect(url.absoluteString == "ws://127.0.0.1:3577/ws")
    }

    @Test("Dashboard URL conversion")
    func dashboardURL() {
        let wsURL = URL(string: "ws://127.0.0.1:3577/ws")!
        let dash = RemoteURLValidator.dashboardURL(from: wsURL)
        #expect(dash?.scheme == "http")
        #expect(dash?.path == "/")

        let wssURL = URL(string: "wss://gateway.example.com:443/ws")!
        let sslDash = RemoteURLValidator.dashboardURL(from: wssURL)
        #expect(sslDash?.scheme == "https")
    }
}

// MARK: - Connection Mode Resolver Tests

@Suite("ConnectionModeResolver")
struct ConnectionModeResolverTests {
    @Test("Explicit mode wins")
    func explicitMode() {
        #expect(ConnectionModeResolver.resolve(
            explicitMode: "remote", remoteUrl: nil, remoteTarget: nil, hasCompletedOnboarding: true
        ) == "remote")

        #expect(ConnectionModeResolver.resolve(
            explicitMode: "local", remoteUrl: "wss://x", remoteTarget: "user@host", hasCompletedOnboarding: true
        ) == "local")
    }

    @Test("Remote URL triggers remote")
    func remoteUrlTriggersRemote() {
        #expect(ConnectionModeResolver.resolve(
            explicitMode: nil, remoteUrl: "wss://x.com", remoteTarget: nil, hasCompletedOnboarding: true
        ) == "remote")
    }

    @Test("Remote target triggers remote")
    func remoteTargetTriggersRemote() {
        #expect(ConnectionModeResolver.resolve(
            explicitMode: nil, remoteUrl: nil, remoteTarget: "user@host", hasCompletedOnboarding: true
        ) == "remote")
    }

    @Test("Empty remote values fall to default")
    func emptyRemoteValues() {
        #expect(ConnectionModeResolver.resolve(
            explicitMode: nil, remoteUrl: "", remoteTarget: "  ", hasCompletedOnboarding: true
        ) == "local")
    }

    @Test("No onboarding → unconfigured")
    func noOnboarding() {
        #expect(ConnectionModeResolver.resolve(
            explicitMode: nil, remoteUrl: nil, remoteTarget: nil, hasCompletedOnboarding: false
        ) == "unconfigured")
    }

    @Test("Onboarding done → local")
    func onboardingDone() {
        #expect(ConnectionModeResolver.resolve(
            explicitMode: nil, remoteUrl: nil, remoteTarget: nil, hasCompletedOnboarding: true
        ) == "local")
    }
}

// MARK: - SSH Arguments Builder Tests

@Suite("SSHArgumentsBuilder")
struct SSHArgumentsBuilderTests {
    @Test("Tunnel args basic")
    func tunnelArgsBasic() {
        let target = RemoteSSHTarget(user: "deploy", host: "prod.example.com", port: nil)
        let args = SSHArgumentsBuilder.buildTunnelArgs(
            target: target, identity: nil, localPort: 3577, remotePort: 3577
        )
        #expect(args.contains("-N"))
        #expect(args.contains("-L"))
        #expect(args.contains("3577:127.0.0.1:3577"))
        #expect(args.last == "deploy@prod.example.com")
        #expect(!args.contains("-i"))
        #expect(!args.contains("-p"))
    }

    @Test("Tunnel args with identity and port")
    func tunnelArgsWithIdentityAndPort() {
        let target = RemoteSSHTarget(user: "admin", host: "server", port: 2222)
        let args = SSHArgumentsBuilder.buildTunnelArgs(
            target: target, identity: "~/.ssh/mykey", localPort: 4000, remotePort: 3577
        )
        #expect(args.contains("-i"))
        #expect(args.contains("-p"))
        #expect(args.contains("2222"))
        #expect(args.contains("4000:127.0.0.1:3577"))
    }

    @Test("Tunnel args empty identity skipped")
    func tunnelArgsEmptyIdentity() {
        let target = RemoteSSHTarget(host: "server")
        let args = SSHArgumentsBuilder.buildTunnelArgs(
            target: target, identity: "  ", localPort: 3577, remotePort: 3577
        )
        #expect(!args.contains("-i"))
    }

    @Test("Test args")
    func testArgs() {
        let target = RemoteSSHTarget(user: "me", host: "box", port: nil)
        let args = SSHArgumentsBuilder.buildTestArgs(target: target, identity: nil, timeoutSeconds: 3)
        #expect(args.contains("ConnectTimeout=3"))
        #expect(args.contains("echo"))
        #expect(args.contains("mcclaw-test-ok"))
        #expect(args.last == "mcclaw-test-ok")
    }
}

// MARK: - IPC Frame Header Tests

@Suite("IPCFrameHeaderKit")
struct IPCFrameHeaderKitTests {
    @Test("Encode/decode roundtrip")
    func roundtrip() {
        let header = IPCFrameHeaderKit(length: 12345)
        let decoded = IPCFrameHeaderKit(bytes: header.bytes)
        #expect(decoded.length == 12345)
    }

    @Test("Zero length")
    func zeroLength() {
        let header = IPCFrameHeaderKit(length: 0)
        #expect(header.bytes == [0, 0, 0, 0])
        #expect(IPCFrameHeaderKit(bytes: [0, 0, 0, 0]).length == 0)
    }

    @Test("Max value")
    func maxValue() {
        let header = IPCFrameHeaderKit(length: UInt32.max)
        let decoded = IPCFrameHeaderKit(bytes: header.bytes)
        #expect(decoded.length == UInt32.max)
    }

    @Test("Known bytes")
    func knownBytes() {
        // 256 = 0x00000100
        let header = IPCFrameHeaderKit(length: 256)
        #expect(header.bytes == [0, 0, 1, 0])
    }
}
