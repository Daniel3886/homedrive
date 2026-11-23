import AppKit

/// Small AppKit touches SwiftUI doesn't expose.
@MainActor
enum WindowLayout {
    /// Splits the two file panes evenly around the narrow Send/Retrieve column.
    /// (`HSplitView` otherwise gives all spare width to the first pane.)
    static func balancePanes(in window: NSWindow?) {
        guard let root = window?.contentView,
              let split = find(NSSplitView.self, in: root, where: { $0.isVertical && $0.arrangedSubviews.count == 3 })
        else { return }
        let middle = split.arrangedSubviews[1].frame.width
        let pane = (split.bounds.width - middle - 2 * split.dividerThickness) / 2
        split.setPosition(pane, ofDividerAt: 0)
        split.setPosition(pane + split.dividerThickness + middle, ofDividerAt: 1)
    }

    /// Gives keyboard focus to the first file list, so arrow keys work straight away
    /// (and no stray focus ring lands on a toolbar button).
    static func focusFirstTable(in window: NSWindow?) {
        guard let window, let root = window.contentView,
              let table = find(NSTableView.self, in: root, where: { _ in true }) else { return }
        window.makeFirstResponder(table)
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView, where match: (T) -> Bool) -> T? {
        if let v = view as? T, match(v) { return v }
        for sub in view.subviews {
            if let found = find(type, in: sub, where: match) { return found }
        }
        return nil
    }
}
