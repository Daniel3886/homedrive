#if DEBUG
import AppKit
import HomeDriveCore

/// Debug-only helper for checking the UI without screen-recording permission:
/// `HOMEDRIVE_SNAPSHOT=/tmp/shot` renders the main window to `/tmp/shot-N.png` a few times,
/// and with `HOMEDRIVE_SNAPSHOT_DEMO=1` it also sends and retrieves one item along the way.
@MainActor
enum DebugSnapshot {
    static func startIfRequested(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["HOMEDRIVE_SNAPSHOT"] else { return }
        let demo = env["HOMEDRIVE_SNAPSHOT_DEMO"] == "1"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            capture("\(base)-1.png")
            guard demo else { NSApp.terminate(nil); return }
            if let file = model.mac.visibleEntries.first(where: { !$0.isFolderLike && $0.size > 1_000_000 }) {
                model.mac.selection = [file.id]
                model.sendSelection()
            }
            if let file = model.pc.visibleEntries.first(where: { !$0.isFolderLike }) {
                model.pc.selection = [file.id]
                model.retrieveSelection()
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            capture("\(base)-2.png")
            model.showSettings = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            for window in NSApp.windows where window.isVisible && window.sheets.count > 0 {
                if let sheet = window.sheets.first { capture(window: sheet, to: "\(base)-3.png") }
            }
            NSApp.terminate(nil)
        }
    }

    static func capture(_ path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.sheetParent == nil })
        else { return }
        capture(window: window, to: path)
    }

    static func capture(window: NSWindow, to path: String) {
        // Render the whole frame view so the toolbar is included.
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
