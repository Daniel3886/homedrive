import Foundation

/// Everything needed to reach the Linux PC over SSH.
///
/// The simplest setup is to put the PC in `~/.ssh/config` (for example `Host ubuntu-home`)
/// and set `host` to that alias; user, port and key then come from the SSH config.
public struct ConnectionSettings: Codable, Equatable, Sendable {
    /// A `~/.ssh/config` alias, a hostname (e.g. `pc.example.com`) or an IP (e.g. `10.77.0.1`).
    public var host: String
    /// Optional user name. Empty means "whatever SSH would use" (config or local user).
    public var user: String
    /// Optional port. `nil` means the SSH default / config value.
    public var port: Int?
    /// Optional private key path. Empty means SSH decides (config / agent / default keys).
    public var identityFile: String
    /// Seconds to wait for the TCP connection before giving up.
    public var connectTimeout: Int
    /// Reuse one SSH connection for all operations (much faster folder browsing).
    public var useMultiplexing: Bool
    /// Trust a host key the first time we see it (`StrictHostKeyChecking=accept-new`).
    /// Changed keys are still rejected.
    public var acceptNewHostKeys: Bool
    /// Remote folder shown after connecting. Empty means the remote home folder.
    public var remoteStartPath: String
    /// Local folder shown in the Mac pane at launch. Empty means `~/Downloads`.
    public var localStartPath: String

    public init(
        host: String = "",
        user: String = "",
        port: Int? = nil,
        identityFile: String = "",
        connectTimeout: Int = 8,
        useMultiplexing: Bool = true,
        acceptNewHostKeys: Bool = true,
        remoteStartPath: String = "",
        localStartPath: String = ""
    ) {
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.connectTimeout = connectTimeout
        self.useMultiplexing = useMultiplexing
        self.acceptNewHostKeys = acceptNewHostKeys
        self.remoteStartPath = remoteStartPath
        self.localStartPath = localStartPath
    }

    public var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// `user@host` or just `host`.
    public var destination: String {
        let h = host.trimmingCharacters(in: .whitespaces)
        let u = user.trimmingCharacters(in: .whitespaces)
        return u.isEmpty ? h : "\(u)@\(h)"
    }

    // Tolerate settings saved by older versions that lack newer keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ConnectionSettings()
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? d.host
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? d.user
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        identityFile = try c.decodeIfPresent(String.self, forKey: .identityFile) ?? d.identityFile
        connectTimeout = try c.decodeIfPresent(Int.self, forKey: .connectTimeout) ?? d.connectTimeout
        useMultiplexing = try c.decodeIfPresent(Bool.self, forKey: .useMultiplexing) ?? d.useMultiplexing
        acceptNewHostKeys = try c.decodeIfPresent(Bool.self, forKey: .acceptNewHostKeys) ?? d.acceptNewHostKeys
        remoteStartPath = try c.decodeIfPresent(String.self, forKey: .remoteStartPath) ?? d.remoteStartPath
        localStartPath = try c.decodeIfPresent(String.self, forKey: .localStartPath) ?? d.localStartPath
    }
}

/// Persists `ConnectionSettings` as JSON in `UserDefaults`.
public struct SettingsStore {
    public let defaults: UserDefaults
    public let key: String

    public init(defaults: UserDefaults = .standard, key: String = "connectionSettings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ConnectionSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ConnectionSettings.self, from: data)
        else { return ConnectionSettings() }
        return settings
    }

    public func save(_ settings: ConnectionSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
