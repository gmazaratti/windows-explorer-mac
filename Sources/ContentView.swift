import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject var model: WindowModel
    @StateObject private var menus = MenuController()
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var transfers = TransferQueue.shared
    @State private var sidebarWidth: CGFloat = Win.M.sidebarWidth

    /// The pane the chrome is currently driving.
    private var ex: Explorer { model.active }

    init(start: Location = .home) {
        _model = StateObject(wrappedValue: WindowModel(start: start))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    TitleBar(ex: ex, menus: menus)
                    NavBar(ex: ex, menus: menus)
                    CommandBar(ex: ex, model: model, menus: menus)

                    HStack(spacing: 0) {
                        if prefs.showNavPane {
                            NavPane(ex: ex, menus: menus)
                                .frame(width: sidebarWidth)
                            SplitHandle(width: $sidebarWidth, min: 120, max: 380)
                        }
                        panes()
                        if prefs.showShelf { ShelfPane(ex: ex) }
                        if prefs.showPreviewPane { PreviewPane(ex: ex) }
                        if prefs.showDetailsPane { DetailsPane(ex: ex) }
                    }
                    .frame(maxHeight: .infinity)

                    StatusBar(ex: ex)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()

                MarqueeOverlay()

                // Flyout menus
                if let open = menus.open {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { menus.close() }
                        .onRightClick { _ in menus.close() }
                    FlyoutView(open: open,
                               flipSubmenus: flyoutX(open, geo.size) + open.width + 232 > geo.size.width) {
                        menus.close()
                    }
                        .offset(x: flyoutX(open, geo.size), y: flyoutY(open, geo.size))
                        .transition(.opacity)
                }

                // Transfer queue
                if TransferQueue.shared.panelOpen {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { TransferQueue.shared.panelOpen = false }
                    TransfersPanel()
                        .offset(x: max(8, geo.size.width - 410),
                                y: max(8, geo.size.height - 360))
                }

                // Modal dialogs
                DialogHost(ex: ex, model: model, maxHeight: max(200, geo.size.height - 170))
            }
            .coordinateSpace(name: "root")
            .background(Win.chrome)
            .ignoresSafeArea(.all, edges: .all)
            .onAppear { runTestHook() }
            .onReceive(NotificationCenter.default.publisher(for: .demoShowMenu)) { _ in
                guard AppState.shared.explorer(for: NSApp.keyWindow) === ex else { return }
                menus.show(id: "demo", anchor: .zero, entries: ContextMenus.item(ex),
                           width: 260, iconRow: ContextMenus.iconRow(ex),
                           point: CGPoint(x: 430, y: 250))
            }
            .onReceive(NotificationCenter.default.publisher(for: .demoCloseMenu)) { _ in
                menus.close()
            }
            .onReceive(NotificationCenter.default.publisher(for: .explorerCommand)) { note in
                if let cmd = note.object as? ExplorerCommand { handle(cmd) }
            }
        }
        .background(WindowAccessor { window in
            AppState.shared.register(window: window, model: model)
        })
    }

    /// Development hook so layouts can be captured without driving the mouse.
    private func runTestHook() {
        guard let spec = ProcessInfo.processInfo.environment["WINEXP_TEST"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            switch spec {
            case "menu:view":
                menus.show(id: "view", anchor: CGRect(x: 400, y: 88, width: 90, height: 32),
                           entries: ContextMenus.background(ex), width: 250)
            case "menu:context":
                if let first = ex.tab.items.first { ex.select(first, extend: false, toggle: false) }
                menus.show(id: "item", anchor: .zero, entries: ContextMenus.item(ex), width: 260,
                           iconRow: ContextMenus.iconRow(ex), point: CGPoint(x: 480, y: 330))
            case "dialog:props":
                if let first = ex.tab.items.first { ex.sheet = .properties([first]) }
            case "dialog:settings":
                ex.sheet = .settings
            case "dual":
                if !model.dual { model.toggleDual() }
                Prefs.shared.showShelf = true
                if let first = ex.tab.items.first { Shelf.shared.add([first.url]) }
                model.right?.go(to: Places.home)
            case "dual-home":
                if !model.dual { model.toggleDual() }
                Prefs.shared.showShelf = true
                model.left.go(to: .home)
                model.right?.go(to: .home)
            case "rename":
                let items = Array(ex.tab.items.prefix(6))
                if !items.isEmpty { ex.sheet = .batchRename(items) }
            case "archive":
                if let zip = ex.tab.items.first(where: { Archives.isArchive($0.url) }) {
                    ex.go(to: .archive(zip.url, ""))
                }
            case "compare":
                ex.sheet = .compare
            case "commands":
                SettingsDialog.initialTab = 4
                ex.sheet = .settings
            case "marquee":
                let marquee = MarqueeController.shared
                if let zone = marquee.zone(for: ex), zone.frame.height > 120 {
                    // Start below the last row, which is where empty space is.
                    let lowest = zone.items.values.map(\.maxY).max() ?? zone.frame.minY
                    let start = CGPoint(x: zone.frame.minX + 30,
                                        y: min(zone.frame.maxY - 16, lowest + 34))
                    _ = marquee.begin(at: start, additive: false)
                    marquee.update(to: CGPoint(x: zone.frame.minX + 420,
                                               y: zone.frame.minY + 24))
                }
            case "drop":
                DropHighlight.forceOn = true
                ex.reload()
            case "dialog:about":
                SettingsDialog.initialTab = SettingsDialog.aboutTabIndex
                ex.sheet = .settings
            case "settings:shortcuts":
                ex.sheet = .settings
            case "dialog:delete":
                if let first = ex.tab.items.first { ex.sheet = .confirmDelete([first], permanent: true) }
            default: break
            }
        }
    }

    /// One pane, or two with a draggable divider between them. The split is
    /// measured against the space left for panes, not the whole window, so the
    /// shelf and the side panes do not squeeze one pane into nothing.
    @ViewBuilder
    private func panes() -> some View {
        if let right = model.right {
            GeometryReader { paneArea in
                HStack(spacing: 0) {
                    PaneView(model: model, ex: model.left, side: .left, menus: menus)
                        .frame(width: max(180, paneArea.size.width * model.splitRatio))
                    PaneDivider(model: model, available: max(1, paneArea.size.width))
                    PaneView(model: model, ex: right, side: .right, menus: menus)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            FileArea(ex: model.left, menus: menus)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Flyout placement

    private func estimatedHeight(_ open: MenuController.Open) -> CGFloat {
        var h: CGFloat = 8
        if open.iconRow != nil { h += 41 }
        for e in open.entries {
            if e.separator { h += 9 } else if e.header { h += 24 } else { h += 30 }
        }
        return h
    }

    private func flyoutX(_ open: MenuController.Open, _ size: CGSize) -> CGFloat {
        let x = open.point?.x ?? open.anchor.minX
        return max(6, min(x, size.width - open.width - 6))
    }

    private func flyoutY(_ open: MenuController.Open, _ size: CGSize) -> CGFloat {
        let h = estimatedHeight(open)
        let y = open.point?.y ?? (open.anchor.maxY + 4)
        if y + h > size.height - 6 {
            return max(6, (open.point != nil ? y - h : open.anchor.minY - h - 4))
        }
        return y
    }

    // MARK: Command dispatch (from the key handler)

    private func handle(_ cmd: ExplorerCommand) {
        guard AppState.shared.explorer(for: NSApp.keyWindow) === ex else { return }
        switch cmd {
        case .closeMenus: menus.close(); ex.addressEditing = false
        case .focusAddress:
            menus.close()
            ex.addressText = ex.addressPath
            ex.addressEditing = true
        case .openSettings:
            menus.close()
            ex.sheet = .settings
        }
    }
}

/// Hosts the modal dialogs, observing whichever pane is active.
struct DialogHost: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var model: WindowModel
    let maxHeight: CGFloat

    var body: some View {
        if let sheet = ex.sheet {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { }
                dialog(sheet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dialog(_ sheet: Explorer.SheetKind) -> some View {
        switch sheet {
        case .properties(let items):
            PropertiesDialog(items: items, maxHeight: maxHeight) { ex.sheet = nil }
        case .confirmDelete(let items, let permanent):
            ConfirmDeleteDialog(items: items, permanent: permanent,
                                onConfirm: {
                                    ex.sheet = nil
                                    ex.performDelete(items, permanent: permanent)
                                },
                                onCancel: { ex.sheet = nil })
        case .error(let message):
            ErrorDialog(message: message) { ex.sheet = nil }
        case .settings:
            SettingsDialog(ex: ex, maxHeight: maxHeight) { ex.sheet = nil }
        case .folderIcon(let item):
            FolderIconDialog(item: item) { ex.sheet = nil }
        case .batchRename(let items):
            BatchRenameDialog(ex: ex, items: items, maxHeight: maxHeight) { ex.sheet = nil }
        case .compare:
            CompareDialog(model: model, maxHeight: maxHeight) { ex.sheet = nil }
        case .connectServer:
            ConnectServerDialog { ex.sheet = nil }
        case .workspaces:
            WorkspacesDialog(model: model) { ex.sheet = nil }
        }
    }
}

/// One pane of the content area.
struct PaneView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var ex: Explorer
    let side: PaneSide
    @ObservedObject var menus: MenuController

    private var isActive: Bool { model.activeSide == side }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Glyph(icon: ex.tab.location.icon, size: 13,
                      color: isActive ? Win.accent : Win.textTertiary, weight: 1.2)
                Text(ex.tab.location.title)
                    .font(Win.body(11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Win.text : Win.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(ex.tab.items.count) items")
                    .font(Win.body(11)).foregroundStyle(Win.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(isActive ? Win.selected : Color.clear)

            FileArea(ex: ex, menus: menus)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .overlay(alignment: .top) {
            Rectangle().fill(isActive ? Win.accent : Color.clear).frame(height: 2)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.activate(side) })
    }
}

struct PaneDivider: View {
    @ObservedObject var model: WindowModel
    let available: CGFloat
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(Win.divider)
            .frame(width: 1)
            .overlay(
                Rectangle().fill(Color.clear).frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { h in
                        hovering = h
                        if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture()
                        .onChanged { g in
                            let delta = g.translation.width / available
                            model.splitRatio = min(0.8, max(0.2, model.splitRatio + delta / 12))
                        })
            )
    }
}

enum ExplorerCommand { case closeMenus, focusAddress, openSettings }

extension Notification.Name {
    static let explorerCommand = Notification.Name("winexp.command")
}

// MARK: - Split handle

struct SplitHandle: View {
    @Binding var width: CGFloat
    let min: CGFloat
    let max: CGFloat
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(Win.divider)
            .frame(width: 1)
            .overlay(
                Rectangle().fill(Color.clear).frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { h in
                        hovering = h
                        if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(coordinateSpace: .global)
                        .onChanged { g in
                            width = Swift.max(min, Swift.min(max, width + g.translation.width / 16))
                        })
            )
    }
}

// MARK: - Window access from SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
