import AppKit
import SwiftUI

/// Drives the app through a scripted tour and writes one PNG per state, so the
/// README animation can be produced without a human at the keyboard.
/// Run with WINEXP_DEMO=<output directory>.
enum Demo {

    struct Step {
        let name: String
        let action: () -> Void
        /// How long this frame is held in the finished animation, in seconds.
        let hold: Double
    }

    private static var frame = 0
    private static var outputDir = ""

    static func run(into directory: String) {
        outputDir = directory
        try? FileManager.default.createDirectory(atPath: directory,
                                                 withIntermediateDirectories: true)
        guard let model = AppState.shared.activeModel else { return }
        let ex = model.active
        let prefs = Prefs.shared
        let settings = Settings.shared

        let steps: [Step] = [
            Step(name: "home", action: { ex.go(to: .home) }, hold: 1.6),
            Step(name: "downloads", action: { ex.go(to: Places.downloads) }, hold: 1.5),
            Step(name: "sort-size", action: {
                prefs.sortKey = .size; prefs.sortAscending = false; ex.resort()
            }, hold: 1.2),
            Step(name: "icons", action: {
                prefs.sortKey = .name; prefs.sortAscending = true; ex.resort()
                prefs.viewMode = .largeIcons
            }, hold: 1.7),
            Step(name: "details-view", action: { prefs.viewMode = .details }, hold: 0.9),
            Step(name: "select", action: {
                if let item = ex.tab.items.first(where: { !$0.isDirectory }) {
                    ex.select(item, extend: false, toggle: false)
                }
                prefs.showDetailsPane = true
            }, hold: 1.5),
            Step(name: "context-menu", action: {
                NotificationCenter.default.post(name: .demoShowMenu, object: nil)
            }, hold: 2.0),
            Step(name: "dual-pane", action: {
                NotificationCenter.default.post(name: .demoCloseMenu, object: nil)
                prefs.showDetailsPane = false
                model.toggleDual()
                model.right?.go(to: Places.home)
                model.activate(.left)
            }, hold: 1.9),
            Step(name: "shelf", action: {
                prefs.showShelf = true
                Shelf.shared.clear()
                Shelf.shared.add(Array(ex.tab.items.prefix(3)).map(\.url))
            }, hold: 1.7),
            Step(name: "archive", action: {
                prefs.showShelf = false
                if let archive = ex.tab.items.first(where: { Archives.isArchive($0.url) }) {
                    ex.go(to: .archive(archive.url, ""))
                }
            }, hold: 1.8),
            Step(name: "batch-rename", action: {
                ex.go(to: Places.downloads)
                let items = Array(ex.tab.items.prefix(6))
                if !items.isEmpty { ex.sheet = .batchRename(items) }
            }, hold: 2.0),
            Step(name: "settings", action: {
                ex.sheet = nil
                model.toggleDual()
                SettingsDialog.initialTab = 0
                ex.sheet = .settings
            }, hold: 1.7),
            Step(name: "accent", action: { settings.accentID = "green" }, hold: 1.3),
            Step(name: "light", action: { settings.theme = .light }, hold: 1.7),
            Step(name: "light-files", action: {
                ex.sheet = nil
                ex.go(to: Places.downloads)
            }, hold: 1.6),
            Step(name: "back-to-dark", action: {
                settings.theme = .dark
                settings.accentID = "blue"
            }, hold: 1.4),
        ]

        var manifest: [String] = []
        var delay = 0.6

        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                step.action()
            }
            // Give SwiftUI a beat to settle before the frame is taken.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.45) {
                capture(named: step.name)
                manifest.append("\(step.name) \(step.hold)")
            }
            delay += 0.45 + 0.35
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.6) {
            try? manifest.joined(separator: "\n")
                .write(toFile: outputDir + "/manifest.txt", atomically: true, encoding: .utf8)
            // Leave preferences the way we found them.
            prefs.viewMode = .details
            prefs.showDetailsPane = false
            prefs.showShelf = false
            Shelf.shared.clear()
            settings.theme = .system
            settings.accentID = "blue"
            NSApp.terminate(nil)
        }
    }

    private static func capture(named name: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let path = String(format: "%@/frame_%03d_%@.png", outputDir, frame, name)
        try? data.write(to: URL(fileURLWithPath: path))
        frame += 1
    }
}

extension Notification.Name {
    static let demoShowMenu = Notification.Name("winexp.demoShowMenu")
    static let demoCloseMenu = Notification.Name("winexp.demoCloseMenu")
}
