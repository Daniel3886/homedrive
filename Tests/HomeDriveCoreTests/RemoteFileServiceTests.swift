import Foundation
import Testing
@testable import HomeDriveCore

@Suite struct RemoteFileServiceTests {
    private func service(_ runner: FakeRunner, multiplex: Bool = true) -> RemoteFileService {
        var s = ConnectionSettings(host: "ubuntu-home")
        s.useMultiplexing = multiplex
        return RemoteFileService(builder: SSHCommandBuilder(settings: s, controlPath: "/tmp/cp"), runner: runner)
    }

    @Test func passesUserValuesOnlyAsQuotedArguments() async throws {
        let runner = FakeRunner()
        try await service(runner).makeDirectory(named: "$(reboot)", in: "/home/me")
        let line = try #require(runner.lastCommandLine)
        #expect(line.hasPrefix("sh -c '"))
        #expect(line.hasSuffix(" sh '/home/me/$(reboot)'"))
    }

    @Test func exit255IsAConnectionError() async {
        let runner = FakeRunner { _ in CommandResult(status: 255, stderr: Data("Operation timed out".utf8)) }
        await #expect(throws: HomeDriveError.connectionFailed("Operation timed out")) {
            _ = try await service(runner).list("/")
        }
    }

    @Test func otherFailuresCarryStderr() async {
        let runner = FakeRunner { _ in CommandResult(status: 3, stderr: Data("No such folder: /x\n".utf8)) }
        await #expect(throws: HomeDriveError.commandFailed(status: 3, message: "No such folder: /x")) {
            _ = try await service(runner).list("/x")
        }
    }

    @Test func listParsesAndSorts() async throws {
        let out = "ff\t1\t0\t644\tzeta.txt\0dd\t0\t0\t755\tAlpha\0ff\t1\t0\t644\talpha.txt\0"
        let runner = FakeRunner { _ in CommandResult(status: 0, stdout: Data(out.utf8)) }
        let entries = try await service(runner).list("/home/me")
        #expect(entries.map(\.name) == ["Alpha", "alpha.txt", "zeta.txt"])
    }

    @Test func connectStartsMasterOnlyWhenNeeded() async throws {
        let runner = FakeRunner { args in
            if args.contains("check") { return CommandResult(status: 255) }   // no master yet
            return CommandResult(status: 0, stdout: Data("home\t/home/me\n".utf8))
        }
        let info = try await service(runner).connect()
        #expect(info.home == "/home/me")
        #expect(runner.calls.count == 3)        // check, start master, probe
        #expect(runner.calls[1].contains("-M"))
    }

    @Test func connectWithoutMultiplexingJustProbes() async throws {
        let runner = FakeRunner { _ in CommandResult(status: 0, stdout: Data("home\t/root\n".utf8)) }
        _ = try await service(runner, multiplex: false).connect()
        #expect(runner.calls.count == 1)
    }

    @Test func failedMasterStartIsReported() async {
        let runner = FakeRunner { args in
            CommandResult(status: 255, stderr: Data("Permission denied (publickey).".utf8))
        }
        await #expect(throws: HomeDriveError.connectionFailed("Permission denied (publickey).")) {
            _ = try await service(runner).connect()
        }
    }

    @Test func refusesToDeleteRoot() async throws {
        let runner = FakeRunner()
        try await service(runner).delete(["/", "//", ""])
        #expect(runner.calls.isEmpty)
    }

    @Test func rejectsInvalidNames() async {
        let runner = FakeRunner()
        await #expect(throws: HomeDriveError.invalidName("a/b")) {
            try await service(runner).rename("/home/me/x", to: "a/b")
        }
        #expect(runner.calls.isEmpty)
    }

    @Test func notConfigured() async {
        let s = RemoteFileService(builder: SSHCommandBuilder(settings: ConnectionSettings()), runner: FakeRunner())
        await #expect(throws: HomeDriveError.notConfigured) { _ = try await s.connect() }
    }

    @Test func settingsStoreRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "homedrive-tests-\(UUID().uuidString)"))
        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == ConnectionSettings())
        let s = ConnectionSettings(host: "ubuntu-home", port: 22, remoteStartPath: "/home/me/Documents")
        store.save(s)
        #expect(store.load() == s)
    }
}
