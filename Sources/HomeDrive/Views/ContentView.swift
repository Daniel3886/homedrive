import AppKit
import HomeDriveCore
import SwiftUI

/// Main window: Mac on the left, Linux PC on the right, transfers underneath.
struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        VSplitView {
            HSplitView {
                FilePaneView(pane: app.mac)
                    .frame(minWidth: 320, idealWidth: 560, maxWidth: .infinity)
                transferButtons
                FilePaneView(pane: app.pc)
                    .frame(minWidth: 320, idealWidth: 560, maxWidth: .infinity)
            }
            .frame(minHeight: 300, maxHeight: .infinity)
            TransfersView()
                .frame(minHeight: 110, idealHeight: 180, maxHeight: 400)
        }
        .frame(minWidth: 820, minHeight: 520)
        .toolbar { toolbar }
        .navigationTitle("HomeDrive")
        .navigationSubtitle(subtitle)
        .sheet(isPresented: $app.showSettings) {
            SettingsView(isSheet: true)
        }
        .alert(item: $app.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .alert(conflictTitle, isPresented: Binding(get: { app.conflict != nil }, set: { _ in })) {
            Button("Replace") { app.conflict?.resolve(.replace) }
            Button("Skip Existing") { app.conflict?.resolve(.skip) }
            Button("Cancel", role: .cancel) { app.conflict?.resolve(.cancel) }
        } message: {
            Text(conflictMessage)
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                let window = NSApp.windows.first { $0.isVisible && $0.sheetParent == nil }
                WindowLayout.balancePanes(in: window)
                WindowLayout.sizeTransfers(in: window)
                WindowLayout.focusFirstTable(in: window)
            }
            if !app.settings.isConfigured {
                app.showSettings = true
            } else if !app.isConnected {
                app.connect()
            }
        }
    }

    /// The narrow column between the panes.
    private var transferButtons: some View {
        VStack(spacing: 14) {
            Spacer()
            Button { app.sendSelection() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 26))
                    Text("Send").font(.caption)
                }
            }
            .disabled(!app.isConnected || app.mac.selection.isEmpty)
            .help("Send the selected Mac items to the folder open on the PC (⌘→)")
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button { app.retrieveSelection() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.left.circle.fill").font(.system(size: 26))
                    Text("Retrieve").font(.caption)
                }
            }
            .disabled(!app.isConnected || app.pc.selection.isEmpty)
            .help("Copy the selected PC items to the folder open on the Mac (⌘←)")
            .keyboardShortcut(.leftArrow, modifiers: .command)
            Spacer()
        }
        .buttonStyle(.borderless)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ConnectionBadge()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            switch app.connection {
            case .connected:
                Button { app.disconnect() } label: { Label("Disconnect", systemImage: "bolt.horizontal.circle") }
                    .help("Disconnect from the PC")
            case .connecting:
                Button { app.disconnect() } label: { Label("Stop", systemImage: "stop.circle") }
            default:
                Button { app.connect() } label: { Label("Connect", systemImage: "bolt.horizontal.circle.fill") }
                    .help("Connect to the PC")
            }
            Button { app.refreshAll() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Refresh both sides (⌘R)")
            SettingsLink { Label("Settings", systemImage: "gearshape") }
                .help("Connection settings (⌘,)")
        }
    }

    private var subtitle: String {
        switch app.connection {
        case .connected: return "Connected to \(app.pcDisplayName)"
        case .connecting: return "Connecting…"
        case .failed: return "Connection failed"
        case .disconnected: return "Not connected"
        }
    }

    private var conflictTitle: String {
        guard let c = app.conflict else { return "" }
        return c.names.count == 1 ? "“\(c.names[0])” already exists" : "\(c.names.count) items already exist"
    }

    private var conflictMessage: String {
        guard let c = app.conflict else { return "" }
        let list = c.names.prefix(5).joined(separator: "\n")
        let more = c.names.count > 5 ? "\n…and \(c.names.count - 5) more" : ""
        return "In \(c.destination):\n\(list)\(more)\n\nReplace them with the items you're copying?"
    }
}

/// Coloured dot + state, top-left of the toolbar.
struct ConnectionBadge: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.callout)
        }
        .padding(.horizontal, 8)
        .help(help)
    }

    private var color: Color {
        switch app.connection {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var label: String {
        switch app.connection {
        case .connected: return app.pcDisplayName
        case .connecting: return "Connecting…"
        case .failed: return "Offline"
        case .disconnected: return "Not connected"
        }
    }

    private var help: String {
        if case .failed(let message) = app.connection { return message }
        return app.settings.isConfigured ? "SSH host: \(app.settings.destination)" : "No PC set up"
    }
}
