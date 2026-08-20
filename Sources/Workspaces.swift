import SwiftUI
import AppKit

// MARK: - Saved layouts

struct Workspace: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var leftPaths: [String]
    var leftActive: Int
    var rightPaths: [String]
    var rightActive: Int
    var dual: Bool
    var splitRatio: Double
    var viewMode: String
}

enum Workspaces {
    static var all: [Workspace] {
        get {
            guard let data = Store.defaults.data(forKey: "workspaces"),
                  let list = try? JSONDecoder().decode([Workspace].self, from: data)
            else { return [] }
            return list
        }
        set { Store.defaults.set(try? JSONEncoder().encode(newValue), forKey: "workspaces") }
    }

    static func capture(_ model: WindowModel, named name: String) -> Workspace {
        func paths(_ explorer: Explorer?) -> [String] {
            guard let explorer else { return [] }
            return explorer.tabs.map { tab in
                tab.location.url?.path ?? tab.location.title
            }
        }
        return Workspace(name: name,
                         leftPaths: paths(model.left),
                         leftActive: model.left.active,
                         rightPaths: paths(model.right),
                         rightActive: model.right?.active ?? 0,
                         dual: model.dual,
                         splitRatio: Double(model.splitRatio),
                         viewMode: Prefs.shared.viewMode.rawValue)
    }

    static func save(_ workspace: Workspace) {
        var list = all.filter { $0.name != workspace.name }
        list.append(workspace)
        all = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func delete(_ workspace: Workspace) {
        all = all.filter { $0.id != workspace.id }
    }

    /// Turns a stored path back into a location, including the special ones.
    static func location(for path: String) -> Location {
        switch path {
        case "Home": return .home
        case "This PC": return .thisPC
        case "Gallery": return .gallery
        case "Network": return .network
        case "Recycle Bin": return .recycleBin
        default: return .folder(URL(fileURLWithPath: path))
        }
    }

    static func restore(_ workspace: Workspace, into model: WindowModel) {
        if let mode = ViewMode(rawValue: workspace.viewMode) { Prefs.shared.viewMode = mode }
        model.applyWorkspace(workspace)
    }
}

// MARK: - Dialog

struct WorkspacesDialog: View {
    @ObservedObject var model: WindowModel
    let onClose: () -> Void

    @State private var saved = Workspaces.all
    @State private var newName = ""

    var body: some View {
        WinDialog(title: "Workspaces", width: 480, onClose: onClose) {
            VStack(alignment: .leading, spacing: 14) {
                Text("A workspace remembers the tabs open in each pane, the split, and the view mode.")
                    .font(Win.body(11)).foregroundStyle(Win.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TextField("Name this workspace", text: $newName)
                        .textFieldStyle(.plain)
                        .font(Win.body(12)).foregroundStyle(Win.text)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(WinRR(radius: 4).fill(Win.field))
                        .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
                        .onSubmit { saveCurrent() }
                    WinDialogButton(title: "Save", primary: true,
                                    enabled: !newName.trimmingCharacters(in: .whitespaces).isEmpty) {
                        saveCurrent()
                    }
                }

                if saved.isEmpty {
                    Text("Nothing saved yet.")
                        .font(Win.body(12)).foregroundStyle(Win.textSecondary)
                } else {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(saved) { workspace in
                                HStack(spacing: 10) {
                                    Glyph(icon: .gridView, size: 15,
                                          color: Win.textSecondary, weight: 1.15)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(workspace.name)
                                            .font(Win.body(12)).foregroundStyle(Win.text)
                                        Text(summary(workspace))
                                            .font(Win.body(11)).foregroundStyle(Win.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    WinButton(tooltip: "Open", padding: 8, height: 26) {
                                        Workspaces.restore(workspace, into: model)
                                        onClose()
                                    } content: {
                                        Text("Open").font(Win.body(11)).foregroundStyle(Win.text)
                                    }
                                    .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
                                    WinButton(tooltip: "Delete", padding: 6, height: 26) {
                                        Workspaces.delete(workspace)
                                        saved = Workspaces.all
                                    } content: {
                                        Glyph(icon: .delete, size: 13,
                                              color: Win.textSecondary, weight: 1.15)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 44)
                                .background(WinRR(radius: 5).fill(Win.controlFill.opacity(0.5)))
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
            .padding(18)
        } footer: {
            WinDialogButton(title: "Done", primary: true, action: onClose)
        }
    }

    private func summary(_ workspace: Workspace) -> String {
        let tabs = workspace.leftPaths.count + workspace.rightPaths.count
        let panes = workspace.dual ? "two panes" : "one pane"
        return "\(panes), \(tabs) tab\(tabs == 1 ? "" : "s")"
    }

    private func saveCurrent() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Workspaces.save(Workspaces.capture(model, named: name))
        saved = Workspaces.all
        newName = ""
    }
}
