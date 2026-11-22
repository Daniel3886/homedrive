import AppKit
import SwiftUI

@main
struct HomeDriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("HomeDrive", id: "main") {
            ContentView()
                .environment(model)
                .onAppear {
                    appDelegate.model = model
                    #if DEBUG
                    DebugSnapshot.startIfRequested(model: model)
                    #endif
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") { model.refreshAll() }
                    .keyboardShortcut("r", modifiers: .command)
                Toggle("Show Hidden Files", isOn: Binding(
                    get: { model.mac.showHidden },
                    set: { model.mac.showHidden = $0; model.pc.showHidden = $0 }))
                    .keyboardShortcut(".", modifiers: [.command, .shift])
            }
            CommandMenu("Connection") {
                Button("Connect") { model.connect() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(model.isConnected)
                Button("Disconnect") { model.disconnect() }
                    .disabled(!model.isConnected)
                Divider()
                Button("Send Selected to PC") { model.sendSelection() }
                    .disabled(!model.isConnected || model.mac.selection.isEmpty)
                Button("Retrieve Selected to Mac") { model.retrieveSelection() }
                    .disabled(!model.isConnected || model.pc.selection.isEmpty)
                Button("Retrieve Selected to…") { model.retrieveSelection(choosingFolder: true) }
                    .disabled(!model.isConnected || model.pc.selection.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run` (no .app bundle): become a regular,
        // frontmost app with a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.transfers.activeCount > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Transfers are still running"
        alert.informativeText = "Quitting now cancels \(model.transfers.activeCount) transfer(s). Partially copied items are cleaned up."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Close the shared SSH connection so it doesn't linger.
        guard let model else { return }
        model.transfers.cancelAll()
        let builder = model.builder
        if builder.settings.useMultiplexing && builder.settings.isConfigured {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: builder.sshExecutable)
            p.arguments = builder.stopMaster()
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }
}
