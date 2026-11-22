import Foundation
import HomeDriveCore
import Observation

enum Side: String {
    case mac, pc
}

/// State for one file browser pane (the Mac side or the Linux PC side).
@MainActor
@Observable
final class PaneModel {
    let side: Side
    private(set) var path: String = ""
    private(set) var entries: [FileEntry] = []
    private(set) var isLoading = false
    private(set) var error: String?
    var selection: Set<FileEntry.ID> = []
    var showHidden = false
    var sortOrder: [KeyPathComparator<FileEntry>] = [KeyPathComparator(\.name, comparator: .localizedStandard)]
    private(set) var backStack: [String] = []

    /// Fetches the contents of a folder. Set by `AppModel`.
    @ObservationIgnored var loader: ((String) async throws -> [FileEntry])?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(side: Side) {
        self.side = side
    }

    /// Entries after applying the hidden-file filter and the table's sort order.
    /// Folders always stay on top, as in Finder.
    var visibleEntries: [FileEntry] {
        let filtered = showHidden ? entries : entries.filter { !$0.isHidden }
        let sorted = filtered.sorted(using: sortOrder)
        return sorted.filter(\.isFolderLike) + sorted.filter { !$0.isFolderLike }
    }

    var selectedEntries: [FileEntry] {
        entries.filter { selection.contains($0.id) }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoUp: Bool { !path.isEmpty && path != "/" }

    func navigate(to newPath: String, recordHistory: Bool = true) {
        let target = RemotePath.normalize(newPath)
        if recordHistory, !path.isEmpty, target != path {
            backStack.append(path)
            if backStack.count > 50 { backStack.removeFirst() }
        }
        path = target
        selection = []
        reload()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        navigate(to: previous, recordHistory: false)
    }

    func goUp() {
        guard canGoUp else { return }
        let child = path
        navigate(to: RemotePath.parent(path))
        // Keep the folder we came from selected, which is handy when climbing up.
        selection = [child]
    }

    func reload() {
        guard let loader, !path.isEmpty else { return }
        loadTask?.cancel()
        let requested = path
        isLoading = true
        loadTask = Task { [weak self] in
            do {
                let result = try await loader(requested)
                guard let self, !Task.isCancelled, self.path == requested else { return }
                self.entries = result
                self.error = nil
                let ids = Set(result.map(\.id))
                self.selection = self.selection.intersection(ids)
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.path == requested else { return }
                self.entries = []
                self.error = error.localizedDescription
            }
            self?.isLoading = false
        }
    }

    /// Clears everything (used when disconnecting).
    func reset() {
        loadTask?.cancel()
        path = ""
        entries = []
        error = nil
        selection = []
        backStack = []
        isLoading = false
    }
}
