import Foundation

/// Output of a finished process.
public struct CommandResult: Sendable, Equatable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data = Data(), stderr: Data = Data()) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

/// Something that can run an executable and collect its output.
/// Abstracted so the remote file logic can be unit-tested with a fake.
public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], stdin: Data?) async throws -> CommandResult
    /// Like `run`, for commands that leave a background child behind (`ssh -f`).
    /// The child may keep inherited pipes open forever, so implementations must not
    /// wait for end-of-file on stdout/stderr — only for the launched process to exit.
    func runDetaching(_ executable: String, _ arguments: [String]) async throws -> CommandResult
}

extension CommandRunning {
    public func runDetaching(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        try await run(executable, arguments, stdin: nil)
    }
}

/// Runs real processes with `Foundation.Process`. Cancelling the calling task terminates the process.
public struct ProcessRunner: CommandRunning {
    public var environment: [String: String]?

    public init(environment: [String: String]? = nil) {
        self.environment = environment
    }

    public func run(_ executable: String, _ arguments: [String], stdin: Data? = nil) async throws -> CommandResult {
        IgnoreSigpipe.once()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe: Pipe?
        if stdin != nil {
            let p = Pipe()
            process.standardInput = p
            inPipe = p
        } else {
            process.standardInput = FileHandle.nullDevice
            inPipe = nil
        }

        let cancelled = Flag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                if cancelled.value { process.terminate() }
                let group = DispatchGroup()
                let out = DataBox()
                let err = DataBox()
                group.enter()
                DispatchQueue.global().async {
                    out.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    err.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                if let inPipe, let stdin {
                    DispatchQueue.global().async {
                        try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
                        try? inPipe.fileHandleForWriting.close()
                    }
                }
                DispatchQueue.global().async {
                    group.wait()
                    process.waitUntilExit()
                    if cancelled.value {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: CommandResult(
                            status: process.terminationStatus, stdout: out.data, stderr: err.data))
                    }
                }
            }
        } onCancel: {
            cancelled.set()
            if process.isRunning { process.terminate() }
        }
    }
}

extension ProcessRunner {
    public func runDetaching(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        // stderr goes to a temporary file instead of a pipe, so a lingering background
        // child can't block us; we read the file once the launched process has exited.
        let errURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("homedrive-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errURL) }
        let errHandle = try FileHandle(forWritingTo: errURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errHandle

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        try? errHandle.close()
        let stderr = (try? Data(contentsOf: errURL)) ?? Data()
        return CommandResult(status: status, stdout: Data(), stderr: stderr)
    }
}

/// Mutable holder used to hand data back from a background queue.
final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Thread-safe one-way boolean.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return _value }
    func set() { lock.lock(); _value = true; lock.unlock() }
}

/// Writing to a pipe whose reader has exited raises SIGPIPE, which would kill the app.
/// We want an EPIPE error instead.
enum IgnoreSigpipe {
    private static let installed: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    static func once() { _ = installed }
}
