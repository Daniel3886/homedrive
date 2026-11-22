import Foundation

/// Facts about the Linux PC, gathered once when connecting.
public struct RemoteSystemInfo: Equatable, Sendable {
    public var home: String
    public var hostname: String
    public var os: String
    /// Existing standard folders (Desktop, Documents, ...) as absolute paths.
    public var places: [String]
    /// `gio trash` is available, so deletes can go to the desktop Trash.
    public var supportsTrash: Bool
    public var diskTotalBytes: Int64?
    public var diskFreeBytes: Int64?

    public init(home: String = "", hostname: String = "", os: String = "", places: [String] = [],
                supportsTrash: Bool = false, diskTotalBytes: Int64? = nil, diskFreeBytes: Int64? = nil) {
        self.home = home
        self.hostname = hostname
        self.os = os
        self.places = places
        self.supportsTrash = supportsTrash
        self.diskTotalBytes = diskTotalBytes
        self.diskFreeBytes = diskFreeBytes
    }

    public static func parse(_ text: String) -> RemoteSystemInfo {
        var info = RemoteSystemInfo()
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let key = f.first, f.count >= 2 else { continue }
            switch key {
            case "home": info.home = f[1]
            case "host": info.hostname = f[1]
            case "os": info.os = f[1]
            case "trash": info.supportsTrash = f[1] == "1"
            case "place": if !info.places.contains(f[1]) { info.places.append(f[1]) }
            case "disk" where f.count >= 3:
                info.diskTotalBytes = Int64(f[1]).map { $0 * 1024 }
                info.diskFreeBytes = Int64(f[2]).map { $0 * 1024 }
            default: break
            }
        }
        return info
    }
}

/// All file operations on the Linux PC, each one an `ssh host sh -c '<script>' ...` call.
public struct RemoteFileService: Sendable {
    public var builder: SSHCommandBuilder
    public var runner: CommandRunning

    public init(builder: SSHCommandBuilder, runner: CommandRunning = ProcessRunner()) {
        self.builder = builder
        self.runner = runner
    }

    // MARK: Connection

    /// Opens the shared master connection (if multiplexing is on) and reads system info.
    public func connect() async throws -> RemoteSystemInfo {
        guard builder.settings.isConfigured else { throw HomeDriveError.notConfigured }
        if builder.settings.useMultiplexing {
            let check = try await runner.run(builder.sshExecutable, builder.checkMaster(), stdin: nil)
            if check.status != 0 {
                let start = try await runner.runDetaching(builder.sshExecutable, builder.startMaster())
                if start.status != 0 {
                    throw HomeDriveError.connectionFailed(start.stderrString)
                }
            }
        }
        return try await probe()
    }

    /// Closes the shared master connection, if any.
    public func disconnect() async {
        guard builder.settings.useMultiplexing, builder.settings.isConfigured else { return }
        _ = try? await runner.run(builder.sshExecutable, builder.stopMaster(), stdin: nil)
    }

    public func probe() async throws -> RemoteSystemInfo {
        let result = try await exec(RemoteScripts.probe)
        return RemoteSystemInfo.parse(result.stdoutString)
    }

    // MARK: Browsing

    public func list(_ path: String) async throws -> [FileEntry] {
        let result = try await exec(RemoteScripts.list, [path])
        return ListingParser.parse(result.stdout, parent: path).sorted(by: FileEntry.finderOrder)
    }

    /// Which of `names` already exist inside `folder`.
    public func existingNames(_ names: [String], in folder: String) async throws -> Set<String> {
        guard !names.isEmpty else { return [] }
        let result = try await exec(RemoteScripts.existing, [folder] + names)
        let found = result.stdout.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        return Set(found)
    }

    /// Approximate total size (bytes) of the given paths, for progress bars.
    public func diskUsage(_ paths: [String]) async throws -> Int64 {
        guard !paths.isEmpty else { return 0 }
        let result = try await exec(RemoteScripts.diskUsage, paths)
        let kib = Int64(result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return kib * 1024
    }

    // MARK: Changing things

    public func makeDirectory(named name: String, in folder: String) async throws {
        guard RemotePath.isValidName(name) else { throw HomeDriveError.invalidName(name) }
        try await exec(RemoteScripts.makeDirectory, [RemotePath.join(folder, name)])
    }

    public func rename(_ path: String, to newName: String) async throws {
        guard RemotePath.isValidName(newName) else { throw HomeDriveError.invalidName(newName) }
        let target = RemotePath.join(RemotePath.parent(path), newName)
        guard target != path else { return }
        try await exec(RemoteScripts.rename, [path, target])
    }

    /// Moves items to the Linux desktop Trash (`gio trash`).
    public func trash(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await exec(RemoteScripts.trash, paths)
    }

    /// Deletes items permanently.
    public func delete(_ paths: [String]) async throws {
        let safe = paths.filter { RemotePath.normalize($0) != "/" && !$0.isEmpty }
        guard !safe.isEmpty else { return }
        try await exec(RemoteScripts.delete, safe)
    }

    // MARK: Plumbing

    /// Runs one of `RemoteScripts` with positional arguments, mapping failures to `HomeDriveError`.
    @discardableResult
    public func exec(_ script: String, _ arguments: [String] = []) async throws -> CommandResult {
        guard builder.settings.isConfigured else { throw HomeDriveError.notConfigured }
        let commandLine = Shell.script(script, arguments: arguments)
        let result = try await runner.run(builder.sshExecutable, builder.remoteCommand(commandLine), stdin: nil)
        try Self.check(result)
        return result
    }

    static func check(_ result: CommandResult) throws {
        switch result.status {
        case 0: return
        case 255: throw HomeDriveError.connectionFailed(result.stderrString)
        default:
            throw HomeDriveError.commandFailed(
                status: result.status,
                message: result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
