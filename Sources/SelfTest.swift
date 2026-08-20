import AppKit

/// Exercises the key bindings and file operations against a throwaway folder.
/// Run with WINEXP_SELFTEST=1; the app prints results and exits.
enum SelfTest {

    private static var passed = 0
    private static var failed = 0

    static func run() {
        setvbuf(stdout, nil, _IONBF, 0)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("winexp-selftest-\(getpid())")
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        fm.createFile(atPath: root.appendingPathComponent("alpha.txt").path,
                      contents: "alpha".data(using: .utf8))
        fm.createFile(atPath: root.appendingPathComponent("beta.txt").path,
                      contents: "beta".data(using: .utf8))
        try? fm.createDirectory(at: root.appendingPathComponent("subfolder"),
                                withIntermediateDirectories: true)

        guard let ex = AppState.shared.active else {
            print("FAIL: no explorer"); exit(1)
        }
        ex.go(to: root)

        check("lists folder contents", ex.tab.items.count == 3)
        check("folders sort before files", ex.tab.items.first?.name == "subfolder")
        check("size column uses Windows KB format",
              ex.tab.items.first(where: { $0.name == "alpha.txt" })?.sizeText == "1 KB")
        check("type column uses Windows wording",
              ex.tab.items.first(where: { $0.name == "alpha.txt" })?.typeName == "Text Document")

        // Ctrl+A / Ctrl+Shift+A
        send(ex, "a", ctrl: true)
        check("Ctrl+A selects all", ex.tab.selection.count == 3)
        send(ex, "a", ctrl: true, shift: true)
        check("Ctrl+Shift+A clears selection", ex.tab.selection.isEmpty)

        // Copy / paste
        guard let alpha = ex.tab.items.first(where: { $0.name == "alpha.txt" }) else {
            print("FAIL: missing alpha.txt"); finish()
            return
        }
        ex.select(alpha, extend: false, toggle: false)
        send(ex, "c", ctrl: true)
        check("Ctrl+C fills the clipboard", Clipboard.urls.first?.lastPathComponent == "alpha.txt")

        let sub = root.appendingPathComponent("subfolder")
        ex.go(to: sub)
        send(ex, "v", ctrl: true)
        check("Ctrl+V pastes into the folder",
              fm.fileExists(atPath: sub.appendingPathComponent("alpha.txt").path))

        send(ex, "z", ctrl: true)
        check("Ctrl+Z undoes the paste",
              !fm.fileExists(atPath: sub.appendingPathComponent("alpha.txt").path))

        // New folder + rename
        send(ex, "n", ctrl: true, shift: true)
        check("Ctrl+Shift+N creates a folder",
              fm.fileExists(atPath: sub.appendingPathComponent("New folder").path))
        check("new folder enters rename mode", ex.tab.editing != nil)
        if let created = ex.tab.items.first(where: { $0.name == "New folder" }) {
            ex.commitRename(created, to: "Renamed")
            check("rename moves the item",
                  fm.fileExists(atPath: sub.appendingPathComponent("Renamed").path))
        }

        // F2
        if let item = ex.tab.items.first {
            ex.select(item, extend: false, toggle: false)
            sendCode(ex, 120)
            check("F2 starts rename", ex.tab.editing == item.id)
            sendCode(ex, 53)
            check("Escape cancels rename", ex.tab.editing == nil)
        }

        // Delete to Recycle Bin + undo
        if let item = ex.tab.items.first(where: { $0.name == "Renamed" }) {
            ex.select(item, extend: false, toggle: false)
            sendCode(ex, 117)   // forward delete == Windows Delete
            check("Delete moves to the Recycle Bin",
                  !fm.fileExists(atPath: sub.appendingPathComponent("Renamed").path))
            send(ex, "z", ctrl: true)
            check("Ctrl+Z restores from the Recycle Bin",
                  fm.fileExists(atPath: sub.appendingPathComponent("Renamed").path))
        }

        // Navigation
        sendCode(ex, 123, alt: true)
        check("Alt+Left goes back", ex.currentDirectory?.path == root.path)
        sendCode(ex, 124, alt: true)
        check("Alt+Right goes forward", ex.currentDirectory?.path == sub.path)
        sendCode(ex, 126, alt: true)
        check("Alt+Up goes to the parent", ex.currentDirectory?.path == root.path)
        sendCode(ex, 51)
        check("Backspace goes back", ex.currentDirectory?.path == sub.path)

        // Tabs
        let tabsBefore = ex.tabs.count
        send(ex, "t", ctrl: true)
        check("Ctrl+T opens a tab", ex.tabs.count == tabsBefore + 1)
        send(ex, "w", ctrl: true)
        check("Ctrl+W closes a tab", ex.tabs.count == tabsBefore)

        // View modes. Shift+digit reports "#" not "3", so these match on key code.
        sendCode(ex, KeyChord.digitCodes[3]!, ctrl: true, shift: true)
        check("Ctrl+Shift+3 selects medium icons", Prefs.shared.viewMode == .mediumIcons)
        sendCode(ex, KeyChord.digitCodes[6]!, ctrl: true, shift: true)
        check("Ctrl+Shift+6 selects details", Prefs.shared.viewMode == .details)

        // Re-mappable shortcuts
        let settings = Settings.shared
        settings.resetAllChords()
        settings.setChord(KeyChord(char: "j", ctrl: true), for: .newFolder)
        ex.go(to: sub)
        send(ex, "j", ctrl: true)
        check("a re-mapped shortcut fires its command",
              fm.fileExists(atPath: sub.appendingPathComponent("New folder").path))
        ex.tab.editing = nil
        check("re-mapping displays the new chord", settings.display(for: .newFolder) == "Ctrl+J")
        send(ex, "n", ctrl: true, shift: true)
        check("the old chord no longer fires",
              !fm.fileExists(atPath: sub.appendingPathComponent("New folder (2)").path))
        settings.setChord(KeyChord(char: "c", ctrl: true), for: .compress)
        check("a conflicting chord is taken from the other command",
              settings.chords(for: .copy).isEmpty)
        settings.resetAllChords()
        check("restoring defaults brings shortcuts back",
              settings.display(for: .copy) == "Ctrl+C" && settings.display(for: .newFolder) == "Ctrl+Shift+N")

        // Pinning
        let pinCount = Places.quickAccess.count
        settings.pin(sub)
        check("pinning adds a Quick access entry", Places.quickAccess.count == pinCount + 1)
        check("pin state is reported", settings.isPinned(sub))
        settings.unpin(sub)
        check("unpinning removes it", Places.quickAccess.count == pinCount)
        settings.unpin(Places.downloads)
        check("a default pin can be removed",
              !Places.quickAccess.contains { $0.url?.path == Places.downloads.path })
        settings.hiddenPlaces.remove(Places.downloads.path)
        check("and restored",
              Places.quickAccess.contains { $0.url?.path == Places.downloads.path })

        // Folder icons
        settings.setStyle(FolderStyle(icon: Icon.star.rawValue, tint: "4CC2FF"), for: sub)
        check("a folder icon override is stored", settings.style(for: sub)?.iconCase == .star)
        settings.setStyle(nil, for: sub)
        check("a folder icon override can be reset", settings.style(for: sub) == nil)

        // Type-ahead
        ex.go(to: root)
        send(ex, "b")
        check("type-ahead jumps to a name",
              ex.selectedItems.first?.name.lowercased().hasPrefix("b") == true)

        // Sorting
        Prefs.shared.sortKey = .size
        Prefs.shared.sortAscending = false
        ex.resort()
        check("sorting keeps folders first", ex.tab.items.first?.isDirectory == true)

        // Cut = move
        Prefs.shared.sortKey = .name
        Prefs.shared.sortAscending = true
        ex.resort()
        if let beta = ex.tab.items.first(where: { $0.name == "beta.txt" }) {
            ex.select(beta, extend: false, toggle: false)
            send(ex, "x", ctrl: true)
            ex.go(to: sub)
            send(ex, "v", ctrl: true)
            check("Ctrl+X then Ctrl+V moves the file",
                  fm.fileExists(atPath: sub.appendingPathComponent("beta.txt").path)
                  && !fm.fileExists(atPath: root.appendingPathComponent("beta.txt").path))
        }

        // Go-to-folder shortcuts
        settings.resetAllChords()
        ex.go(to: root)
        send(ex, "d", ctrl: true)
        check("Ctrl+D / Cmd+D goes to the Desktop",
              ex.currentDirectory?.path == Places.desktop.path)
        check("Ctrl+D no longer deletes", settings.chords(for: .delete).allSatisfy { $0.char != "d" })
        send(ex, "h", ctrl: true, shift: true)
        check("Ctrl+Shift+H goes Home", ex.tab.location == .home)
        ex.go(to: root)

        // Right-click routing: the catcher must actually receive right mouse
        // events while staying invisible to left clicks.
        checkRightClickRouting()

        // Search runs on a background queue, so assert once it has landed.
        ex.go(to: root)
        ex.updateSearch("alpha")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            check("search finds matching files",
                  ex.tab.searching && ex.tab.items.contains { $0.name == "alpha.txt" })
            try? fm.removeItem(at: root)
            finish()
        }
    }

    private static func checkRightClickRouting() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // SwiftUI hosting views are flipped, so mirror that here.
        window.contentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let catcher = RightClickCatcher.View(frame: NSRect(x: 40, y: 60, width: 120, height: 40))
        var received: CGPoint?
        catcher.onClick = { received = $0 }
        window.contentView?.addSubview(catcher)

        let router = RightClickRouter.shared
        router.contentFrame = CGRect(x: 0, y: 0, width: 400, height: 300)

        func rightClick(at point: CGPoint) -> NSEvent? {
            // NSEvent locations use a bottom-left origin.
            NSEvent.mouseEvent(with: .rightMouseDown,
                               location: CGPoint(x: point.x, y: 300 - point.y),
                               modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)
        }

        check("a target registers itself when added to a window",
              router.target(at: CGPoint(x: 100, y: 80), in: window) === catcher)

        if let e = rightClick(at: CGPoint(x: 100, y: 80)) {
            check("a right-click on an item is routed to it", router.route(e) && received != nil)
        } else {
            check("a right-click on an item is routed to it", false)
        }

        received = nil
        var backgroundPoint: CGPoint?
        let token = NotificationCenter.default.addObserver(
            forName: .backgroundContextMenu, object: nil, queue: .main) { note in
                backgroundPoint = note.object as? CGPoint
            }
        if let e = rightClick(at: CGPoint(x: 300, y: 250)) {
            check("a right-click on empty space opens the background menu",
                  router.route(e) && received == nil)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        check("the background menu is told where to appear", backgroundPoint != nil)
        NotificationCenter.default.removeObserver(token)

        router.contentFrame = CGRect(x: 0, y: 200, width: 400, height: 100)
        if let e = rightClick(at: CGPoint(x: 300, y: 20)) {
            check("a right-click outside the file area is ignored", !router.route(e))
        }

        catcher.removeFromSuperview()
        check("a target unregisters when it leaves the window",
              router.target(at: CGPoint(x: 100, y: 80), in: window) == nil)
        router.contentFrame = .zero
    }

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    // MARK: helpers

    private static func send(_ ex: Explorer, _ chars: String,
                             ctrl: Bool = false, shift: Bool = false, alt: Bool = false) {
        var flags: NSEvent.ModifierFlags = []
        if ctrl { flags.insert(.control) }
        if shift { flags.insert(.shift) }
        if alt { flags.insert(.option) }
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       characters: chars, charactersIgnoringModifiers: chars,
                                       isARepeat: false, keyCode: 0) else { return }
        _ = Keys.handle(e, ex: ex, editingText: false)
    }

    private static func sendCode(_ ex: Explorer, _ code: UInt16,
                                 ctrl: Bool = false, shift: Bool = false, alt: Bool = false) {
        var flags: NSEvent.ModifierFlags = []
        if ctrl { flags.insert(.control) }
        if shift { flags.insert(.shift) }
        if alt { flags.insert(.option) }
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       characters: "", charactersIgnoringModifiers: "",
                                       isARepeat: false, keyCode: code) else { return }
        _ = Keys.handle(e, ex: ex, editingText: false)
    }

    private static func check(_ name: String, _ condition: Bool) {
        if condition { passed += 1; print("  PASS  \(name)") }
        else { failed += 1; print("  FAIL  \(name)") }
    }

    private static func finish() {
        print("\n\(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
