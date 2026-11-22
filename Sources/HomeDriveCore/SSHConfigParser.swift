import Foundation

/// A `Host` block from `~/.ssh/config`.
public struct SSHHostAlias: Equatable, Hashable, Sendable, Identifiable {
    public var alias: String
    public var hostName: String?
    public var user: String?
    public var port: Int?

    public var id: String { alias }

    public init(alias: String, hostName: String? = nil, user: String? = nil, port: Int? = nil) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.port = port
    }

    /// e.g. `diamondeyes@10.77.0.1`
    public var summary: String {
        var s = hostName ?? alias
        if let user { s = "\(user)@\(s)" }
        if let port { s += ":\(port)" }
        return s
    }
}

/// Minimal reader for `~/.ssh/config`, used to offer the user's existing host aliases.
/// It doesn't need to understand everything: ssh itself still reads the real config.
public enum SSHConfigParser {
    public static func parse(_ text: String) -> [SSHHostAlias] {
        var result: [SSHHostAlias] = []
        var current: [SSHHostAlias] = []

        func flush() {
            for alias in current where !result.contains(where: { $0.alias == alias.alias }) {
                result.append(alias)
            }
            current = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let (key, value) = splitKeyValue(line)
            switch key.lowercased() {
            case "host":
                flush()
                current = value.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                    .filter { !$0.contains("*") && !$0.contains("?") && !$0.hasPrefix("!") }
                    .map { SSHHostAlias(alias: $0) }
            case "match":
                flush()
            case "hostname":
                for i in current.indices where current[i].hostName == nil { current[i].hostName = value }
            case "user":
                for i in current.indices where current[i].user == nil { current[i].user = value }
            case "port":
                for i in current.indices where current[i].port == nil { current[i].port = Int(value) }
            default:
                break
            }
        }
        flush()
        return result
    }

    public static func loadDefault() -> [SSHHostAlias] {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh/config")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Splits `Key value`, `Key=value` and `Key = value`.
    static func splitKeyValue(_ line: String) -> (String, String) {
        guard let sep = line.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "=" }) else {
            return (line, "")
        }
        let key = String(line[..<sep])
        var rest = line[sep...].drop(while: { $0 == " " || $0 == "\t" })
        if rest.first == "=" { rest = rest.dropFirst().drop(while: { $0 == " " || $0 == "\t" }) }
        return (key, String(rest).trimmingCharacters(in: .whitespaces))
    }
}
