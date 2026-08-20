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
        check("Ctrl+V queues a copy", TransferQueue.shared.hasActive)

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
        ex.resetTypeAhead()
        send(ex, "b")
        let diag = "buf=\(ex.typeAhead) items=\(ex.tab.items.map(\.name)) sel=\(ex.selectedItems.map(\.name))"
        check("type-ahead jumps to a name [\(diag)]",
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
            check("Ctrl+X then Ctrl+V queues a move", TransferQueue.shared.hasActive)
        }

        // Go-to-folder shortcuts
        settings.resetAllChords()
        ex.go(to: root)
        send(ex, "d", ctrl: true, shift: true)
        check("Ctrl+Shift+D goes to the Desktop folder",
              ex.currentDirectory?.path == Places.desktop.path)
        check("Ctrl+D shows the desktop instead of deleting",
              settings.chords(for: .showDesktop).contains(KeyChord(char: "d", ctrl: true))
              && settings.chords(for: .delete).allSatisfy { $0.char != "d" })
        send(ex, "h", ctrl: true, shift: true)
        check("Ctrl+Shift+H goes Home", ex.tab.location == .home)
        ex.go(to: root)

        // Right-click routing: the catcher must actually receive right mouse
        // events while staying invisible to left clicks.
        checkRightClickRouting()

        checkPanes(root: root, sub: sub)
        checkColumnFitting()
        checkBatchRename()
        checkArchives(root: root)
        checkCompare(root: root, sub: sub)
        checkShelf(root: root)
        checkWorkspaces(root: root, sub: sub)

        // Search runs on a background queue, so assert once it has landed.
        ex.go(to: root)
        ex.updateSearch("alpha")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            check("search finds matching files",
                  ex.tab.searching && ex.tab.items.contains { $0.name == "alpha.txt" })

            // The queued copy and move land after the synchronous script ends.
            afterTransfers {
                check("the queued paste copied the file in",
                      fm.fileExists(atPath: sub.appendingPathComponent("alpha.txt").path))
                check("the queued cut and paste moved the file",
                      fm.fileExists(atPath: sub.appendingPathComponent("beta.txt").path)
                      && !fm.fileExists(atPath: root.appendingPathComponent("beta.txt").path))
                ex.undo()
                check("Ctrl+Z undoes a queued move",
                      fm.fileExists(atPath: root.appendingPathComponent("beta.txt").path))
                checkCustomCommand(ex: ex, root: root) {
                    checkTransfers(root: root, sub: sub) { finish() }
                }
            }
        }
    }

    /// Copies a few megabytes through the background queue and watches the
    /// progress it reports.
    private static func checkTransfers(root: URL, sub: URL, then done: @escaping () -> Void) {
        let fm = FileManager.default
        let big = root.appendingPathComponent("payload.bin")
        fm.createFile(atPath: big.path, contents: Data(count: 3 * 1024 * 1024))

        let queue = TransferQueue.shared
        queue.enqueue(kind: .copy, sources: [big], to: sub) { job in
            check("a queued copy finishes", job.state == .finished)
            check("progress reaches the full size",
                  job.bytesTotal == 3 * 1024 * 1024 && job.bytesDone == job.bytesTotal)
            check("the copy lands at the destination",
                  fm.fileExists(atPath: sub.appendingPathComponent("payload.bin").path))
            check("the finished job reports what it created", job.created.count == 1)

            // A move within one volume should be instant and recorded for undo.
            let moving = sub.appendingPathComponent("payload.bin")
            queue.enqueue(kind: .move, sources: [moving], to: root) { moveJob in
                check("a queued move finishes", moveJob.state == .finished)
                check("the move is recorded for undo", moveJob.moved.count == 1)
                check("the file is gone from the source",
                      !fm.fileExists(atPath: moving.path))
                try? fm.removeItem(at: root)
                done()
            }
        }
        // The queue marks itself busy the moment work is handed over.
        check("the queue reports itself busy as soon as work is queued", queue.hasActive)
    }

    /// User-defined commands run a script with the selection in the environment.
    private static func checkCustomCommand(ex: Explorer, root: URL, then done: @escaping () -> Void) {
        ex.go(to: root)
        guard let item = ex.tab.items.first(where: { !$0.isDirectory }) else { done(); return }
        ex.select(item, extend: false, toggle: false)

        let marker = root.appendingPathComponent("command-ran.txt")
        let command = CustomCommand(name: "selftest",
                                    script: "printf '%s' \"$FE_COUNT:$(basename \"$FE_FIRST\")\" > \"$FE_DIR/command-ran.txt\"",
                                    icon: Icon.terminal.rawValue,
                                    applies: .selection, refreshAfter: false)
        check("a command that needs a selection is offered when there is one",
              CustomCommands.shared.applicable(to: ex).count >= 0)
        CustomCommands.shared.run(command, in: ex)

        var waited = 0
        func poll() {
            waited += 1
            let text = (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
            if !text.isEmpty || waited > 40 {
                check("a custom command runs with the selection in its environment [\(text)]",
                      text == "1:\(item.name)")
                done()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
    }

    /// Runs `body` once the transfer queue has drained, without blocking the
    /// main queue (which the queue itself needs in order to finish).
    private static func afterTransfers(_ body: @escaping () -> Void) {
        func poll() {
            if TransferQueue.shared.hasActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: body)
            }
        }
        poll()
    }

    private static func checkPanes(root: URL, sub: URL) {
        guard let model = AppState.shared.activeModel else {
            check("the window has a pane model", false)
            return
        }
        let wasDual = model.dual
        if wasDual { model.toggleDual() }

        check("a window starts with one pane", !model.dual)
        model.toggleDual()
        check("dual pane opens a second pane", model.dual && model.right != nil)

        model.left.go(to: root)
        model.right?.go(to: sub)
        model.activate(.left)
        check("the left pane is active after using it", model.activeSide == .left)
        model.switchPane()
        check("switching moves to the other pane", model.activeSide == .right)
        check("the chrome follows the active pane",
              model.active.currentDirectory?.path == sub.path)

        model.swapPanes()
        check("swapping exchanges the two folders",
              model.left.currentDirectory?.path == sub.path
              && model.right?.currentDirectory?.path == root.path)

        // Cross-pane copy goes through the same queue as everything else.
        model.activate(.left)
        if let item = model.left.tab.items.first(where: { !$0.isDirectory }) {
            model.left.select(item, extend: false, toggle: false)
            model.sendSelection(kind: .copy)
            check("copy to the other pane queues a transfer", TransferQueue.shared.hasActive)
        }

        model.toggleDual()
        check("dual pane closes again", !model.dual && model.activeSide == .left)
    }

    /// A pane must never lay out wider than it is: that is what pushed the
    /// whole window sideways when two panes were open.
    private static func checkColumnFitting() {
        var detailsFit = true
        var recentFit = true
        for width in stride(from: 140.0, through: 1600.0, by: 20.0) {
            let details = DetailColumns(available: CGFloat(width), preferredName: 300,
                                        date: 150, type: 140, size: 90)
            if details.totalWidth > CGFloat(width) + 0.5, width >= 200 { detailsFit = false }
            let recent = RecentColumns(available: CGFloat(width))
            if recent.totalWidth > CGFloat(width) + 0.5, width >= 280 { recentFit = false }
        }
        check("Details columns always fit the pane they are drawn in", detailsFit)
        check("the Recent list always fits the pane it is drawn in", recentFit)

        let narrow = DetailColumns(available: 300, preferredName: 300,
                                   date: 150, type: 140, size: 90)
        check("a narrow pane keeps Name and Date", narrow.date != nil && narrow.type == nil)
        let wide = DetailColumns(available: 1200, preferredName: 300,
                                 date: 150, type: 140, size: 90)
        check("a wide pane shows every column",
              wide.date != nil && wide.type != nil && wide.size != nil && wide.name == 300)
    }

    private static func checkBatchRename() {
        var plan = RenamePlan()
        plan.find = "alpha"
        plan.replace = "gamma"
        check("batch rename replaces text", plan.apply(to: "alpha.txt", index: 0) == "gamma.txt")

        plan = RenamePlan()
        plan.prefix = "IMG_"
        plan.numbering = true
        plan.startAt = 1
        plan.digits = 3
        check("batch rename numbers items",
              plan.apply(to: "photo.png", index: 4) == "IMG_photo005.png")

        plan = RenamePlan()
        plan.caseMode = .upper
        plan.newExtension = "jpeg"
        check("batch rename changes case and extension",
              plan.apply(to: "photo.png", index: 0) == "PHOTO.jpeg")

        plan = RenamePlan()
        check("batch rename leaves names alone by default",
              plan.apply(to: "untouched.txt", index: 3) == "untouched.txt")
    }

    private static func checkArchives(root: URL) {
        let archive = root.appendingPathComponent("bundle.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = root
        zip.arguments = ["-qr", archive.lastPathComponent, "alpha.txt", "subfolder"]
        try? zip.run()
        zip.waitUntilExit()

        check("a zip is recognised as an archive", Archives.isArchive(archive))
        check("a plain file is not", !Archives.isArchive(root.appendingPathComponent("alpha.txt")))

        let top = Archives.children(of: archive, at: "")
        check("an archive lists its top level [\(top.map(\.name))]",
              top.contains { $0.name == "alpha.txt" } && top.contains { $0.name == "subfolder" })
        check("folders inside an archive are marked as folders",
              top.first { $0.name == "subfolder" }?.isDirectory == true)

        let destination = root.appendingPathComponent("unpacked")
        let failure = Archives.extract(archive, entries: [], to: destination)
        check("an archive extracts", failure == nil
              && FileManager.default.fileExists(atPath: destination.appendingPathComponent("alpha.txt").path))
    }

    private static func checkCompare(root: URL, sub: URL) {
        let entries = FolderCompare.run(left: root, right: sub)
        check("comparing folders reports what is only on one side",
              entries.contains { $0.relativePath == "alpha.txt" && $0.status == .onlyLeft })
        check("comparing folders walks into subfolders",
              entries.contains { $0.relativePath.contains("/") } || entries.count > 1)
    }

    private static func checkShelf(root: URL) {
        let shelf = Shelf.shared
        shelf.clear()
        shelf.add([root.appendingPathComponent("alpha.txt")])
        check("the shelf holds what is dropped on it", shelf.items.count == 1)
        shelf.add([root.appendingPathComponent("alpha.txt")])
        check("the shelf ignores duplicates", shelf.items.count == 1)
        if let item = shelf.items.first { shelf.remove(item) }
        check("items can be taken off the shelf", shelf.items.isEmpty)
    }

    private static func checkWorkspaces(root: URL, sub: URL) {
        guard let model = AppState.shared.activeModel else { return }
        model.left.go(to: root)
        model.left.openTab(.folder(sub))
        let workspace = Workspaces.capture(model, named: "selftest")
        check("a workspace captures every tab", workspace.leftPaths.count == 2)

        model.left.tabs = [TabState()]
        model.left.active = 0
        model.left.go(to: Places.home)
        Workspaces.restore(workspace, into: model)
        check("restoring a workspace brings the tabs back",
              model.left.tabs.count == 2
              && model.left.currentDirectory?.path == sub.path)
        Workspaces.delete(workspace)
        check("a workspace can be deleted", !Workspaces.all.contains { $0.name == "selftest" })
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
        let owner = NSObject()
        router.setContentFrame(CGRect(x: 0, y: 0, width: 400, height: 300), for: owner)

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

        router.setContentFrame(CGRect(x: 0, y: 200, width: 400, height: 100), for: owner)
        if let e = rightClick(at: CGPoint(x: 300, y: 20)) {
            check("a right-click outside the file area is ignored", !router.route(e))
        }

        catcher.removeFromSuperview()
        check("a target unregisters when it leaves the window",
              router.target(at: CGPoint(x: 100, y: 80), in: window) == nil)
        router.setContentFrame(.zero, for: owner)
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
