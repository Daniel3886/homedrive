import Foundation

public enum HomeDriveError: LocalizedError, Equatable {
    case notConfigured
    /// SSH itself failed (exit 255): network, VPN, DNS, auth or host-key problems.
    case connectionFailed(String)
    /// A remote or local command ran but failed.
    case commandFailed(status: Int32, message: String)
    case alreadyExists(String)
    case invalidName(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No Linux PC is set up yet. Open Settings and enter its SSH host."
        case .connectionFailed(let message):
            return "Couldn't reach the Linux PC. \(Self.friendlySSHHint(message))"
        case .commandFailed(_, let message):
            return message.isEmpty ? "The operation failed." : message
        case .alreadyExists(let name):
            return "“\(name)” already exists."
        case .invalidName(let name):
            return "“\(name)” isn't a valid name."
        }
    }

    /// Turns raw ssh stderr into a hint a human can act on.
    public static func friendlySSHHint(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let hint: String
        if lower.contains("timed out") || lower.contains("no route to host") || lower.contains("network is unreachable") {
            hint = "Is WireGuard connected and the PC turned on?"
        } else if lower.contains("could not resolve hostname") {
            hint = "The host name couldn't be resolved. Check the host in Settings (or your DuckDNS name)."
        } else if lower.contains("connection refused") {
            hint = "The PC is reachable but SSH isn't accepting connections. Is sshd running?"
        } else if lower.contains("permission denied") {
            hint = "SSH key login was rejected. HomeDrive needs key-based login (no password prompts)."
        } else if lower.contains("host key verification failed") || lower.contains("remote host identification has changed") {
            hint = "The PC's host key doesn't match ~/.ssh/known_hosts. Connect once in Terminal to check it."
        } else {
            hint = ""
        }
        if text.isEmpty { return hint }
        return hint.isEmpty ? text : "\(hint)\n\n\(text)"
    }
}
