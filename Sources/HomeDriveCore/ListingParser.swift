import Foundation

/// Parses the output of the remote listing script (see `RemoteScripts.list`).
///
/// Records are NUL-terminated, fields tab-separated: `type \t size \t mtime \t mode \t name`.
/// The name is the last field and may itself contain tabs, so we split at most 4 times.
///
/// Two dialects are understood:
/// * GNU find (Linux): type is `%y%Y`, e.g. `ff`, `dd`, `ld` (link → dir), `lN` (broken link);
///   mtime is fractional seconds (`1700000000.123`); name is the bare file name.
/// * BSD stat (macOS remote, used in tests): type is a word (`Regular File`, `Directory`,
///   `Symbolic Link`); mtime is integer seconds; name is a full path.
public enum ListingParser {
    public static func parse(_ data: Data, parent: String) -> [FileEntry] {
        var entries: [FileEntry] = []
        for record in data.split(separator: 0, omittingEmptySubsequences: true) {
            let line = String(decoding: record, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            if let entry = parseRecord(line, parent: parent) {
                entries.append(entry)
            }
        }
        return entries
    }

    static func parseRecord(_ line: String, parent: String) -> FileEntry? {
        let fields = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
        guard fields.count == 5 else { return nil }
        let (kind, target) = parseType(String(fields[0]))
        let size = Int64(fields[1]) ?? 0
        let mtime = Double(fields[2]) ?? 0
        let mode = String(fields[3])
        var name = String(fields[4])
        if name.contains("/") { name = RemotePath.name(name) }   // BSD stat prints full paths
        guard RemotePath.isValidName(name) else { return nil }
        return FileEntry(
            path: RemotePath.join(parent, name),
            name: name,
            kind: kind,
            linkTarget: target,
            size: size,
            modified: Date(timeIntervalSince1970: mtime),
            permissions: mode
        )
    }

    static func parseType(_ raw: String) -> (FileEntry.Kind, FileEntry.Kind?) {
        switch raw {
        case "Directory": return (.directory, nil)
        case "Regular File": return (.file, nil)
        case "Symbolic Link": return (.symlink, nil)
        default: break
        }
        guard let first = raw.first else { return (.other, nil) }
        let kind = kindFromGNU(first)
        if kind == .symlink, raw.count > 1 {
            let target = kindFromGNU(raw[raw.index(after: raw.startIndex)])
            return (.symlink, target == .other ? nil : target)
        }
        return (kind, nil)
    }

    private static func kindFromGNU(_ c: Character) -> FileEntry.Kind {
        switch c {
        case "f": return .file
        case "d": return .directory
        case "l": return .symlink
        default: return .other
        }
    }
}
