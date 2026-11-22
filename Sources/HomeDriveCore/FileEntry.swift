import Foundation

/// A file or folder, on either machine.
public struct FileEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case file, directory, symlink, other
    }

    /// Full path. For remote entries this is a POSIX path on the Linux PC.
    public var path: String
    public var name: String
    public var kind: Kind
    /// For symlinks: the kind of the target (`nil` if broken or unknown).
    public var linkTarget: Kind?
    public var size: Int64
    public var modified: Date
    /// Octal permission bits as text, e.g. `"644"`.
    public var permissions: String

    public var id: String { path }

    public init(path: String, name: String, kind: Kind, linkTarget: Kind? = nil,
                size: Int64, modified: Date, permissions: String = "") {
        self.path = path
        self.name = name
        self.kind = kind
        self.linkTarget = linkTarget
        self.size = size
        self.modified = modified
        self.permissions = permissions
    }

    /// Can be opened like a folder (a folder or a link to one).
    public var isFolderLike: Bool {
        kind == .directory || (kind == .symlink && linkTarget == .directory)
    }

    public var isHidden: Bool { name.hasPrefix(".") }

    /// Lowercased extension, used for icons.
    public var fileExtension: String {
        guard !isFolderLike, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}

extension FileEntry {
    /// Folders first, then case-insensitive natural name order (file2 < file10).
    public static func finderOrder(_ a: FileEntry, _ b: FileEntry) -> Bool {
        if a.isFolderLike != b.isFolderLike { return a.isFolderLike }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
