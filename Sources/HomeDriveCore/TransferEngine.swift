import Foundation

/// Copies files and folders between this Mac and the Linux PC.
///
/// Each transfer is a tar stream piped through SSH, with HomeDrive in the middle of the pipe:
///
///     upload:    tar -c (Mac)  ──▶ HomeDrive ──▶ ssh pc 'tar -x'
///     download:  ssh pc 'tar -c' ──▶ HomeDrive ──▶ tar -x (Mac)
///
/// Sitting in the middle lets us count bytes for the progress bar and stop both sides on cancel.
/// tar keeps folders, permissions and timestamps, and needs nothing extra installed on the PC.
/// Both directions extract into a hidden staging folder first and only move the item into
/// place once it is complete.
public struct TransferEngine: Sendable {
    public typealias Progress = @Sendable (_ bytesTransferred: Int64) -> Void

    public var builder: SSHCommandBuilder
    public var tarExecutable: String

    public init(builder: SSHCommandBuilder, tarExecutable: String = "/usr/bin/tar") {
        self.builder = builder
        self.tarExecutable = tarExecutable
    }

    /// Uploads the file or folder at `localURL` into `remoteFolder`.
    public func upload(_ localURL: URL, toRemoteFolder remoteFolder: String,
                       replaceExisting: Bool, progress: @escaping Progress) async throws {
        guard builder.settings.isConfigured else { throw HomeDriveError.notConfigured }
        let name = localURL.lastPathComponent
        guard RemotePath.isValidName(name) else { throw HomeDriveError.invalidName(name) }

        var tarArgs = ["-c", "-f", "-"]
        var env = ProcessInfo.processInfo.environment
        #if os(macOS)
        // Don't send macOS resource forks / extended attributes (._foo files) to Linux.
        tarArgs += ["--no-mac-metadata", "--no-xattrs"]
        env["COPYFILE_DISABLE"] = "1"
        #endif
        tarArgs += ["-C", localURL.deletingLastPathComponent().path, "./" + name]

        let remote = Shell.script(RemoteScripts.tarExtract,
                                  arguments: [remoteFolder, name, replaceExisting ? "1" : "0"])
        let producer = PipeEndpoint(executable: tarExecutable, arguments: tarArgs, environment: env)
        let consumer = PipeEndpoint(executable: builder.sshExecutable, arguments: builder.remoteCommand(remote))

        let result = try await PipeTransfer.run(producer: producer, consumer: consumer, progress: progress)
        try Self.check(result, sshSide: .consumer, name: name)
    }

    /// Downloads `remotePath` (file or folder) into the local folder `localFolder`.
    public func download(_ remotePath: String, toLocalFolder localFolder: URL,
                         replaceExisting: Bool, progress: @escaping Progress) async throws {
        guard builder.settings.isConfigured else { throw HomeDriveError.notConfigured }
        let name = RemotePath.name(remotePath)
        guard RemotePath.isValidName(name) else { throw HomeDriveError.invalidName(name) }
        let fm = FileManager.default
        let finalURL = localFolder.appendingPathComponent(name)
        if !replaceExisting, fm.fileExists(atPath: finalURL.path) || isSymlink(finalURL) {
            throw HomeDriveError.alreadyExists(name)
        }

        try fm.createDirectory(at: localFolder, withIntermediateDirectories: true)
        let stage = localFolder.appendingPathComponent(".homedrive-partial-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }

        let remote = Shell.script(RemoteScripts.tarCreate, arguments: [RemotePath.parent(remotePath), name])
        let producer = PipeEndpoint(executable: builder.sshExecutable, arguments: builder.remoteCommand(remote))
        let consumer = PipeEndpoint(executable: tarExecutable, arguments: ["-x", "-f", "-", "-C", stage.path])

        let result = try await PipeTransfer.run(producer: producer, consumer: consumer, progress: progress)
        try Self.check(result, sshSide: .producer, name: name)

        let staged = stage.appendingPathComponent(name)
        guard fm.fileExists(atPath: staged.path) || isSymlink(staged) else {
            throw HomeDriveError.commandFailed(status: 1, message: "“\(name)” wasn't received.")
        }
        if fm.fileExists(atPath: finalURL.path) || isSymlink(finalURL) {
            guard replaceExisting else { throw HomeDriveError.alreadyExists(name) }
            try fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: staged, to: finalURL)
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    enum Side { case producer, consumer }

    static func check(_ result: PipeTransfer.Result, sshSide: Side, name: String) throws {
        let ssh = sshSide == .producer ? result.producer : result.consumer
        let tar = sshSide == .producer ? result.consumer : result.producer
        if ssh.status == 255 { throw HomeDriveError.connectionFailed(ssh.stderrString) }
        if ssh.status == 17 { throw HomeDriveError.alreadyExists(name) }
        for side in [ssh, tar] where side.status != 0 {
            let message = side.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HomeDriveError.commandFailed(
                status: side.status,
                message: message.isEmpty ? "Transfer of “\(name)” failed (exit \(side.status))." : message)
        }
    }
}

/// One side of a pipe: an executable and its arguments.
public struct PipeEndpoint: Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]?

    public init(executable: String, arguments: [String], environment: [String: String]? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

/// Runs `producer | consumer`, copying the bytes through this process so they can be counted.
public enum PipeTransfer {
    public struct Result: Sendable {
        public var producer: CommandResult
        public var consumer: CommandResult
        public var bytes: Int64
    }

    static let chunkSize = 256 * 1024
    static let progressInterval: TimeInterval = 0.1

    public static func run(producer: PipeEndpoint, consumer: PipeEndpoint,
                           progress: @escaping @Sendable (Int64) -> Void) async throws -> Result {
        IgnoreSigpipe.once()
        let p = makeProcess(producer)
        let c = makeProcess(consumer)
        let pOut = Pipe(), pErr = Pipe(), cIn = Pipe(), cErr = Pipe()
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = pOut
        p.standardError = pErr
        c.standardInput = cIn
        c.standardOutput = FileHandle.nullDevice
        c.standardError = cErr

        let cancelled = Flag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                do {
                    try c.run()
                    do { try p.run() } catch {
                        c.terminate()
                        throw error
                    }
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                if cancelled.value { p.terminate(); c.terminate() }

                let pErrBox = DataBox(), cErrBox = DataBox()
                let group = DispatchGroup()
                for (pipe, box) in [(pErr, pErrBox), (cErr, cErrBox)] {
                    group.enter()
                    DispatchQueue.global().async {
                        box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                }

                // The pump: a dedicated thread, since it blocks on reads for the whole transfer.
                let thread = Thread {
                    var total: Int64 = 0
                    var lastReport = Date.distantPast
                    let reader = pOut.fileHandleForReading
                    let writer = cIn.fileHandleForWriting
                    while true {
                        let chunk: Data
                        do {
                            guard let d = try reader.read(upToCount: chunkSize), !d.isEmpty else { break }
                            chunk = d
                        } catch { break }
                        do {
                            try writer.write(contentsOf: chunk)
                        } catch {
                            // Consumer went away (EPIPE). Stop the producer too.
                            p.terminate()
                            break
                        }
                        total += Int64(chunk.count)
                        let now = Date()
                        if now.timeIntervalSince(lastReport) >= progressInterval {
                            lastReport = now
                            progress(total)
                        }
                    }
                    try? writer.close()
                    try? reader.close()
                    p.waitUntilExit()
                    c.waitUntilExit()
                    group.wait()
                    progress(total)
                    if cancelled.value {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    continuation.resume(returning: Result(
                        producer: CommandResult(status: p.terminationStatus, stderr: pErrBox.data),
                        consumer: CommandResult(status: c.terminationStatus, stderr: cErrBox.data),
                        bytes: total))
                }
                thread.name = "HomeDrive transfer"
                thread.start()
            }
        } onCancel: {
            cancelled.set()
            if p.isRunning { p.terminate() }
            if c.isRunning { c.terminate() }
        }
    }

    private static func makeProcess(_ endpoint: PipeEndpoint) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: endpoint.executable)
        process.arguments = endpoint.arguments
        if let env = endpoint.environment { process.environment = env }
        return process
    }
}
