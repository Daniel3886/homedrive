#if DEBUG
import AppKit
import HomeDriveCore

/// Debug-only helper that stages and captures the README screenshots (see docs/DEVELOPMENT.md).
///
/// Environment:
/// - `HOMEDRIVE_SNAPSHOT=/path/base`  enables it; writes `base-main.png` and `base-settings.png`, then quits
/// - `HOMEDRIVE_SNAPSHOT_RETRIEVE`    `|`-separated PC item names to retrieve first
/// - `HOMEDRIVE_SNAPSHOT_SEND`        `|`-separated Mac item names to send afterwards
/// - `HOMEDRIVE_SNAPSHOT_SELECT_MAC`  Mac item to leave selected in the picture
/// - `HOMEDRIVE_SNAPSHOT_WAIT`        seconds between starting the sends and capturing (default 3)
/// - `HOMEDRIVE_DEBUG_APPEARANCE`     `light` or `dark`
@MainActor
enum DebugSnapshot {
    static func startIfRequested(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        switch env["HOMEDRIVE_DEBUG_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        guard let base = env["HOMEDRIVE_SNAPSHOT"] else { return }
        func names(_ key: String) -> [String] {
            (env[key] ?? "").split(separator: "|").map(String.init)
        }
        let wait = Double(env["HOMEDRIVE_SNAPSHOT_WAIT"] ?? "") ?? 3

        Task { @MainActor in
            if let window = mainWindow() {
                window.setContentSize(NSSize(width: 1240, height: 720))
                window.center()
                try? await Task.sleep(for: .milliseconds(300))
                WindowLayout.balancePanes(in: window)
                WindowLayout.sizeTransfers(in: window)
            }
            try? await Task.sleep(for: .seconds(2.5))

            let retrieve = model.pc.visibleEntries.filter { names("HOMEDRIVE_SNAPSHOT_RETRIEVE").contains($0.name) }
            if !retrieve.isEmpty { model.retrieve(retrieve) }
            try? await Task.sleep(for: .seconds(1.5))

            let send = model.mac.visibleEntries.filter { names("HOMEDRIVE_SNAPSHOT_SEND").contains($0.name) }
            if !send.isEmpty { model.send(send.map { URL(fileURLWithPath: $0.path) }) }
            try? await Task.sleep(for: .seconds(wait))

            if let select = env["HOMEDRIVE_SNAPSHOT_SELECT_MAC"] {
                model.mac.selection = Set(model.mac.visibleEntries.filter { $0.name == select }.map(\.id))
            }
            model.pc.selection = []
            try? await Task.sleep(for: .seconds(0.4))
            if let window = mainWindow() { capture(window, to: "\(base)-main.png") }

            model.transfers.cancelAll()
            model.showSettings = true
            try? await Task.sleep(for: .seconds(2))
            // The sheet is its own window. Capture only that window, never what's around it.
            if let sheet = mainWindow()?.attachedSheet { capture(sheet, to: "\(base)-settings.png") }
            // Unattended run: leave straight away rather than through the normal quit path
            // (which can stop for confirmation while transfers wind down).
            exit(0)
        }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && $0.contentView != nil && $0.title == "HomeDrive" }
            ?? NSApp.windows.first { $0.isVisible && $0.sheetParent == nil }
    }

    /// Captures a window exactly as the window server draws it (toolbar, materials, shadow).
    /// Capturing your own windows needs no Screen Recording permission. The API is deprecated,
    /// so it's looked up at runtime; if it's missing we fall back to an in-process render.
    static func capture(_ window: NSWindow, to path: String) {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        var image: CGImage?
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let create = unsafeBitCast(symbol, to: CreateImage.self)
            let includingWindow: UInt32 = 1 << 3   // kCGWindowListOptionIncludingWindow: this window only
            let bestResolution: UInt32 = 1 << 3    // kCGWindowImageBestResolution
            image = create(.null, includingWindow, UInt32(window.windowNumber), bestResolution)?.takeRetainedValue()
        }
        let rep: NSBitmapImageRep
        if let image {
            rep = NSBitmapImageRep(cgImage: image)
        } else {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: cached)
            rep = cached
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
