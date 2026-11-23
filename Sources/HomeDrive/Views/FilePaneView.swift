import AppKit
import HomeDriveCore
import SwiftUI
import UniformTypeIdentifiers

/// Prefix used when dragging PC items as text, so the Mac pane can tell them apart.
let remoteDragPrefix = "homedrive-remote:"

/// One side of the window: header with places + path, a file table, and a status footer.
struct FilePaneView: View {
    @Environment(AppModel.self) private var app
    @Bindable var pane: PaneModel

    @State private var namePrompt: NamePrompt?
    @State private var nameText = ""
    @State private var deleteCandidates: [FileEntry] = []
    @State private var isDropTargeted = false

    struct NamePrompt: Identifiable {
        enum Kind { case newFolder, rename(FileEntry) }
        let id = UUID()
        let kind: Kind
    }

    private var isPC: Bool { pane.side == .pc }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(4)
                            .allowsHitTesting(false)
                    }
                }
            Divider()
            footer
        }
        .alert(namePromptTitle, isPresented: Binding(get: { namePrompt != nil }, set: { if !$0 { namePrompt = nil } })) {
            TextField("Name", text: $nameText)
            Button(namePromptAction) { commitNamePrompt() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { namePrompt = nil }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { !deleteCandidates.isEmpty },
                                                              set: { if !$0 { deleteCandidates = [] } })) {
            if isPC {
                if app.remoteInfo?.supportsTrash == true {
                    Button("Move to Trash") { app.deleteRemote(deleteCandidates, permanently: false) }
                }
                Button("Delete Permanently", role: .destructive) {
                    app.deleteRemote(deleteCandidates, permanently: true)
                }
            } else {
                Button("Move to Trash") { app.trashLocal(deleteCandidates) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isPC && app.remoteInfo?.supportsTrash != true
                 ? "This can't be undone." : "You can restore items from the Trash.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isPC ? "pc" : "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(isPC ? Color.orange : Color.accentColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text(isPC ? app.pcDisplayName : "This Mac").font(.headline)
                    if isPC, let os = app.remoteInfo?.os {
                        Text(os).font(.caption).foregroundStyle(.secondary)
                    } else if !isPC {
                        Text(app.macName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                placesMenu
            }
            HStack(spacing: 4) {
                Button { pane.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!pane.canGoBack)
                    .help("Back")
                Button { pane.goUp() } label: { Image(systemName: "arrow.up") }
                    .disabled(!pane.canGoUp)
                    .help("Enclosing folder")
                breadcrumbs
                Spacer(minLength: 4)
                if pane.isLoading { ProgressView().controlSize(.small) }
                Button { pane.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
                Button {
                    nameText = "New Folder"
                    namePrompt = NamePrompt(kind: .newFolder)
                } label: { Image(systemName: "folder.badge.plus") }
                    .help("New folder")
                Toggle(isOn: $pane.showHidden) { Image(systemName: pane.showHidden ? "eye" : "eye.slash") }
                    .toggleStyle(.button)
                    .help("Show hidden files")
            }
            .buttonStyle(.borderless)
            .disabled(isPC && !app.isConnected)
        }
        .padding(10)
    }

    private var placesMenu: some View {
        let places = isPC ? app.pcPlaces : app.macPlaces
        return Menu {
            ForEach(places, id: \.path) { place in
                Button { pane.navigate(to: place.path) } label: { Label(place.name, systemImage: place.symbol) }
            }
            if !isPC {
                Divider()
                Button("Choose Folder…") { chooseLocalFolder() }
            }
        } label: {
            Label("Places", systemImage: "star")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(places.isEmpty)
    }

    private var breadcrumbs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let crumbs = RemotePath.breadcrumbs(pane.path, home: homePath)
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                        }
                        Button(crumb.name) { pane.navigate(to: crumb.path) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(index == crumbs.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                            .id(index)
                    }
                }
                .font(.callout)
            }
            .onChange(of: pane.path) { _, _ in
                proxy.scrollTo(RemotePath.breadcrumbs(pane.path, home: homePath).count - 1, anchor: .trailing)
            }
        }
    }

    private var homePath: String? {
        isPC ? app.remoteInfo?.home : app.macHome
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isPC && !app.isConnected {
            disconnectedView
        } else if let error = pane.error {
            ContentUnavailableView {
                Label("Can't open this folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { pane.reload() }
                if pane.canGoBack { Button("Go Back") { pane.goBack() } }
            }
            .dropDestination(for: URL.self) { _, _ in false }
        } else {
            table
        }
    }

    private var disconnectedView: some View {
        Group {
            switch app.connection {
            case .connecting:
                ProgressView("Connecting to \(app.settings.host)…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't connect", systemImage: "wifi.exclamationmark")
                } description: {
                    ScrollView { Text(message).textSelection(.enabled) }.frame(maxHeight: 160)
                } actions: {
                    Button("Try Again") { app.connect() }.keyboardShortcut(.defaultAction)
                    Button("Settings…") { app.showSettings = true }
                }
            default:
                ContentUnavailableView {
                    Label("Not connected", systemImage: "pc")
                } description: {
                    Text(app.settings.isConfigured
                         ? "Connect to \(app.settings.host) to browse its files.\nMake sure WireGuard is on."
                         : "Set up your Linux PC's SSH host to get started.")
                } actions: {
                    if app.settings.isConfigured {
                        Button("Connect") { app.connect() }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Set Up…") { app.showSettings = true }.keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var table: some View {
        Table(of: FileEntry.self, selection: $pane.selection, sortOrder: $pane.sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { entry in
                HStack(spacing: 6) {
                    Image(nsImage: FileIcons.icon(for: entry, side: pane.side))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(entry.isHidden ? .secondary : .primary)
                    if entry.kind == .symlink {
                        Image(systemName: "arrow.turn.up.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 160, ideal: 260)
            TableColumn("Size", value: \.size) { entry in
                Text(entry.isFolderLike ? "—" : Format.bytes(entry.size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            TableColumn("Modified", value: \.modified) { entry in
                Text(Format.date(entry.modified)).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 150)
        } rows: {
            ForEach(pane.visibleEntries) { entry in
                if isPC {
                    TableRow(entry).draggable(remoteDragPrefix + entry.path)
                } else {
                    TableRow(entry).draggable(URL(fileURLWithPath: entry.path))
                }
            }
        }
        .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
            contextMenu(for: entries(ids))
        } primaryAction: { ids in
            guard let first = entries(ids).first else { return }
            if isPC { app.openRemote(first) } else { app.openLocal(first) }
        }
        .onDeleteCommand {
            let selected = pane.selectedEntries
            if !selected.isEmpty { deleteCandidates = selected }
        }
        .modifier(DropSupport(isPC: isPC, isTargeted: $isDropTargeted))
        .overlay {
            if pane.visibleEntries.isEmpty && !pane.isLoading {
                Text(isPC ? "Empty folder — drop files here to send them" : "Empty folder")
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
    }

    private func entries(_ ids: Set<FileEntry.ID>) -> [FileEntry] {
        pane.visibleEntries.filter { ids.contains($0.id) }
    }

    @ViewBuilder
    private func contextMenu(for entries: [FileEntry]) -> some View {
        if entries.isEmpty {
            Button("New Folder…") { nameText = "New Folder"; namePrompt = NamePrompt(kind: .newFolder) }
            Button("Refresh") { pane.reload() }
        } else if isPC {
            Button("Retrieve to Mac (\(app.displayPath(mac: app.mac.path)))") { app.retrieve(entries) }
            Button("Retrieve to…") {
                pane.selection = Set(entries.map(\.id))
                app.retrieveSelection(choosingFolder: true)
            }
            if entries.count == 1, let entry = entries.first {
                Button(entry.isFolderLike ? "Open" : "Open on Mac") { app.openRemote(entry) }
                Divider()
                Button("Rename…") { nameText = entry.name; namePrompt = NamePrompt(kind: .rename(entry)) }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entries.map(\.path).joined(separator: "\n"), forType: .string)
            }
            Divider()
            Button(app.remoteInfo?.supportsTrash == true ? "Move to Trash…" : "Delete…", role: .destructive) {
                deleteCandidates = entries
            }
        } else {
            Button("Send to \(app.pcDisplayName)") {
                app.send(entries.map { URL(fileURLWithPath: $0.path) })
            }
            .disabled(!app.isConnected)
            if entries.count == 1, let entry = entries.first {
                Button("Open") { app.openLocal(entry) }
                Button("Show in Finder") { app.revealLocal(URL(fileURLWithPath: entry.path)) }
                Divider()
                Button("Rename…") { nameText = entry.name; namePrompt = NamePrompt(kind: .rename(entry)) }
            }
            Divider()
            Button("Move to Trash", role: .destructive) { deleteCandidates = entries }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            let visible = pane.visibleEntries
            let selected = pane.selectedEntries
            Text(selected.isEmpty
                 ? "\(visible.count) item\(visible.count == 1 ? "" : "s")"
                 : "\(selected.count) of \(visible.count) selected")
            if !selected.isEmpty {
                let bytes = selected.filter { !$0.isFolderLike }.reduce(0) { $0 + $1.size }
                if bytes > 0 { Text("· \(Format.bytes(bytes))") }
            }
            Spacer()
            if let free = freeSpace {
                Text("\(Format.bytes(free)) free")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var freeSpace: Int64? {
        if isPC { return app.remoteInfo?.diskFreeBytes }
        return pane.path.isEmpty ? nil : LocalFileService().freeSpace(at: pane.path)
    }

    // MARK: Prompts

    private var namePromptTitle: String {
        switch namePrompt?.kind {
        case .rename(let entry): return "Rename “\(entry.name)”"
        default: return "New Folder"
        }
    }

    private var namePromptAction: String {
        if case .rename = namePrompt?.kind { return "Rename" }
        return "Create"
    }

    private var deleteTitle: String {
        let what = deleteCandidates.count == 1 ? "“\(deleteCandidates[0].name)”" : "\(deleteCandidates.count) items"
        if isPC && app.remoteInfo?.supportsTrash != true { return "Delete \(what) from \(app.pcDisplayName)?" }
        return "Move \(what) to the Trash?"
    }

    private func commitNamePrompt() {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { namePrompt = nil }
        guard !name.isEmpty, let prompt = namePrompt else { return }
        switch prompt.kind {
        case .newFolder:
            if isPC { app.newRemoteFolder(named: name) } else { app.newLocalFolder(named: name) }
        case .rename(let entry):
            guard name != entry.name else { return }
            if isPC { app.renameRemote(entry, to: name) } else { app.renameLocal(entry, to: name) }
        }
    }

    private func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: pane.path)
        if panel.runModal() == .OK, let url = panel.url { pane.navigate(to: url.path) }
    }
}

/// Drops onto the PC pane upload Mac files (from Finder or the Mac pane).
/// Drops onto the Mac pane download items dragged from the PC pane.
private struct DropSupport: ViewModifier {
    @Environment(AppModel.self) private var app
    let isPC: Bool
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if isPC {
            content.dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty, app.isConnected else { return false }
                app.send(files)
                return true
            } isTargeted: { isTargeted = $0 && app.isConnected }
        } else {
            content.dropDestination(for: String.self) { strings, _ in
                let paths = strings.flatMap { $0.components(separatedBy: "\n") }
                    .filter { $0.hasPrefix(remoteDragPrefix) }
                    .map { String($0.dropFirst(remoteDragPrefix.count)) }
                guard !paths.isEmpty else { return false }
                app.retrieve(paths: paths)
                return true
            } isTargeted: { isTargeted = $0 }
        }
    }
}
