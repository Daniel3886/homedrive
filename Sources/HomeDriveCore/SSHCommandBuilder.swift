import Foundation

/// Builds argument lists for the system `ssh` binary.
///
/// HomeDrive deliberately drives `/usr/bin/ssh` instead of embedding an SSH library:
/// it reuses your `~/.ssh/config`, keys, agent and `known_hosts` exactly as the terminal does.
public struct SSHCommandBuilder: Sendable {
    public var settings: ConnectionSettings
    public var sshExecutable: String
    /// Unix socket used for connection sharing (`ControlPath`). `%C` is a hash of the
    /// connection parameters, so different hosts never share a socket.
    public var controlPath: String

    public init(
        settings: ConnectionSettings,
        sshExecutable: String = "/usr/bin/ssh",
        controlPath: String = SSHCommandBuilder.defaultControlPath
    ) {
        self.settings = settings
        self.sshExecutable = sshExecutable
        self.controlPath = controlPath
    }

    /// Kept short on purpose: Unix socket paths are limited to ~104 bytes on macOS.
    public static var defaultControlPath: String {
        NSHomeDirectory() + "/.ssh/homedrive-%C"
    }

    /// Options shared by every invocation.
    ///
    /// - Parameter includeMultiplexing: when `false`, connection-sharing options are left
    ///   out so the caller can add its own (used when starting the master connection).
    public func commonOptions(includeMultiplexing: Bool = true) -> [String] {
        var args: [String] = [
            // A GUI can't answer password / passphrase prompts; fail fast instead of hanging.
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(max(1, settings.connectTimeout))",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
        ]
        if settings.acceptNewHostKeys {
            args += ["-o", "StrictHostKeyChecking=accept-new"]
        }
        if let port = settings.port {
            args += ["-p", String(port)]
        }
        let identity = settings.identityFile.trimmingCharacters(in: .whitespaces)
        if !identity.isEmpty {
            args += ["-i", (identity as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"]
        }
        if includeMultiplexing && settings.useMultiplexing {
            // Use a master connection if one is running, but never become one implicitly:
            // an implicit ControlPersist master inherits our pipes and keeps them open.
            args += ["-o", "ControlMaster=no", "-o", "ControlPath=\(controlPath)"]
        }
        return args
    }

    /// Arguments to run one remote shell command line (already quoted).
    public func remoteCommand(_ commandLine: String) -> [String] {
        // `-T`: no pseudo-terminal, so binary data (tar streams) passes through untouched.
        commonOptions() + ["-T", "--", settings.destination, commandLine]
    }

    /// Arguments to start a background master connection (`ssh -M -N -f`).
    /// Later commands then reuse it instead of doing a fresh SSH handshake each time.
    public func startMaster(persistSeconds: Int = 600) -> [String] {
        commonOptions(includeMultiplexing: false) + [
            "-o", "ControlMaster=yes",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=\(persistSeconds)",
            "-M", "-N", "-f", "--", settings.destination,
        ]
    }

    /// Arguments to ask a running master connection to exit.
    public func stopMaster() -> [String] {
        // Port and user must match the master's: they are part of the %C socket hash.
        commonOptions(includeMultiplexing: false)
            + ["-o", "ControlPath=\(controlPath)", "-O", "exit", "--", settings.destination]
    }

    /// Arguments to check whether a master connection is running.
    public func checkMaster() -> [String] {
        commonOptions(includeMultiplexing: false)
            + ["-o", "ControlPath=\(controlPath)", "-O", "check", "--", settings.destination]
    }
}
