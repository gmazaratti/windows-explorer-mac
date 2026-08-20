import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject var ex: Explorer
    @StateObject private var menus = MenuController()
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var settings = Settings.shared
    @State private var sidebarWidth: CGFloat = Win.M.sidebarWidth

    init(start: Location = .home) {
        let e = Explorer()
        if case .home = start {} else {
            e.tabs[0].history = [start]
            e.reload()
        }
        _ex = StateObject(wrappedValue: e)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    TitleBar(ex: ex, menus: menus)
                    NavBar(ex: ex, menus: menus)
                    CommandBar(ex: ex, menus: menus)

                    HStack(spacing: 0) {
                        if prefs.showNavPane {
                            NavPane(ex: ex, menus: menus)
                                .frame(width: sidebarWidth)
                            SplitHandle(width: $sidebarWidth, min: 120, max: 380)
                        }
                        FileArea(ex: ex, menus: menus)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if prefs.showPreviewPane { PreviewPane(ex: ex) }
                        if prefs.showDetailsPane { DetailsPane(ex: ex) }
                    }
                    .frame(maxHeight: .infinity)

                    StatusBar(ex: ex)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()

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

                // Modal dialogs
                if let sheet = ex.sheet {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { }
                    dialog(sheet, maxHeight: max(200, geo.size.height - 170))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .coordinateSpace(name: "root")
            .background(Win.chrome)
            .ignoresSafeArea(.all, edges: .all)
            .onAppear { runTestHook() }
            .onReceive(NotificationCenter.default.publisher(for: .explorerCommand)) { note in
                if let cmd = note.object as? ExplorerCommand { handle(cmd) }
            }
        }
        .background(WindowAccessor { window in
            AppState.shared.register(window: window, explorer: ex)
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
            case "drop":
                DropHighlight.forceOn = true
                ex.reload()
            case "dialog:about":
                SettingsDialog.initialTab = 4
                ex.sheet = .settings
            case "settings:shortcuts":
                ex.sheet = .settings
            case "dialog:delete":
                if let first = ex.tab.items.first { ex.sheet = .confirmDelete([first], permanent: true) }
            default: break
            }
        }
    }

    @ViewBuilder
    private func dialog(_ sheet: Explorer.SheetKind, maxHeight: CGFloat) -> some View {
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
