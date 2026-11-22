import AppKit
import Foundation
import HomeDriveCore
import Observation

/// What to do when items being transferred already exist at the destination.
enum ConflictChoice {
    case replace, skip, cancel
}

struct ConflictPrompt: Identifiable {
    let id = UUID()
    let names: [String]
    let destination: String
    let resolve: (ConflictChoice) -> Void
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// App-wide state: connection, both panes, and the transfer queue.
@MainActor
@Observable
final class AppModel {
    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected(RemoteSystemInfo)
        case failed(String)

        var info: RemoteSystemInfo? {
            if case .connected(let info) = self { return info }
            return nil
        }
    }

    var settings: ConnectionSettings {
        didSet { if settings != oldValue { settingsStore.save(settings) } }
    }
    private(set) var connection: Connection = .disconnected
    let mac = PaneModel(side: .mac)
    let pc = PaneModel(side: .pc)
    let transfers = TransferQueue()
    var alert: AlertMessage?
    var conflict: ConflictPrompt?
    var showSettings = false

    // Developer overrides (see docs/DEVELOPMENT.md): point the app at a different ssh
    // binary, e.g. the fake one used by the tests, and keep its settings separate.
    @ObservationIgnored private static let env = ProcessInfo.processInfo.environment
    @ObservationIgnored private let settingsStore = SettingsStore(key: AppModel.env["HOMEDRIVE_SETTINGS_KEY"] ?? "connectionSettings")
    @ObservationIgnored private let local = LocalFileService()
    @ObservationIgnored private var connectTask: Task<Void, Never>?

    init() {
        settings = SettingsStore(key: AppModel.env["HOMEDRIVE_SETTINGS_KEY"] ?? "connectionSettings").load()
        mac.loader = { path in
            try await Task.detached { try LocalFileService().list(path) }.value
        }
        pc.loader = { [weak self] path in
            guard let self else { return [] }
            return try await self.remote.list(path)
        }
        let start = settings.localStartPath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
            : (settings.localStartPath as NSString).expandingTildeInPath
        mac.navigate(to: FileManager.default.fileExists(atPath: start) ? start : NSHomeDirectory())
    }

    // MARK: Services

    var builder: SSHCommandBuilder {
        SSHCommandBuilder(settings: settings, sshExecutable: Self.env["HOMEDRIVE_SSH"] ?? "/usr/bin/ssh")
    }
    var remote: RemoteFileService { RemoteFileService(builder: builder) }
    var engine: TransferEngine { TransferEngine(builder: builder) }

    var isConnected: Bool { connection.info != nil }
    var remoteInfo: RemoteSystemInfo? { connection.info }

    var pcDisplayName: String {
        if let host = remoteInfo?.hostname, !host.isEmpty { return host }
        return settings.isConfigured ? settings.host : "Linux PC"
    }

    // MARK: Connection

    func connect() {
        guard settings.isConfigured else {
            showSettings = true
            return
        }
        connectTask?.cancel()
        connection = .connecting
        let service = remote
        connectTask = Task {
            do {
                let info = try await service.connect()
                guard !Task.isCancelled else { return }
                connection = .connected(info)
                let start = settings.remoteStartPath.trimmingCharacters(in: .whitespaces)
                pc.reset()
                pc.navigate(to: start.isEmpty ? info.home : start)
            } catch is CancellationError {
                connection = .disconnected
            } catch {
                connection = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        connectTask?.cancel()
        transfers.cancelAll()
        let service = remote
        Task { await service.disconnect() }
        connection = .disconnected
        pc.reset()
    }

    /// Called after settings change: drop the old connection and reconnect with the new one.
    func settingsChanged(from old: ConnectionSettings) {
        guard old != settings else { return }
        var oldBuilder = builder
        oldBuilder.settings = old
        let oldService = RemoteFileService(builder: oldBuilder)
        Task { await oldService.disconnect() }
        connection = .disconnected
        pc.reset()
        if settings.isConfigured { connect() }
    }

    func refreshRemoteInfo() {
        guard isConnected else { return }
        let service = remote
        Task {
            if let info = try? await service.probe(), isConnected {
                connection = .connected(info)
            }
        }
    }

    func refreshAll() {
        mac.reload()
        if isConnected {
            pc.reload()
            refreshRemoteInfo()
        } else if case .failed = connection {
            connect()
        }
    }

    // MARK: Places

    var macPlaces: [(name: String, path: String, symbol: String)] {
        let home = NSHomeDirectory()
        return [
            ("Home", home, "house"),
            ("Desktop", home + "/Desktop", "menubar.dock.rectangle"),
            ("Documents", home + "/Documents", "doc"),
            ("Downloads", home + "/Downloads", "arrow.down.circle"),
            ("Pictures", home + "/Pictures", "photo"),
            ("Movies", home + "/Movies", "film"),
            ("Music", home + "/Music", "music.note"),
        ].filter { FileManager.default.fileExists(atPath: $0.1) }
    }

    var pcPlaces: [(name: String, path: String, symbol: String)] {
        guard let info = remoteInfo else { return [] }
        var places: [(String, String, String)] = [("Home", info.home, "house")]
        for path in info.places {
            let name = RemotePath.name(path)
            places.append((name, path, Self.symbol(forPlace: name)))
        }
        places.append(("Computer", "/", "desktopcomputer"))
        return places
    }

    static func symbol(forPlace name: String) -> String {
        switch name.lowercased() {
        case "desktop": return "menubar.dock.rectangle"
        case "documents": return "doc"
        case "downloads": return "arrow.down.circle"
        case "pictures", "photos": return "photo"
        case "videos", "movies": return "film"
        case "music": return "music.note"
        default: return "folder"
        }
    }

    // MARK: Sending (Mac → PC)

    /// Uploads local files/folders into `remoteFolder` (default: the folder open in the PC pane).
    func send(_ urls: [URL], to remoteFolder: String? = nil) {
        guard isConnected else {
            alert = AlertMessage(title: "Not connected", message: "Connect to the Linux PC first.")
            return
        }
        let folder = remoteFolder ?? pc.path
        guard !folder.isEmpty, !urls.isEmpty else { return }
        let service = remote
        Task {
            let names = urls.map(\.lastPathComponent)
            let existing: Set<String>
            do {
                existing = try await service.existingNames(names, in: folder)
            } catch {
                alert = AlertMessage(title: "Couldn't send", message: error.localizedDescription)
                return
            }
            guard let choice = await resolveConflicts(names.filter(existing.contains),
                                                      destination: displayPath(pc: folder)) else { return }
            for url in urls {
                let name = url.lastPathComponent
                let exists = existing.contains(name)
                if exists && choice == .skip { continue }
                enqueueUpload(url, to: folder, replace: exists)
            }
        }
    }

    private func enqueueUpload(_ url: URL, to folder: String, replace: Bool) {
        let engine = self.engine
        let size = local.totalSize(of: url)
        let transfer = Transfer(name: url.lastPathComponent, direction: .upload,
                                destination: displayPath(pc: folder), totalBytes: size) { progress in
            try await engine.upload(url, toRemoteFolder: folder, replaceExisting: replace, progress: progress)
        }
        transfer.onFinish = { [weak self] in
            guard let self else { return }
            if self.pc.path == folder { self.pc.reload() }
            self.refreshRemoteInfo()
            self.updateDockBadge()
        }
        transfers.enqueue(transfer)
        updateDockBadge()
    }

    func sendSelection() {
        send(mac.selectedEntries.map { URL(fileURLWithPath: $0.path) })
    }

    // MARK: Retrieving (PC → Mac)

    /// Downloads remote entries into `localFolder` (default: the folder open in the Mac pane).
    func retrieve(_ entries: [FileEntry], to localFolder: URL? = nil) {
        guard isConnected, !entries.isEmpty else { return }
        let folder = localFolder ?? URL(fileURLWithPath: mac.path, isDirectory: true)
        let existing = entries.map(\.name).filter {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        Task {
            guard let choice = await resolveConflicts(existing, destination: displayPath(mac: folder.path))
            else { return }
            let service = remote
            for entry in entries {
                let exists = existing.contains(entry.name)
                if exists && choice == .skip { continue }
                var size = entry.size
                if entry.isFolderLike {
                    size = (try? await service.diskUsage([entry.path])) ?? 0
                }
                enqueueDownload(entry, to: folder, replace: exists, size: size)
            }
        }
    }

    /// Paths dragged out of the PC pane arrive as text; turn them back into entries.
    func retrieve(paths: [String], to localFolder: URL? = nil) {
        let known = Dictionary(pc.entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = paths.map { path in
            known[path] ?? FileEntry(path: path, name: RemotePath.name(path), kind: .file,
                                     size: 0, modified: .distantPast)
        }
        retrieve(entries, to: localFolder)
    }

    @discardableResult
    private func enqueueDownload(_ entry: FileEntry, to folder: URL, replace: Bool, size: Int64,
                                 then: (@MainActor (URL) -> Void)? = nil) -> Transfer {
        let engine = self.engine
        let path = entry.path
        let result = folder.appendingPathComponent(entry.name)
        let transfer = Transfer(name: entry.name, direction: .download, destination: displayPath(mac: folder.path),
                                localResult: result, totalBytes: size) { progress in
            try await engine.download(path, toLocalFolder: folder, replaceExisting: replace, progress: progress)
        }
        transfer.onSuccess = { then?(result) }
        transfer.onFinish = { [weak self] in
            guard let self else { return }
            if self.mac.path == folder.path { self.mac.reload() }
            self.updateDockBadge()
        }
        transfers.enqueue(transfer)
        updateDockBadge()
        return transfer
    }

    func retrieveSelection() {
        retrieve(pc.selectedEntries)
    }

    func retrieveSelection(choosingFolder: Bool) {
        guard choosingFolder else { return retrieveSelection() }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Download Here"
        panel.directoryURL = URL(fileURLWithPath: mac.path)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        retrieve(pc.selectedEntries, to: url)
    }

    /// Downloads a remote file to a cache folder and opens it with its default Mac app.
    func openRemote(_ entry: FileEntry) {
        if entry.isFolderLike {
            pc.navigate(to: entry.path)
            return
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeDrive/Opened/\(UUID().uuidString)", isDirectory: true)
        enqueueDownload(entry, to: cache, replace: true, size: entry.size) { url in
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Remote file management

    func newRemoteFolder(named name: String) {
        let folder = pc.path
        runRemote("Couldn't create folder") { service in
            try await service.makeDirectory(named: name, in: folder)
        } then: { [weak self] in
            self?.pc.reload()
            self?.pc.selection = [RemotePath.join(folder, name)]
        }
    }

    func renameRemote(_ entry: FileEntry, to name: String) {
        runRemote("Couldn't rename") { service in
            try await service.rename(entry.path, to: name)
        } then: { [weak self] in
            self?.pc.reload()
            self?.pc.selection = [RemotePath.join(RemotePath.parent(entry.path), name)]
        }
    }

    func deleteRemote(_ entries: [FileEntry], permanently: Bool) {
        let paths = entries.map(\.path)
        runRemote(permanently ? "Couldn't delete" : "Couldn't move to Trash") { service in
            if permanently { try await service.delete(paths) } else { try await service.trash(paths) }
        } then: { [weak self] in
            self?.pc.reload()
            self?.refreshRemoteInfo()
        }
    }

    private func runRemote(_ failureTitle: String,
                           _ operation: @escaping @Sendable (RemoteFileService) async throws -> Void,
                           then: @escaping @MainActor () -> Void) {
        let service = remote
        Task {
            do {
                try await operation(service)
                then()
            } catch {
                alert = AlertMessage(title: failureTitle, message: error.localizedDescription)
                pc.reload()
            }
        }
    }

    // MARK: Local file management

    func newLocalFolder(named name: String) {
        let url = URL(fileURLWithPath: mac.path).appendingPathComponent(name)
        do {
            guard RemotePath.isValidName(name) else { throw HomeDriveError.invalidName(name) }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            mac.reload()
            mac.selection = [url.path]
        } catch {
            alert = AlertMessage(title: "Couldn't create folder", message: error.localizedDescription)
        }
    }

    func renameLocal(_ entry: FileEntry, to name: String) {
        let src = URL(fileURLWithPath: entry.path)
        let dst = src.deletingLastPathComponent().appendingPathComponent(name)
        do {
            guard RemotePath.isValidName(name) else { throw HomeDriveError.invalidName(name) }
            try FileManager.default.moveItem(at: src, to: dst)
            mac.reload()
            mac.selection = [dst.path]
        } catch {
            alert = AlertMessage(title: "Couldn't rename", message: error.localizedDescription)
        }
    }

    func trashLocal(_ entries: [FileEntry]) {
        let urls = entries.map { URL(fileURLWithPath: $0.path) }
        NSWorkspace.shared.recycle(urls) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.alert = AlertMessage(title: "Couldn't move to Trash", message: error.localizedDescription)
                }
                self?.mac.reload()
            }
        }
    }

    func openLocal(_ entry: FileEntry) {
        if entry.isFolderLike {
            mac.navigate(to: entry.path)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        }
    }

    func revealLocal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Helpers

    /// Asks the user what to do about existing names. Returns `nil` if they cancel.
    private func resolveConflicts(_ names: [String], destination: String) async -> ConflictChoice? {
        guard !names.isEmpty else { return .replace }
        let choice = await withCheckedContinuation { continuation in
            conflict = ConflictPrompt(names: names, destination: destination) { choice in
                continuation.resume(returning: choice)
            }
        }
        conflict = nil
        return choice == .cancel ? nil : choice
    }

    func displayPath(pc path: String) -> String {
        RemotePath.abbreviate(path, home: remoteInfo?.home)
    }

    func displayPath(mac path: String) -> String {
        RemotePath.abbreviate(path, home: NSHomeDirectory())
    }

    func updateDockBadge() {
        let count = transfers.activeCount
        NSApp?.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }
}
