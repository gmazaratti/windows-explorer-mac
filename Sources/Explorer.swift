import SwiftUI
import AppKit

// MARK: - Locations

enum Location: Hashable {
    case home
    case gallery
    case thisPC
    case network
    case folder(URL)
    case recycleBin
    /// Browsing inside an archive: the archive file, and the path within it.
    case archive(URL, String)

    var url: URL? {
        switch self {
        case .folder(let u): return u
        case .archive: return nil
        case .gallery: return Places.pictures
        case .network: return URL(fileURLWithPath: "/Volumes")
        case .recycleBin: return Places.trash
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .gallery: return "Gallery"
        case .thisPC: return "This PC"
        case .network: return "Network"
        case .recycleBin: return "Recycle Bin"
        case .folder(let u): return Places.displayName(for: u)
        case .archive(let archive, let inner):
            return inner.isEmpty ? archive.lastPathComponent
                                 : String(inner.split(separator: "/").last ?? "")
        }
    }

    var icon: Icon {
        switch self {
        case .home: return .home
        case .gallery: return .gallery
        case .thisPC: return .thisPC
        case .network: return .network
        case .recycleBin: return .recycleBin
        case .folder(let u): return Places.icon(for: u)
        case .archive: return .compress
        }
    }
}

// MARK: - Tab

struct TabState: Identifiable {
    let id = UUID()
    var history: [Location] = [.home]
    var index: Int = 0
    var items: [FileItem] = []
    var selection: Set<String> = []
    var anchor: String? = nil
    var lead: String? = nil
    var search: String = ""
    var searching: Bool = false
    var editing: String? = nil
    var scrollTarget: String? = nil

    var location: Location { history[min(index, history.count - 1)] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < history.count - 1 }
    var title: String { location.title }
}

// MARK: - Clipboard

enum Clipboard {
    static let cutType = NSPasteboard.PasteboardType("com.winexplorer.cut")
    private(set) static var cutPaths: Set<String> = []

    static func copy(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSPasteboardWriting])
        cutPaths = []
    }

    static func cut(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSPasteboardWriting])
        pb.setString("1", forType: cutType)
        cutPaths = Set(urls.map(\.path))
    }

    static var urls: [URL] {
        let pb = NSPasteboard.general
        let objs = pb.readObjects(forClasses: [NSURL.self],
                                  options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return objs ?? []
    }

    static var isCut: Bool { NSPasteboard.general.string(forType: cutType) == "1" }
    static var hasFiles: Bool { !urls.isEmpty }

    static func clearCut() {
        cutPaths = []
        NSPasteboard.general.clearContents()
    }
}

// MARK: - Undo

enum UndoAction {
    case rename(from: URL, to: URL)
    case move(items: [(from: URL, to: URL)])
    case create(url: URL)
    case trash(items: [(original: URL, trashed: URL)])
    case copy(created: [URL])

    var label: String {
        switch self {
        case .rename: return "Rename"
        case .move: return "Move"
        case .create: return "New"
        case .trash: return "Delete"
        case .copy: return "Copy"
        }
    }
}

// MARK: - File operations

enum Ops {
    static let fm = FileManager.default

    /// Windows-style conflict naming: "name - Copy", "name - Copy (2)", ...
    static func uniqueURL(for name: String, in dir: URL, copySuffix: Bool) -> URL {
        var candidate = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        func build(_ s: String) -> URL {
            dir.appendingPathComponent(ext.isEmpty ? s : "\(s).\(ext)")
        }
        if copySuffix {
            candidate = build("\(stem) - Copy")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            var n = 2
            while true {
                candidate = build("\(stem) - Copy (\(n))")
                if !fm.fileExists(atPath: candidate.path) { return candidate }
                n += 1
            }
        } else {
            var n = 2
            while true {
                candidate = build("\(stem) (\(n))")
                if !fm.fileExists(atPath: candidate.path) { return candidate }
                n += 1
            }
        }
    }

    @discardableResult
    static func copyItems(_ urls: [URL], to dir: URL) throws -> [URL] {
        var created: [URL] = []
        for u in urls {
            let sameDir = u.deletingLastPathComponent().path == dir.path
            let dest = uniqueURL(for: u.lastPathComponent, in: dir, copySuffix: sameDir)
            try fm.copyItem(at: u, to: dest)
            created.append(dest)
        }
        return created
    }

    @discardableResult
    static func moveItems(_ urls: [URL], to dir: URL) throws -> [(from: URL, to: URL)] {
        var moved: [(URL, URL)] = []
        for u in urls where u.deletingLastPathComponent().path != dir.path {
            let dest = uniqueURL(for: u.lastPathComponent, in: dir, copySuffix: false)
            try fm.moveItem(at: u, to: dest)
            moved.append((u, dest))
        }
        return moved
    }

    static func trash(_ urls: [URL]) -> [(original: URL, trashed: URL)] {
        var out: [(URL, URL)] = []
        for u in urls {
            var resulting: NSURL?
            do {
                try fm.trashItem(at: u, resultingItemURL: &resulting)
                if let r = resulting as URL? { out.append((u, r)) }
            } catch { NSSound.beep() }
        }
        return out
    }

    static func deleteForever(_ urls: [URL]) {
        for u in urls { try? fm.removeItem(at: u) }
    }

    static func newFolder(in dir: URL, name: String = "New folder") throws -> URL {
        let url = uniqueURL(for: name, in: dir, copySuffix: false)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func newFile(in dir: URL, name: String, contents: Data = Data()) throws -> URL {
        let url = uniqueURL(for: name, in: dir, copySuffix: false)
        guard fm.createFile(atPath: url.path, contents: contents) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    static func rename(_ url: URL, to newName: String) throws -> URL {
        let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
        if dest.path == url.path { return url }
        try fm.moveItem(at: url, to: dest)
        return dest
    }

    static func makeShortcut(for urls: [URL], in dir: URL) {
        for u in urls {
            let name = "\(u.deletingPathExtension().lastPathComponent) - Shortcut"
            let dest = uniqueURL(for: name, in: dir, copySuffix: false)
            try? fm.createSymbolicLink(at: dest, withDestinationURL: u)
        }
    }

    static func zip(_ urls: [URL], in dir: URL) {
        guard let first = urls.first else { return }
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let dest = uniqueURL(for: base + ".zip", in: dir, copySuffix: false)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-r", "-q", dest.lastPathComponent] + urls.map(\.lastPathComponent)
        try? p.run()
        p.waitUntilExit()
    }

    static func folderSize(_ url: URL) -> (bytes: Int64, files: Int, folders: Int) {
        var bytes: Int64 = 0, files = 0, folders = 0
        let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                              options: [], errorHandler: { _, _ in true })
        while let u = e?.nextObject() as? URL {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory == true { folders += 1 }
            else { files += 1; bytes += Int64(v?.fileSize ?? 0) }
        }
        return (bytes, files, folders)
    }
}

// MARK: - Model

final class Explorer: ObservableObject {
    @Published var tabs: [TabState] = [TabState()]
    @Published var active: Int = 0
    @Published var addressEditing = false
    @Published var addressText = ""
    @Published var statusMessage: String? = nil
    @Published var recentFiles: [FileItem] = []
    @Published var undoStack: [UndoAction] = []
    @Published var redoStack: [UndoAction] = []
    @Published var sheet: SheetKind? = nil
    @Published var navExpanded: Set<String> = ["thispc"]
    @Published var filterKind: String? = nil

    enum SheetKind: Identifiable {
        case properties([FileItem])
        case confirmDelete([FileItem], permanent: Bool)
        case error(String)
        case settings
        case folderIcon(FileItem)
        case batchRename([FileItem])
        case compare
        case connectServer
        case workspaces
        var id: String {
            switch self {
            case .properties(let i): return "props-\(i.count)-\(i.first?.id ?? "")"
            case .confirmDelete(let i, let p): return "del-\(p)-\(i.count)"
            case .error(let m): return "err-\(m)"
            case .settings: return "settings"
            case .folderIcon(let i): return "icon-\(i.id)"
            case .batchRename(let i): return "rename-\(i.count)"
            case .compare: return "compare"
            case .connectServer: return "connect"
            case .workspaces: return "workspaces"
            }
        }
    }

    let prefs = Prefs.shared
    /// Called whenever the user drives this pane, so the window can make it active.
    var onInteract: (() -> Void)?
    private var searchWork: DispatchWorkItem?
    private var watcher: DirectoryWatcher?

    var tab: TabState {
        get { tabs[min(active, tabs.count - 1)] }
        set { tabs[min(active, tabs.count - 1)] = newValue }
    }

    init() {
        reload()
        loadRecents()
    }

    // MARK: Loading

    func reload() {
        let loc = tab.location
        var items: [FileItem] = []
        switch loc {
        case .home:
            items = []
        case .thisPC:
            items = Loader.volumes()
        case .gallery:
            items = Loader.contents(of: Places.pictures, showHidden: prefs.showHidden)
                .filter { $0.isDirectory || $0.kind == .image || $0.kind == .video }
        case .network:
            items = Loader.contents(of: URL(fileURLWithPath: "/Volumes"), showHidden: prefs.showHidden)
        case .recycleBin:
            items = Loader.contents(of: Places.trash, showHidden: prefs.showHidden)
        case .folder(let url):
            items = Loader.contents(of: url, showHidden: prefs.showHidden)
        case .archive(let archive, let inner):
            items = Archives.children(of: archive, at: inner)
        }
        if let f = filterKind { items = items.filter { matchesFilter($0, f) } }
        tab.items = Loader.sort(items, by: prefs.sortKey, ascending: prefs.sortAscending)
        tab.selection = tab.selection.filter { p in tab.items.contains { $0.id == p } }
        watchCurrentFolder()
    }

    private func matchesFilter(_ item: FileItem, _ filter: String) -> Bool {
        switch filter {
        case "folder": return item.isDirectory && !item.isPackage
        case "document": return [.pdf, .word, .excel, .powerpoint, .text, .code].contains(item.kind)
        case "image": return item.kind == .image
        case "video": return item.kind == .video
        case "audio": return item.kind == .audio
        case "archive": return item.kind == .archive
        case "app": return item.kind == .app || item.kind == .executable
        default: return true
        }
    }

    func resort() {
        tab.items = Loader.sort(tab.items, by: prefs.sortKey, ascending: prefs.sortAscending)
    }

    private func watchCurrentFolder() {
        watcher = nil
        guard let url = tab.location.url ?? nil else { return }
        watcher = DirectoryWatcher(url: url) { [weak self] in
            guard let self else { return }
            if self.tab.editing == nil && !self.tab.searching { self.reload() }
        }
    }

    func loadRecents() {
        // Skipped in tests so the scan doesn't trigger folder-access prompts.
        if ProcessInfo.processInfo.environment["WINEXP_NORECENTS"] != nil { return }
        DispatchQueue.global(qos: .utility).async {
            var pool: [FileItem] = []
            for dir in [Places.downloads, Places.desktop, Places.documents, Places.pictures] {
                pool += Loader.contents(of: dir, showHidden: false).filter { !$0.isDirectory }
            }
            let screenshots = Places.pictures.appendingPathComponent("Screenshots")
            pool += Loader.contents(of: screenshots, showHidden: false).filter { !$0.isDirectory }
            let top = pool.sorted { $0.modified > $1.modified }.prefix(20)
            DispatchQueue.main.async { self.recentFiles = Array(top) }
        }
    }

    // MARK: Navigation

    func go(to loc: Location, newTab: Bool = false) {
        onInteract?()
        if newTab { openTab(loc); return }
        var t = tab
        if t.index < t.history.count - 1 {
            t.history.removeSubrange((t.index + 1)...)
        }
        if t.history.last != loc {
            t.history.append(loc)
            t.index = t.history.count - 1
        }
        t.selection = []
        t.search = ""
        t.searching = false
        t.editing = nil
        tab = t
        reload()
    }

    func go(to url: URL, newTab: Bool = false) { go(to: .folder(url), newTab: newTab) }

    func back() {
        guard tab.canGoBack else { NSSound.beep(); return }
        tab.index -= 1; tab.selection = []; tab.searching = false; tab.search = ""
        reload()
    }

    func forward() {
        guard tab.canGoForward else { NSSound.beep(); return }
        tab.index += 1; tab.selection = []; tab.searching = false; tab.search = ""
        reload()
    }

    var isInsideArchive: Bool {
        if case .archive = tab.location { return true }
        return false
    }

    func up() {
        switch tab.location {
        case .archive(let archive, let inner):
            if inner.isEmpty {
                go(to: archive.deletingLastPathComponent())
            } else {
                var parts = inner.split(separator: "/").map(String.init)
                parts.removeLast()
                go(to: .archive(archive, parts.joined(separator: "/")))
            }
        case .folder(let url):
            if url.path == "/" { go(to: .thisPC) }
            else { go(to: url.deletingLastPathComponent()) }
        case .gallery, .network, .recycleBin: go(to: .home)
        case .thisPC: go(to: .home)
        case .home: NSSound.beep()
        }
    }

    var canGoUp: Bool {
        if case .home = tab.location { return false }
        return true
    }

    func open(_ item: FileItem) {
        onInteract?()
        if case .archive(let archive, let inner) = tab.location {
            let entry = inner.isEmpty ? item.name : inner + "/" + item.name
            if item.isDirectory {
                go(to: .archive(archive, entry))
            } else if let staged = Archives.stage(archive, entry: entry) {
                NSWorkspace.shared.open(staged)
            } else {
                sheet = .error("Could not extract “\(item.name)” from the archive.")
            }
            return
        }
        if item.isDirectory && !item.isPackage {
            go(to: item.url)
        } else if Archives.isArchive(item.url) {
            go(to: .archive(item.url, ""))
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: Archives

    /// Extracts the whole archive, or just the selection when browsing inside one.
    func extractSelection() {
        if case .archive(let archive, let inner) = tab.location {
            let selected = selectedItems
            let destination = Archives.extractionFolder(for: archive)
            let entries = selected.map { inner.isEmpty ? $0.name : inner + "/" + $0.name }
            runExtraction(archive, entries: entries, to: destination)
            return
        }
        guard let item = selectedItems.first(where: { Archives.isArchive($0.url) }) else {
            NSSound.beep()
            return
        }
        runExtraction(item.url, entries: [], to: Archives.extractionFolder(for: item.url))
    }

    private func runExtraction(_ archive: URL, entries: [String], to destination: URL) {
        flash("Extracting \(archive.lastPathComponent)")
        DispatchQueue.global(qos: .userInitiated).async {
            let error = Archives.extract(archive, entries: entries, to: destination)
            DispatchQueue.main.async {
                if let error {
                    self.sheet = .error("Could not extract the archive.\n\(error)")
                } else {
                    self.flash("Extracted to \(destination.lastPathComponent)")
                    if self.currentDirectory == destination.deletingLastPathComponent() {
                        self.reload()
                    }
                }
            }
        }
    }

    func openSelection() {
        let sel = selectedItems
        if sel.count == 1 { open(sel[0]) }
        else { for i in sel where !(i.isDirectory && !i.isPackage) { NSWorkspace.shared.open(i.url) } }
    }

    // MARK: Tabs

    func openTab(_ loc: Location = .home) {
        var t = TabState()
        t.history = [loc]
        tabs.append(t)
        active = tabs.count - 1
        reload()
    }

    func closeTab(_ idx: Int) {
        guard tabs.count > 1 else {
            NSApp.keyWindow?.performClose(nil)
            return
        }
        tabs.remove(at: idx)
        active = min(active, tabs.count - 1)
        reload()
    }

    func nextTab() { active = (active + 1) % tabs.count; reload() }
    func prevTab() { active = (active - 1 + tabs.count) % tabs.count; reload() }
    func selectTab(_ i: Int) { guard i < tabs.count else { return }; active = i; reload() }

    // MARK: Selection

    var displayedItems: [FileItem] { tab.searching ? tab.items : tab.items }

    var selectedItems: [FileItem] { tab.items.filter { tab.selection.contains($0.id) } }

    func select(_ item: FileItem, extend: Bool, toggle: Bool) {
        onInteract?()
        var t = tab
        if toggle {
            if t.selection.contains(item.id) { t.selection.remove(item.id) }
            else { t.selection.insert(item.id) }
            t.anchor = item.id
        } else if extend, let anchor = t.anchor,
                  let a = t.items.firstIndex(where: { $0.id == anchor }),
                  let b = t.items.firstIndex(where: { $0.id == item.id }) {
            let range = a <= b ? a...b : b...a
            t.selection = Set(range.map { t.items[$0].id })
        } else {
            t.selection = [item.id]
            t.anchor = item.id
        }
        t.lead = item.id
        tab = t
    }

    /// Applies a rubber-band selection on top of whatever it started from.
    func applyMarquee(_ ids: Set<String>, base: Set<String>) {
        let combined = base.union(ids)
        if tab.selection != combined {
            onInteract?()
            tab.selection = combined
        }
    }

    func selectAll() { tab.selection = Set(tab.items.map(\.id)) }
    func selectNone() { tab.selection = [] }
    func invertSelection() {
        let all = Set(tab.items.map(\.id))
        tab.selection = all.subtracting(tab.selection)
    }

    func moveSelection(by delta: Int, extend: Bool) {
        guard !tab.items.isEmpty else { return }
        let current = tab.lead.flatMap { id in tab.items.firstIndex { $0.id == id } } ?? -1
        let next = max(0, min(tab.items.count - 1, current + delta))
        let item = tab.items[next]
        if extend { select(item, extend: true, toggle: false) }
        else { select(item, extend: false, toggle: false) }
        tab.scrollTarget = item.id
    }

    func selectFirst() {
        guard let f = tab.items.first else { return }
        select(f, extend: false, toggle: false); tab.scrollTarget = f.id
    }

    func selectLast() {
        guard let l = tab.items.last else { return }
        select(l, extend: false, toggle: false); tab.scrollTarget = l.id
    }

    /// Type-ahead: jump to the next item starting with the typed prefix.
    private(set) var typeAhead = ""
    private var typeAheadStamp = Date.distantPast

    /// Clears the type-ahead buffer (used when a view takes over the keyboard).
    func resetTypeAhead() {
        typeAhead = ""
        typeAheadStamp = .distantPast
    }
    func typeSelect(_ ch: String) {
        let now = Date()
        if now.timeIntervalSince(typeAheadStamp) > 1.0 { typeAhead = "" }
        typeAheadStamp = now
        typeAhead += ch.lowercased()
        if let hit = tab.items.first(where: { $0.displayName.lowercased().hasPrefix(typeAhead) }) {
            select(hit, extend: false, toggle: false)
            tab.scrollTarget = hit.id
        }
    }

    // MARK: Clipboard actions

    var currentDirectory: URL? {
        switch tab.location {
        case .folder(let u): return u
        case .archive: return nil
        case .gallery: return Places.pictures
        case .recycleBin: return Places.trash
        case .network: return URL(fileURLWithPath: "/Volumes")
        default: return nil
        }
    }

    func copySelection() {
        let sel = selectedItems
        guard !sel.isEmpty else { return }
        Clipboard.copy(sel.map(\.url))
        flash("\(sel.count) item\(sel.count == 1 ? "" : "s") copied")
    }

    func cutSelection() {
        let sel = selectedItems
        guard !sel.isEmpty else { return }
        Clipboard.cut(sel.map(\.url))
        flash("\(sel.count) item\(sel.count == 1 ? "" : "s") cut")
    }

    func paste() {
        guard let dir = currentDirectory else { NSSound.beep(); return }
        let urls = Clipboard.urls
        guard !urls.isEmpty else { NSSound.beep(); return }
        let cutting = Clipboard.isCut
        if cutting { Clipboard.clearCut() }
        transfer(kind: cutting ? .move : .copy, sources: urls, to: dir)
    }

    /// Hands a copy or move to the background queue and folds the result into
    /// the undo stack once it lands.
    func transfer(kind: TransferJob.Kind, sources: [URL], to destination: URL) {
        TransferQueue.shared.enqueue(kind: kind, sources: sources, to: destination) { [weak self] job in
            guard let self else { return }
            switch job.state {
            case .failed(let message):
                self.sheet = .error(message)
            case .finished:
                if !job.moved.isEmpty { self.push(.move(items: job.moved)) }
                if !job.created.isEmpty { self.push(.copy(created: job.created)) }
            default:
                break
            }
            self.reload()
            let landed = Set((job.created + job.moved.map(\.to)).map { $0.lastPathComponent })
            if !landed.isEmpty {
                self.tab.selection = Set(self.tab.items.filter { landed.contains($0.name) }.map(\.id))
            }
        }
    }

    func pasteShortcut() {
        guard let dir = currentDirectory else { return }
        Ops.makeShortcut(for: Clipboard.urls, in: dir)
        reload()
    }

    func copyPath() {
        let sel = selectedItems
        let paths = sel.isEmpty ? [currentDirectory?.path].compactMap { $0 } : sel.map { "\"\($0.url.path)\"" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: " "), forType: .string)
        flash("Path copied")
    }

    // MARK: Mutations

    func deleteSelection(permanent: Bool) {
        let sel = selectedItems
        guard !sel.isEmpty else { NSSound.beep(); return }
        if permanent {
            sheet = .confirmDelete(sel, permanent: true)
        } else {
            performDelete(sel, permanent: false)
        }
    }

    func performDelete(_ items: [FileItem], permanent: Bool) {
        if permanent {
            Ops.deleteForever(items.map(\.url))
        } else {
            let trashed = Ops.trash(items.map(\.url))
            if !trashed.isEmpty { push(.trash(items: trashed)) }
        }
        tab.selection = []
        reload()
    }

    func beginRename() {
        guard let first = selectedItems.first else { NSSound.beep(); return }
        tab.editing = first.id
    }

    func commitRename(_ item: FileItem, to newName: String) {
        tab.editing = nil
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        var final = trimmed
        // Windows keeps the extension when it is hidden in the UI.
        if !prefs.showExtensions && !item.ext.isEmpty && (trimmed as NSString).pathExtension.isEmpty {
            final = "\(trimmed).\(item.ext)"
        }
        do {
            let dest = try Ops.rename(item.url, to: final)
            push(.rename(from: item.url, to: dest))
            reload()
            tab.selection = [dest.path]
        } catch {
            sheet = .error("The file name you specified is not valid or too long.")
        }
    }

    func newFolder() {
        guard let dir = currentDirectory else { NSSound.beep(); return }
        do {
            let url = try Ops.newFolder(in: dir)
            push(.create(url: url))
            reload()
            tab.selection = [url.path]
            tab.editing = url.path
            tab.scrollTarget = url.path
        } catch { sheet = .error(error.localizedDescription) }
    }

    func newFile(named name: String, contents: Data = Data()) {
        guard let dir = currentDirectory else { NSSound.beep(); return }
        do {
            let url = try Ops.newFile(in: dir, name: name, contents: contents)
            push(.create(url: url))
            reload()
            tab.selection = [url.path]
            tab.editing = url.path
        } catch { sheet = .error(error.localizedDescription) }
    }

    /// Batch renames land on the undo stack as a single step.
    func recordBatchRename(_ renames: [(from: URL, to: URL)]) {
        guard !renames.isEmpty else { return }
        push(.move(items: renames))
        flash("Renamed \(renames.count) item\(renames.count == 1 ? "" : "s")")
    }

    func zipSelection() {
        guard let dir = currentDirectory else { return }
        let sel = selectedItems
        guard !sel.isEmpty else { return }
        Ops.zip(sel.map(\.url), in: dir)
        reload()
    }

    func showProperties() {
        let sel = selectedItems
        if sel.isEmpty, let dir = currentDirectory, let item = Loader.item(at: dir) {
            sheet = .properties([item])
        } else if !sel.isEmpty {
            sheet = .properties(sel)
        }
    }

    // MARK: Undo / redo

    private func push(_ a: UndoAction) {
        undoStack.append(a)
        redoStack.removeAll()
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func undo() {
        guard let a = undoStack.popLast() else { NSSound.beep(); return }
        switch a {
        case .rename(let from, let to):
            _ = try? Ops.rename(to, to: from.lastPathComponent)
        case .move(let items):
            for m in items.reversed() { try? Ops.fm.moveItem(at: m.to, to: m.from) }
        case .create(let url):
            _ = Ops.trash([url])
        case .trash(let items):
            for i in items.reversed() { try? Ops.fm.moveItem(at: i.trashed, to: i.original) }
        case .copy(let created):
            _ = Ops.trash(created)
        }
        redoStack.append(a)
        reload()
        flash("Undo \(a.label)")
    }

    func redo() {
        guard let a = redoStack.popLast() else { NSSound.beep(); return }
        switch a {
        case .rename(let from, let to):
            _ = try? Ops.rename(from, to: to.lastPathComponent)
        case .move(let items):
            for m in items { try? Ops.fm.moveItem(at: m.from, to: m.to) }
        case .create(let url):
            if url.pathExtension.isEmpty { try? Ops.fm.createDirectory(at: url, withIntermediateDirectories: true) }
            else { Ops.fm.createFile(atPath: url.path, contents: nil) }
        case .trash(let items):
            _ = Ops.trash(items.map(\.original))
        case .copy: break
        }
        undoStack.append(a)
        reload()
    }

    // MARK: Search

    func updateSearch(_ text: String) {
        tab.search = text
        searchWork?.cancel()
        guard !text.isEmpty else {
            tab.searching = false
            reload()
            return
        }
        let root = currentDirectory ?? Places.home
        let showHidden = prefs.showHidden
        let key = prefs.sortKey, asc = prefs.sortAscending
        let work = DispatchWorkItem { [weak self] in
            var found: [FileItem] = []
            let needle = text.lowercased()
            let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Loader.keys,
                options: showHidden ? [] : [.skipsHiddenFiles],
                errorHandler: { _, _ in true })
            var scanned = 0
            while let u = e?.nextObject() as? URL {
                scanned += 1
                if scanned > 40000 { break }
                if u.lastPathComponent.lowercased().contains(needle),
                   let item = Loader.item(at: u) {
                    found.append(item)
                    if found.count >= 1000 { break }
                }
            }
            let sorted = Loader.sort(found, by: key, ascending: asc)
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.tab.search == text else { return }
                self.tab.searching = true
                self.tab.items = sorted
                self.tab.selection = []
            }
        }
        searchWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: Status

    func flash(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }

    var statusText: String {
        if let m = statusMessage { return m }
        var n = tab.items.count
        if case .home = tab.location { n = Places.quickAccess.count + recentFiles.count }
        return "\(n) item\(n == 1 ? "" : "s")"
    }

    var selectionText: String? {
        let sel = selectedItems
        guard !sel.isEmpty else { return nil }
        let bytes = sel.reduce(Int64(0)) { $0 + $1.size }
        let sizePart = sel.contains(where: { $0.isDirectory }) ? "" : "  \(FileItem.friendlySize(bytes))"
        return "\(sel.count) item\(sel.count == 1 ? "" : "s") selected\(sizePart)"
    }

    // MARK: Breadcrumbs

    struct Crumb: Identifiable {
        let id = UUID()
        let title: String
        let location: Location
        let icon: Icon?
    }

    var breadcrumbs: [Crumb] {
        switch tab.location {
        case .home: return [Crumb(title: "Home", location: .home, icon: .home)]
        case .thisPC: return [Crumb(title: "This PC", location: .thisPC, icon: .thisPC)]
        case .gallery: return [Crumb(title: "Gallery", location: .gallery, icon: .gallery)]
        case .network: return [Crumb(title: "Network", location: .network, icon: .network)]
        case .recycleBin: return [Crumb(title: "Recycle Bin", location: .recycleBin, icon: .recycleBin)]
        case .archive(let archive, let inner):
            var crumbs = folderCrumbs(archive.deletingLastPathComponent())
            crumbs.append(Crumb(title: archive.lastPathComponent,
                                location: .archive(archive, ""), icon: .compress))
            var accumulated = ""
            for part in inner.split(separator: "/") {
                accumulated = accumulated.isEmpty ? String(part) : accumulated + "/" + part
                crumbs.append(Crumb(title: String(part),
                                    location: .archive(archive, accumulated), icon: nil))
            }
            return crumbs
        case .folder(let url):
            return folderCrumbs(url)
        }
    }

    private func folderCrumbs(_ url: URL) -> [Crumb] {
        var crumbs: [Crumb] = []
        var u = url
        while true {
            crumbs.insert(Crumb(title: Places.displayName(for: u), location: .folder(u),
                                icon: crumbs.isEmpty ? Places.icon(for: u) : nil), at: 0)
            if u.path == "/" || u.path == Places.home.path { break }
            let parent = u.deletingLastPathComponent()
            if parent.path == u.path { break }
            u = parent
        }
        crumbs.insert(Crumb(title: "This PC", location: .thisPC, icon: .thisPC), at: 0)
        return crumbs
    }

    var addressPath: String {
        currentDirectory?.path ?? tab.location.title
    }

    func navigateToTypedPath(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if text.hasPrefix("~") {
            text = Places.home.path + String(text.dropFirst())
        }
        let url = URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { go(to: url) } else { NSWorkspace.shared.open(url) }
        } else {
            sheet = .error("Windows can't find '\(raw)'. Check the spelling and try again.")
        }
    }
}

// MARK: - Live folder watching

final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init?(url: URL, onChange: @escaping () -> Void) {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        var pending = false
        s.setEventHandler {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                pending = false
                onChange()
            }
        }
        s.setCancelHandler { [fd] in close(fd) }
        s.resume()
        source = s
    }

    deinit { source?.cancel() }
}
