import Foundation

/// Helpers for building POSIX shell command lines safely.
///
/// Every remote operation is sent to the Linux PC as `sh -c '<script>' sh <args...>`.
/// The script is a fixed string we wrote; user-controlled values (paths, file names)
/// are only ever passed as positional arguments, each one single-quoted. That way a
/// file called `$(rm -rf ~)` is just a file name, never code.
public enum Shell {
    private static let safeCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:,+@%"
    )

    /// Quotes `value` so a POSIX shell reads it back as exactly one word.
    public static func quote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Builds `sh -c '<script>' sh 'arg1' 'arg2' ...`.
    ///
    /// Using an explicit `sh` keeps behaviour identical regardless of the remote
    /// user's login shell (bash, zsh, fish, ...).
    public static func script(_ script: String, arguments: [String] = []) -> String {
        (["sh", "-c", quote(script), "sh"] + arguments.map(quote)).joined(separator: " ")
    }
}
