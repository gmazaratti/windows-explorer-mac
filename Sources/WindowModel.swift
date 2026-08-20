import SwiftUI
import AppKit

enum PaneSide: String, Hashable { case left, right }

/// A window holds one or two panes. Everything in the chrome (address bar,
/// command bar, navigation pane) acts on whichever pane is active.
final class WindowModel: ObservableObject {
    @Published private(set) var left: Explorer
    @Published private(set) var right: Explorer?
    @Published private(set) var activeSide: PaneSide = .left
    /// Fraction of the width given to the left pane.
    @Published var splitRatio: CGFloat = 0.5

    var dual: Bool { right != nil }
    var active: Explorer { activeSide == .right ? (right ?? left) : left }
    var other: Explorer? { dual ? (activeSide == .right ? left : right) : nil }

    init(start: Location = .home) {
        let pane = Explorer()
        if case .home = start {} else {
            pane.tabs[0].history = [start]
            pane.reload()
        }
        left = pane
        pane.onInteract = { [weak self] in self?.activate(.left) }
        if Prefs.shared.dualPane { enableDual() }
    }

    func activate(_ side: PaneSide) {
        guard activeSide != side, side == .left || right != nil else { return }
        activeSide = side
    }

    func explorer(for side: PaneSide) -> Explorer? {
        side == .left ? left : right
    }

    // MARK: Toggling

    func toggleDual() {
        if dual { disableDual() } else { enableDual() }
        Prefs.shared.dualPane = dual
    }

    private func enableDual() {
        guard right == nil else { return }
        let pane = Explorer()
        // Open the second pane where the first one is, which is what people expect.
        pane.tabs[0].history = [left.tab.location]
        pane.reload()
        pane.onInteract = { [weak self] in self?.activate(.right) }
        right = pane
    }

    private func disableDual() {
        right = nil
        activeSide = .left
    }

    func switchPane() {
        guard dual else { return }
        activeSide = activeSide == .left ? .right : .left
    }

    func swapPanes() {
        guard let rightPane = right else { return }
        let leftLocation = left.tab.location
        left.go(to: rightPane.tab.location)
        rightPane.go(to: leftLocation)
    }

    // MARK: Workspaces

    func applyWorkspace(_ workspace: Workspace) {
        restore(workspace.leftPaths, activeTab: workspace.leftActive, into: left)
        if workspace.dual {
            if right == nil { toggleDual() }
            if let pane = right {
                restore(workspace.rightPaths, activeTab: workspace.rightActive, into: pane)
            }
        } else if right != nil {
            toggleDual()
        }
        splitRatio = CGFloat(workspace.splitRatio)
        activeSide = .left
    }

    private func restore(_ paths: [String], activeTab: Int, into pane: Explorer) {
        guard !paths.isEmpty else { return }
        var tabs: [TabState] = []
        for path in paths {
            var tab = TabState()
            tab.history = [Workspaces.location(for: path)]
            tabs.append(tab)
        }
        pane.tabs = tabs
        pane.active = min(max(0, activeTab), tabs.count - 1)
        pane.reload()
    }

    // MARK: Cross-pane transfers

    var otherDirectory: URL? { other?.currentDirectory }

    func sendSelection(kind: TransferJob.Kind) {
        guard let destination = otherDirectory else { NSSound.beep(); return }
        let sources = active.selectedItems.map(\.url)
        guard !sources.isEmpty else { NSSound.beep(); return }
        active.transfer(kind: kind, sources: sources, to: destination)
    }
}
