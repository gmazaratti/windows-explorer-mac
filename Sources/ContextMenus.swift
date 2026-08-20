import SwiftUI
import AppKit

enum ContextMenus {

    /// The compact icon strip Windows 11 puts at the top of item context menus.
    static func iconRow(_ ex: Explorer) -> MenuIconRow {
        let hasSel = !ex.tab.selection.isEmpty
        return MenuIconRow(items: [
            (.cut,    "Cut",    hasSel, { ex.cutSelection() }),
            (.copy,   "Copy",   hasSel, { ex.copySelection() }),
            (.rename, "Rename", ex.tab.selection.count == 1, { ex.beginRename() }),
            (.share,  "Share",           hasSel, { share(ex) }),
            (.delete, "Delete", hasSel, { ex.deleteSelection(permanent: false) }),
        ])
    }

    static func item(_ ex: Explorer) -> [MenuEntry] {
        let sel = ex.selectedItems
        let single = sel.count == 1
        let isFolder = single && sel[0].isDirectory && !sel[0].isPackage
        var entries: [MenuEntry] = []

        entries.append(MenuEntry(title: "Open", icon: .openWith, shortcut: "Enter") { ex.openSelection() })
        if isFolder {
            entries.append(MenuEntry(title: "Open in new tab", icon: .plus) {
                ex.go(to: sel[0].url, newTab: true)
            })
            entries.append(MenuEntry(title: "Open in new window") {
                AppState.shared.openNewWindow(at: .folder(sel[0].url))
            })
        } else if single {
            entries.append(MenuEntry(title: "Open with", icon: .openWith, submenu: openWithMenu(sel[0])))
        }
        if isFolder {
            let url = sel[0].url
            let settings = Settings.shared
            let pinned = settings.isPinned(url) && !settings.hiddenPlaces.contains(url.path)
            entries.append(.sep())
            entries.append(MenuEntry(title: pinned ? "Unpin from Quick access" : "Pin to Quick access",
                                     icon: pinned ? .unpin : .pin) {
                if pinned { settings.unpin(url) } else { settings.pin(url) }
            })
            entries.append(MenuEntry(title: "Change icon…", icon: .palette) {
                ex.sheet = .folderIcon(sel[0])
            })
        }
        entries.append(.sep())
        entries.append(MenuEntry(title: "Copy as path", icon: .copy,
                                 shortcut: Settings.shared.display(for: .copyPath)) { ex.copyPath() })
        entries.append(MenuEntry(title: "Compress to ZIP file", icon: .compress) { ex.zipSelection() })
        entries.append(MenuEntry(title: "Create shortcut", icon: .link) {
            guard let dir = ex.currentDirectory else { return }
            Ops.makeShortcut(for: sel.map(\.url), in: dir); ex.reload()
        })
        entries.append(MenuEntry(title: "Delete permanently", icon: .delete, shortcut: Settings.shared.display(for: .deletePermanent)) {
            ex.deleteSelection(permanent: true)
        })
        entries.append(.sep())
        entries.append(MenuEntry(title: "Show in Finder", icon: .eye) {
            NSWorkspace.shared.activateFileViewerSelecting(sel.map(\.url))
        })
        entries.append(.sep())
        entries.append(MenuEntry(title: "Properties", icon: .properties, shortcut: Settings.shared.display(for: .properties)) {
            ex.showProperties()
        })
        return entries
    }

    static func background(_ ex: Explorer) -> [MenuEntry] {
        let prefs = Prefs.shared
        return [
            MenuEntry(title: "View", icon: .view, submenu: ViewMode.allCases.map { m in
                MenuEntry(title: m.rawValue, radio: prefs.viewMode == m) { prefs.viewMode = m }
            }),
            MenuEntry(title: "Sort by", icon: .sort, submenu: SortKey.allCases.map { k in
                MenuEntry(title: k.rawValue, radio: prefs.sortKey == k) {
                    prefs.sortKey = k; ex.resort()
                }
            } + [.sep(),
                 MenuEntry(title: "Ascending", radio: prefs.sortAscending) { prefs.sortAscending = true; ex.resort() },
                 MenuEntry(title: "Descending", radio: !prefs.sortAscending) { prefs.sortAscending = false; ex.resort() }]),
            MenuEntry(title: "Refresh", icon: .refresh, shortcut: Settings.shared.display(for: .refresh)) { ex.reload() },
            .sep(),
            MenuEntry(title: "Paste", icon: .paste, shortcut: Settings.shared.display(for: .paste),
                      enabled: Clipboard.hasFiles && ex.currentDirectory != nil) { ex.paste() },
            MenuEntry(title: "Paste shortcut", icon: .link,
                      enabled: Clipboard.hasFiles && ex.currentDirectory != nil) { ex.pasteShortcut() },
            MenuEntry(title: "Undo", icon: .undo, shortcut: Settings.shared.display(for: .undo), enabled: !ex.undoStack.isEmpty) { ex.undo() },
            .sep(),
            MenuEntry(title: "Open in Terminal", icon: .terminal, enabled: ex.currentDirectory != nil) {
                guard let dir = ex.currentDirectory else { return }
                NSWorkspace.shared.open([dir],
                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                    configuration: NSWorkspace.OpenConfiguration())
            },
            .sep(),
            MenuEntry(title: "New", icon: .newItem, enabled: ex.currentDirectory != nil, submenu: [
                MenuEntry(title: "Folder", icon: .newFolder, shortcut: Settings.shared.display(for: .newFolder)) { ex.newFolder() },
                .sep(),
                MenuEntry(title: "Text Document", icon: .document) { ex.newFile(named: "New Text Document.txt") },
                MenuEntry(title: "Rich Text Document", icon: .document) { ex.newFile(named: "New Rich Text Document.rtf") },
            ]),
            .sep(),
            MenuEntry(title: "Properties", icon: .properties,
                      shortcut: Settings.shared.display(for: .properties)) { ex.showProperties() },
            MenuEntry(title: "Settings", icon: .settings,
                      shortcut: Settings.shared.display(for: .openSettings)) { ex.sheet = .settings },
        ]
    }

    private static func openWithMenu(_ item: FileItem) -> [MenuEntry] {
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: item.url)
        var entries = apps.prefix(8).map { app in
            MenuEntry(title: FileManager.default.displayName(atPath: app.path)) {
                NSWorkspace.shared.open([item.url], withApplicationAt: app,
                                        configuration: NSWorkspace.OpenConfiguration())
            }
        }
        if entries.isEmpty { entries = [MenuEntry(title: "No apps available", enabled: false)] }
        return entries
    }

    private static func share(_ ex: Explorer) {
        let urls = ex.selectedItems.map(\.url)
        guard !urls.isEmpty, let window = NSApp.keyWindow, let view = window.contentView else { return }
        NSSharingServicePicker(items: urls)
            .show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1),
                  of: view, preferredEdge: .minY)
    }
}
