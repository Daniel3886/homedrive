import AppKit
import HomeDriveCore
import SwiftUI

/// Connection settings. Shown in the Settings window (⌘,) and as a sheet on first launch.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var isSheet = false

    @State private var draft = ConnectionSettings()
    @State private var portText = ""
    @State private var aliases: [SSHHostAlias] = []
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, testing, ok(String), failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("Host", text: $draft.host, prompt: Text("ubuntu-home, 10.77.0.1 or name.duckdns.org"))
                        if !aliases.isEmpty {
                            Menu {
                                ForEach(aliases) { alias in
                                    Button("\(alias.alias)  —  \(alias.summary)") { draft.host = alias.alias }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Hosts from ~/.ssh/config")
                        }
                    }
                    TextField("User", text: $draft.user, prompt: Text("optional — from SSH config if empty"))
                    TextField("Port", text: $portText, prompt: Text("22"))
                    HStack {
                        TextField("SSH key", text: $draft.identityFile, prompt: Text("optional — e.g. ~/.ssh/id_ed25519"))
                        Button("Choose…") { chooseKey() }
                    }
                } header: {
                    Text("Linux PC")
                } footer: {
                    Text("Tip: an alias from ~/.ssh/config (like the one you use in Terminal) is all you need. HomeDrive uses key-based login; it can't type passwords.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Folders") {
                    TextField("Start on PC in", text: $draft.remoteStartPath, prompt: Text("~ (home folder), or e.g. ~/Documents"))
                    HStack {
                        TextField("Start on Mac in", text: $draft.localStartPath, prompt: Text("~/Downloads"))
                        Button("Choose…") { chooseLocalStart() }
                    }
                }

                Section("Connection") {
                    Stepper("Connect timeout: \(draft.connectTimeout) s", value: $draft.connectTimeout, in: 2...60)
                    Toggle("Keep one shared connection open (faster browsing)", isOn: $draft.useMultiplexing)
                    Toggle("Trust the PC's host key on first connection", isOn: $draft.acceptNewHostKeys)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Test Connection") { test() }
                    .disabled(!candidate.isConfigured || testState == .testing)
                testStatus
                Spacer()
                if isSheet {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                Button(isSheet ? "Save & Connect" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!candidate.isConfigured || candidate == app.settings && !isSheet)
            }
            .padding()
        }
        .frame(width: 560)
        .frame(minHeight: 520)
        .onAppear {
            draft = app.settings
            portText = app.settings.port.map(String.init) ?? ""
            aliases = SSHConfigParser.loadDefault()
            if draft.host.isEmpty, let first = aliases.first { draft.host = first.alias }
        }
    }

    /// The draft with the port text applied.
    private var candidate: ConnectionSettings {
        var s = draft
        s.host = s.host.trimmingCharacters(in: .whitespaces)
        s.port = Int(portText.trimmingCharacters(in: .whitespaces))
        return s
    }

    @ViewBuilder
    private var testStatus: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .ok(let text):
            Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green).lineLimit(1)
        case .failed(let text):
            Label("Failed", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(text)
                .onTapGesture { app.alert = AlertMessage(title: "Connection test failed", message: text) }
        }
    }

    private func test() {
        var settings = candidate
        settings.useMultiplexing = false   // test a fresh connection
        testState = .testing
        Task {
            do {
                var builder = app.builder
                builder.settings = settings
                let info = try await RemoteFileService(builder: builder).probe()
                testState = .ok("Connected to \(info.hostname) (\(info.os))")
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }

    private func save() {
        let old = app.settings
        app.settings = candidate
        if isSheet {
            dismiss()
            if app.settings == old { app.connect() }
        }
        app.settingsChanged(from: old)
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        panel.prompt = "Use Key"
        if panel.runModal() == .OK, let url = panel.url {
            draft.identityFile = RemotePath.abbreviate(url.path, home: NSHomeDirectory())
        }
    }

    private func chooseLocalStart() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            draft.localStartPath = RemotePath.abbreviate(url.path, home: app.macHome)
        }
    }
}
