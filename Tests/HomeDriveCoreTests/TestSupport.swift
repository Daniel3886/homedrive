import Foundation
@testable import HomeDriveCore

/// Records calls and returns canned results.
final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    var handler: @Sendable ([String]) -> CommandResult

    init(handler: @escaping @Sendable ([String]) -> CommandResult = { _ in CommandResult(status: 0) }) {
        self.handler = handler
    }

    func run(_ executable: String, _ arguments: [String], stdin: Data?) async throws -> CommandResult {
        lock.lock(); calls.append(arguments); lock.unlock()
        return handler(arguments)
    }

    var lastCommandLine: String? { lock.lock(); defer { lock.unlock() }; return calls.last?.last }
}

/// A temporary folder removed at deinit.
final class TempDir {
    let url: URL
    var path: String { url.path }

    init() throws {
        // Resolve symlinks (/var -> /private/var on macOS) so paths compare equal.
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
        url = base.appendingPathComponent("homedrive-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ relative: String, _ contents: String = "hello") throws -> URL {
        let u = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let u = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func read(_ relative: String) throws -> String {
        try String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relative).path)
    }

    func children(_ relative: String = "") throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent(relative).path).sorted()
    }
}

/// A stand-in for `/usr/bin/ssh` that runs the remote command on this machine.
///
/// It ignores all options and the destination and runs the final argument with /bin/sh,
/// exactly as sshd would hand it to the remote login shell. So the integration tests run
/// the real scripts, real tar and real pipes; only the network hop is skipped.
enum FakeSSH {
    static func install(in dir: TempDir, exitCode: Int32? = nil, stderr: String = "") throws -> String {
        let script: String
        if let exitCode {
            script = """
            #!/bin/sh
            printf '%s\\n' \(Shell.quote(stderr)) >&2
            exit \(exitCode)
            """
        } else {
            script = """
            #!/bin/sh
            for last; do :; done
            case " $* " in *" -O "*|*" -M "*) exit 0 ;; esac
            exec /bin/sh -c "$last"
            """
        }
        let url = dir.url.appendingPathComponent("fake-ssh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
}

/// Thread-safe progress recorder.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64] = []
    func record(_ v: Int64) { lock.lock(); values.append(v); lock.unlock() }
    var all: [Int64] { lock.lock(); defer { lock.unlock() }; return values }
}
