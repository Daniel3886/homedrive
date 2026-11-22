import Foundation
import Testing
@testable import HomeDriveCore

@Suite struct SSHCommandBuilderTests {
    @Test func destination() {
        #expect(ConnectionSettings(host: "ubuntu-home").destination == "ubuntu-home")
        #expect(ConnectionSettings(host: " pc.duckdns.org ", user: "me").destination == "me@pc.duckdns.org")
    }

    @Test func remoteCommandEndsWithDestinationAndCommand() {
        let b = SSHCommandBuilder(settings: ConnectionSettings(host: "ubuntu-home"), controlPath: "/tmp/cp-%C")
        let args = b.remoteCommand("echo hi")
        #expect(Array(args.suffix(4)) == ["-T", "--", "ubuntu-home", "echo hi"])
        #expect(args.contains("BatchMode=yes"))
        #expect(args.contains("ControlMaster=no"))
        #expect(args.contains("ControlPath=/tmp/cp-%C"))
        #expect(args.contains("StrictHostKeyChecking=accept-new"))
    }

    @Test func portIdentityAndOptionalFeatures() {
        var s = ConnectionSettings(host: "h", port: 2222, identityFile: "/k/id_ed25519")
        s.useMultiplexing = false
        s.acceptNewHostKeys = false
        s.connectTimeout = 3
        let args = SSHCommandBuilder(settings: s).remoteCommand("true")
        #expect(args.contains("ConnectTimeout=3"))
        let p = args.firstIndex(of: "-p")!
        #expect(args[p + 1] == "2222")
        let i = args.firstIndex(of: "-i")!
        #expect(args[i + 1] == "/k/id_ed25519")
        #expect(args.contains("IdentitiesOnly=yes"))
        #expect(!args.contains { $0.hasPrefix("ControlMaster") || $0.hasPrefix("ControlPath") })
        #expect(!args.contains("StrictHostKeyChecking=accept-new"))
    }

    @Test func masterCommands() {
        let s = ConnectionSettings(host: "h", port: 2222)
        let b = SSHCommandBuilder(settings: s, controlPath: "/tmp/cp-%C")
        let start = b.startMaster(persistSeconds: 30)
        #expect(start.contains("ControlMaster=yes"))
        #expect(!start.contains("ControlMaster=no"))
        #expect(start.contains("ControlPersist=30"))
        #expect(Array(start.suffix(5)) == ["-M", "-N", "-f", "--", "h"])
        // The port is part of the socket hash, so control commands must pass it too.
        #expect(b.stopMaster().contains("2222"))
        #expect(Array(b.stopMaster().suffix(4)) == ["-O", "exit", "--", "h"])
        #expect(Array(b.checkMaster().suffix(4)) == ["-O", "check", "--", "h"])
    }

    @Test func settingsCodableIsBackwardCompatible() throws {
        let old = #"{"host":"ubuntu-home","user":""}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(ConnectionSettings.self, from: old)
        #expect(s.host == "ubuntu-home")
        #expect(s.useMultiplexing)
        #expect(s.connectTimeout == 8)
    }
}
