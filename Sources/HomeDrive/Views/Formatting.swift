import AppKit
import HomeDriveCore
import SwiftUI
import UniformTypeIdentifiers

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        bytes(Int64(bytesPerSecond)) + "/s"
    }

    static func duration(_ seconds: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f.string(from: max(1, seconds)) ?? ""
    }

    static func date(_ date: Date) -> String {
        guard date > Date(timeIntervalSince1970: 0) else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Real Finder icons: by path for local files, by file type for remote ones.
@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for entry: FileEntry, side: Side) -> NSImage {
        if side == .mac {
            return NSWorkspace.shared.icon(forFile: entry.path)
        }
        let key: String
        if entry.isFolderLike { key = "<folder>" }
        else if entry.kind == .symlink { key = "<link>" }
        else { key = entry.fileExtension }
        if let cached = cache[key] { return cached }
        let type: UTType
        switch key {
        case "<folder>": type = .folder
        case "<link>": type = .symbolicLink
        case "": type = .data
        default: type = UTType(filenameExtension: key) ?? .data
        }
        let image = NSWorkspace.shared.icon(for: type)
        cache[key] = image
        return image
    }
}
