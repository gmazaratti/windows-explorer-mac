import SwiftUI
import AppKit

// MARK: - Window registry

final class AppState {
    static let shared = AppState()
    private var map: [ObjectIdentifier: Explorer] = [:]
    private var windows: [NSWindow] = []

    func register(window: NSWindow, explorer: Explorer) {
        map[ObjectIdentifier(window)] = explorer
        if !windows.contains(window) { windows.append(window) }
    }

    func explorer(for window: NSWindow?) -> Explorer? {
        guard let window else { return nil }
        return map[ObjectIdentifier(window)]
    }

    var active: Explorer? {
        explorer(for: NSApp.keyWindow) ?? explorer(for: NSApp.mainWindow) ?? map.values.first
    }

    @discardableResult
    func openNewWindow(at location: Location = .home) -> NSWindow {
        let window = ExplorerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1135, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "File Explorer"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 780, height: 480)
        window.backgroundColor = NSColor(Win.chrome)

        let hosting = NSHostingView(rootView: ContentView(start: location))
        // Draw right up into the title bar area and never let content resize
        // the window (which used to push the details pane off screen).
        hosting.safeAreaRegions = []
        hosting.sizingOptions = []
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        if let last = windows.last {
            window.setFrameOrigin(NSPoint(x: last.frame.origin.x + 28, y: last.frame.origin.y - 28))
        } else {
            window.center()
        }
        clampToScreen(window)
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        return window
    }
}

/// Keeps a window fully on the active screen.
func clampToScreen(_ window: NSWindow) {
    guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
    var f = window.frame
    f.size.width = min(f.width, visible.width)
    f.size.height = min(f.height, visible.height)
    f.origin.x = min(max(f.origin.x, visible.minX), visible.maxX - f.width)
    f.origin.y = min(max(f.origin.y, visible.minY), visible.maxY - f.height)
    if f != window.frame { window.setFrame(f, display: true) }
}

/// Lets the borderless-looking window still take key/main status.
final class ExplorerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var rightClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        Settings.shared.applyTheme()
        let env = ProcessInfo.processInfo.environment
        if env["WINEXP_TEST"] == "drop" { DropHighlight.forceOn = true }
        let start: Location = env["WINEXP_START"].map { .folder(URL(fileURLWithPath: $0)) } ?? .home
        AppState.shared.openNewWindow(at: start)
        installKeyHandler()
        NSApp.activate(ignoringOtherApps: true)
        if env["WINEXP_SELFTEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { SelfTest.run() }
        }
        if let dir = env["WINEXP_DEMO"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Demo.run(into: dir) }
        }
        if let path = env["WINEXP_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.snapshot(to: path) }
        }
    }

    /// Development helper: renders the window to a PNG so the layout can be checked.
    private func snapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        if ProcessInfo.processInfo.environment["WINEXP_SNAPSHOT_EXIT"] != nil {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.openNewWindow() }
        return true
    }

    // MARK: Menu bar (kept minimal; the app's own UI carries the commands)

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About File Explorer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide File Explorer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit File Explorer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    // MARK: Keyboard

    private var editingText: Bool {
        guard let r = NSApp.keyWindow?.firstResponder else { return false }
        return r is NSTextView || r is NSTextField
    }

    private func installKeyHandler() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let ex = AppState.shared.active else { return event }
            return Keys.handle(event, ex: ex, editingText: self.editingText) ? nil : event
        }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            RightClickRouter.shared.route(event) ? nil : event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Ctrl+wheel cycles icon sizes, as in Explorer.
            guard event.modifierFlags.contains(.control) || event.modifierFlags.contains(.command) else {
                return event
            }
            let modes: [ViewMode] = [.details, .smallIcons, .mediumIcons, .largeIcons, .extraLargeIcons]
            let prefs = Prefs.shared
            let i = modes.firstIndex(of: prefs.viewMode) ?? 0
            if event.scrollingDeltaY > 0.5 { prefs.viewMode = modes[min(modes.count - 1, i + 1)] }
            else if event.scrollingDeltaY < -0.5 { prefs.viewMode = modes[max(0, i - 1)] }
            return nil
        }
    }
}

/// Windows' Win+D: hide every app so the desktop itself is showing, and put
/// them back when it is pressed again.
enum DesktopReveal {
    private static var hiddenApps: [NSRunningApplication] = []

    static func toggle() {
        if !hiddenApps.isEmpty {
            hiddenApps.forEach { $0.unhide() }
            hiddenApps = []
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && !$0.isHidden
                && $0.processIdentifier != NSRunningApplication.current.processIdentifier
        }
        hiddenApps = others
        others.forEach { $0.hide() }
        NSApp.hide(nil)
    }
}

// MARK: - Windows File Explorer key bindings
//
// Every binding is looked up in Settings, so it can be re-mapped. Both Ctrl
// (as on Windows) and Command (as Mac users expect) act as the "Ctrl"
// modifier; Option stands in for Alt.

/// Lets the settings dialog grab the next keystroke when recording a shortcut.
final class KeyCapture {
    static let shared = KeyCapture()
    var pending: ((KeyChord) -> Void)?
    var isCapturing: Bool { pending != nil }

    func consume(_ event: NSEvent) -> Bool {
        guard let handler = pending else { return false }
        if event.keyCode == 53 { pending = nil; return true }          // Esc cancels
        let chord = KeyChord.from(event)
        // A bare modifier press isn't a usable shortcut.
        guard chord.char != nil || chord.code != nil else { return true }
        pending = nil
        handler(chord)
        return true
    }
}

enum Keys {
    static func handle(_ event: NSEvent, ex: Explorer, editingText: Bool) -> Bool {
        if KeyCapture.shared.consume(event) { return true }

        let code = event.keyCode
        let shift = event.modifierFlags.contains(.shift)
        let ctrl = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
        let alt = event.modifierFlags.contains(.option)

        // While a field is being edited, only Escape is ours.
        if editingText {
            if code == 53 {
                NotificationCenter.default.post(name: .explorerCommand, object: ExplorerCommand.closeMenus)
            }
            return false
        }

        if let command = Settings.shared.command(for: event) {
            perform(command, ex: ex)
            return true
        }

        // Ctrl+1..9 jump between tabs (a convenience beyond Explorer's own set).
        if ctrl && !shift && !alt, let n = digit(code), n >= 1 {
            ex.selectTab(n == 9 ? ex.tabs.count - 1 : n - 1)
            return true
        }

        // Built-ins that aren't re-mappable.
        switch code {
        case 36, 76:                                                    // Enter
            ex.openSelection(); return true
        case 53:                                                        // Escape
            NotificationCenter.default.post(name: .explorerCommand, object: ExplorerCommand.closeMenus)
            if ex.tab.editing != nil { ex.tab.editing = nil }
            else if !ex.tab.search.isEmpty { ex.updateSearch("") }
            else { ex.selectNone() }
            return true
        case 125: ex.moveSelection(by: gridStep(down: true), extend: shift); return true
        case 126: ex.moveSelection(by: gridStep(down: false), extend: shift); return true
        case 124:
            if Prefs.shared.viewMode.isIconGrid || Prefs.shared.viewMode == .list {
                ex.moveSelection(by: 1, extend: shift)
            } else { ex.openSelection() }
            return true
        case 123:
            if Prefs.shared.viewMode.isIconGrid || Prefs.shared.viewMode == .list {
                ex.moveSelection(by: -1, extend: shift)
            } else { ex.up() }
            return true
        case 115: ex.selectFirst(); return true
        case 119: ex.selectLast(); return true
        case 116: ex.moveSelection(by: -12, extend: shift); return true
        case 121: ex.moveSelection(by: 12, extend: shift); return true
        case 49:                                                        // Space
            if let lead = ex.tab.lead, let item = ex.tab.items.first(where: { $0.id == lead }) {
                ex.select(item, extend: false, toggle: true)
                return true
            }
            return false
        default: break
        }

        // Type-ahead selection.
        if !ctrl && !alt, let s = event.characters, s.count == 1,
           let scalar = s.unicodeScalars.first,
           CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" || scalar == "-" {
            ex.typeSelect(s)
            return true
        }

        return false
    }

    static func perform(_ command: Command, ex: Explorer) {
        let prefs = Prefs.shared
        switch command {
        case .copy: ex.copySelection()
        case .cut: ex.cutSelection()
        case .paste: ex.paste()
        case .pasteShortcut: ex.pasteShortcut()
        case .copyPath: ex.copyPath()
        case .undo: ex.undo()
        case .redo: ex.redo()
        case .selectAll: ex.selectAll()
        case .selectNone: ex.selectNone()
        case .invertSelection: ex.invertSelection()
        case .rename: ex.beginRename()
        case .delete: ex.deleteSelection(permanent: false)
        case .deletePermanent: ex.deleteSelection(permanent: true)
        case .newFolder: ex.newFolder()
        case .newTextDocument: ex.newFile(named: "New Text Document.txt")
        case .compress: ex.zipSelection()
        case .createShortcut:
            if let dir = ex.currentDirectory {
                Ops.makeShortcut(for: ex.selectedItems.map(\.url), in: dir); ex.reload()
            }
        case .newTab: ex.openTab()
        case .closeTab: ex.closeTab(ex.active)
        case .nextTab: ex.nextTab()
        case .prevTab: ex.prevTab()
        case .newWindow: AppState.shared.openNewWindow(at: ex.tab.location)
        case .goHome: ex.go(to: .home)
        case .goDesktop: ex.go(to: Places.desktop)
        case .showDesktop: DesktopReveal.toggle()
        case .goDownloads: ex.go(to: Places.downloads)
        case .goDocuments: ex.go(to: Places.documents)
        case .goPictures: ex.go(to: Places.pictures)
        case .goMusic: ex.go(to: Places.music)
        case .goVideos: ex.go(to: Places.videos)
        case .goThisPC: ex.go(to: .thisPC)
        case .refresh: ex.reload()
        case .back: ex.back()
        case .forward: ex.forward()
        case .up: ex.up()
        case .focusAddress:
            NotificationCenter.default.post(name: .explorerCommand, object: ExplorerCommand.focusAddress)
        case .focusSearch:
            NotificationCenter.default.post(name: .focusSearch, object: nil)
        case .properties: ex.showProperties()
        case .openTerminal:
            if let dir = ex.currentDirectory {
                NSWorkspace.shared.open([dir],
                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                    configuration: NSWorkspace.OpenConfiguration())
            }
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting(ex.selectedItems.map(\.url))
        case .toggleHidden: prefs.showHidden.toggle(); ex.reload()
        case .toggleExtensions: prefs.showExtensions.toggle()
        case .toggleNavPane: prefs.showNavPane.toggle()
        case .toggleDetailsPane: prefs.showDetailsPane.toggle()
        case .togglePreviewPane: prefs.showPreviewPane.toggle()
        case .fullScreen: NSApp.keyWindow?.toggleFullScreen(nil)
        case .openSettings:
            NotificationCenter.default.post(name: .explorerCommand, object: ExplorerCommand.openSettings)
        case .viewExtraLarge: prefs.viewMode = .extraLargeIcons
        case .viewLarge: prefs.viewMode = .largeIcons
        case .viewMedium: prefs.viewMode = .mediumIcons
        case .viewSmall: prefs.viewMode = .smallIcons
        case .viewList: prefs.viewMode = .list
        case .viewDetails: prefs.viewMode = .details
        case .viewTiles: prefs.viewMode = .tiles
        case .viewContent: prefs.viewMode = .content
        }
    }

    private static func digit(_ code: UInt16) -> Int? {
        KeyChord.digitCodes.first { $0.value == code }?.key
    }

    /// Arrow keys move one item in list views and a whole row in icon views.
    private static func gridStep(down: Bool) -> Int {
        let mode = Prefs.shared.viewMode
        let step: Int
        switch mode {
        case .extraLargeIcons: step = 6
        case .largeIcons: step = 8
        case .mediumIcons: step = 9
        case .smallIcons: step = 5
        default: step = 1
        }
        return down ? step : -step
    }
}

