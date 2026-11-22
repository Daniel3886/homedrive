import Foundation

/// Pure string helpers for POSIX paths on the Linux side.
/// (We never touch remote paths with `URL`/`FileManager`, which would resolve them on the Mac.)
public enum RemotePath {
    /// Joins a folder and a child name: `join("/home/me", "a b")` → `/home/me/a b`.
    public static func join(_ parent: String, _ name: String) -> String {
        if parent.isEmpty { return name }
        if parent.hasSuffix("/") { return parent + name }
        return parent + "/" + name
    }

    /// Removes duplicate and trailing slashes and resolves `.` / `..` lexically.
    public static func normalize(_ path: String) -> String {
        let absolute = path.hasPrefix("/")
        var parts: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..":
                if let last = parts.last, last != ".." { parts.removeLast() }
                else if !absolute { parts.append("..") }
            default: parts.append(String(part))
            }
        }
        let joined = parts.joined(separator: "/")
        if absolute { return "/" + joined }
        return joined.isEmpty ? "." : joined
    }

    /// Parent folder: `parent("/home/me/docs")` → `/home/me`; the parent of `/` is `/`.
    public static func parent(_ path: String) -> String {
        let p = normalize(path)
        if p == "/" { return "/" }
        guard let slash = p.lastIndex(of: "/") else { return "." }
        if slash == p.startIndex { return "/" }
        return String(p[..<slash])
    }

    /// Last component: `name("/home/me/a.txt")` → `a.txt`.
    public static func name(_ path: String) -> String {
        let p = normalize(path)
        if p == "/" { return "/" }
        return p.split(separator: "/").last.map(String.init) ?? p
    }

    /// Breadcrumb trail: `/home/me` → `[("/", "/"), ("home", "/home"), ("me", "/home/me")]`.
    public static func breadcrumbs(_ path: String) -> [(name: String, path: String)] {
        let p = normalize(path)
        guard p.hasPrefix("/") else { return [(p, p)] }
        var result: [(String, String)] = [("/", "/")]
        var current = ""
        for part in p.split(separator: "/") {
            current += "/" + part
            result.append((String(part), current))
        }
        return result
    }

    /// Shows paths inside `home` as `~/...`.
    public static func abbreviate(_ path: String, home: String?) -> String {
        guard let home, !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Is `name` acceptable as a single file or folder name?
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}
