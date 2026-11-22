import Foundation

/// Lists folders on this Mac in the same `FileEntry` shape as the remote side.
public struct LocalFileService: Sendable {
    public init() {}

    public func list(_ path: String) throws -> [FileEntry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
            .fileSizeKey, .contentModificationDateKey, .isPackageKey,
        ]
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let urls = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
        return urls.compactMap { url in
            entry(for: url)
        }.sorted(by: FileEntry.finderOrder)
    }

    public func entry(for url: URL) -> FileEntry? {
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
            .fileSizeKey, .contentModificationDateKey, .isPackageKey,
        ]) else { return nil }
        var kind: FileEntry.Kind = .other
        var target: FileEntry.Kind?
        if values.isSymbolicLink == true {
            kind = .symlink
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                target = isDir.boolValue ? .directory : .file
            }
        } else if values.isDirectory == true {
            // App bundles and other packages behave like files (as in Finder).
            kind = values.isPackage == true ? .file : .directory
        } else if values.isRegularFile == true {
            kind = .file
        }
        return FileEntry(
            path: url.path,
            name: url.lastPathComponent,
            kind: kind,
            linkTarget: target,
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate ?? .distantPast
        )
    }

    /// Total bytes of a file or folder (recursively), for progress bars.
    public func totalSize(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        var total: Int64 = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let item as URL in e {
                if let v = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true {
                    total += Int64(v.fileSize ?? 0)
                }
            }
        }
        return total
    }

    public func freeSpace(at path: String) -> Int64? {
        let url = URL(fileURLWithPath: path)
        #if os(macOS)
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let cap = v.volumeAvailableCapacityForImportantUsage {
            return cap
        }
        #endif
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
           let free = attrs[.systemFreeSize] as? NSNumber {
            return free.int64Value
        }
        return nil
    }
}
