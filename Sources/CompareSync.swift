import SwiftUI
import AppKit

// MARK: - Comparison

struct CompareEntry: Identifiable {
    enum Status: String {
        case onlyLeft = "Only on the left"
        case onlyRight = "Only on the right"
        case different = "Different"
        case same = "Identical"
    }

    var id: String { relativePath }
    let relativePath: String
    let status: Status
    let leftSize: Int64?
    let rightSize: Int64?
    let leftModified: Date?
    let rightModified: Date?
    let isDirectory: Bool
}

enum FolderCompare {
    /// Walks both trees and pairs them up by relative path.
    static func run(left: URL, right: URL) -> [CompareEntry] {
        let leftFiles = index(left)
        let rightFiles = index(right)
        var entries: [CompareEntry] = []

        for (path, l) in leftFiles {
            if let r = rightFiles[path] {
                let same = l.isDirectory == r.isDirectory
                    && (l.isDirectory || (l.size == r.size && abs(l.modified.timeIntervalSince(r.modified)) < 2))
                entries.append(CompareEntry(relativePath: path,
                                            status: same ? .same : .different,
                                            leftSize: l.size, rightSize: r.size,
                                            leftModified: l.modified, rightModified: r.modified,
                                            isDirectory: l.isDirectory))
            } else {
                entries.append(CompareEntry(relativePath: path, status: .onlyLeft,
                                            leftSize: l.size, rightSize: nil,
                                            leftModified: l.modified, rightModified: nil,
                                            isDirectory: l.isDirectory))
            }
        }
        for (path, r) in rightFiles where leftFiles[path] == nil {
            entries.append(CompareEntry(relativePath: path, status: .onlyRight,
                                        leftSize: nil, rightSize: r.size,
                                        leftModified: nil, rightModified: r.modified,
                                        isDirectory: r.isDirectory))
        }
        return entries.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private struct Entry {
        let size: Int64
        let modified: Date
        let isDirectory: Bool
    }

    private static func index(_ root: URL) -> [String: Entry] {
        // Walked by hand rather than with a prefix-stripping enumerator: the
        // enumerator reports resolved paths (/private/var) while the root may
        // be spelled /var, and the two would never line up.
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        var out: [String: Entry] = [:]
        var scanned = 0

        func walk(_ directory: URL, prefix: String) {
            guard scanned < 20000 else { return }
            let children = (try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles])) ?? []
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                scanned += 1
                if scanned > 20000 { return }
                let values = try? child.resourceValues(forKeys: Set(keys))
                let isDirectory = values?.isDirectory ?? false
                let relative = prefix.isEmpty ? child.lastPathComponent
                                              : prefix + "/" + child.lastPathComponent
                out[relative] = Entry(size: Int64(values?.fileSize ?? 0),
                                      modified: values?.contentModificationDate ?? .distantPast,
                                      isDirectory: isDirectory)
                if isDirectory { walk(child, prefix: relative) }
            }
        }

        walk(root, prefix: "")
        return out
    }
}

// MARK: - Dialog

struct CompareDialog: View {
    @ObservedObject var model: WindowModel
    var maxHeight: CGFloat = 340
    let onClose: () -> Void

    @State private var leftURL: URL?
    @State private var rightURL: URL?
    @State private var entries: [CompareEntry] = []
    @State private var scanning = false
    @State private var differencesOnly = true
    @State private var scanned = false

    private var shown: [CompareEntry] {
        differencesOnly ? entries.filter { $0.status != .same } : entries
    }

    private var counts: (left: Int, right: Int, diff: Int) {
        (entries.filter { $0.status == .onlyLeft }.count,
         entries.filter { $0.status == .onlyRight }.count,
         entries.filter { $0.status == .different }.count)
    }

    var body: some View {
        WinDialog(title: "Compare and sync folders", width: 680, onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                folderPickers
                Divider().overlay(Win.divider)
                results
            }
        } footer: {
            WinDialogButton(title: "Copy right", enabled: canSync) {
                sync(fromLeft: true)
            }
            WinDialogButton(title: "Copy left", enabled: canSync) {
                sync(fromLeft: false)
            }
            WinDialogButton(title: "Close", primary: true, action: onClose)
        }
        .onAppear {
            leftURL = model.left.currentDirectory
            rightURL = model.right?.currentDirectory
        }
    }

    private var canSync: Bool {
        leftURL != nil && rightURL != nil && !shown.isEmpty && !scanning
    }

    private var folderPickers: some View {
        VStack(spacing: 10) {
            FolderPickerRow(title: "Left", url: $leftURL)
            FolderPickerRow(title: "Right", url: $rightURL)
            HStack(spacing: 12) {
                WinDialogButton(title: scanning ? "Comparing…" : "Compare",
                                primary: true,
                                enabled: leftURL != nil && rightURL != nil && !scanning) {
                    compare()
                }
                HStack(spacing: 7) {
                    WinCheckbox(checked: differencesOnly) { differencesOnly.toggle() }
                    Text("Differences only").font(Win.body(12)).foregroundStyle(Win.text)
                }
                Spacer()
                if scanned {
                    Text("\(counts.left) only left · \(counts.right) only right · \(counts.diff) differ")
                        .font(Win.body(11)).foregroundStyle(Win.textSecondary)
                }
            }
        }
        .padding(16)
    }

    private var results: some View {
        Group {
            if !scanned {
                Text("Pick two folders and compare them.")
                    .font(Win.body(12)).foregroundStyle(Win.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else if shown.isEmpty {
                Text(differencesOnly ? "The folders match." : "Both folders are empty.")
                    .font(Win.body(12)).foregroundStyle(Win.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(shown) { entry in
                            HStack(spacing: 10) {
                                Glyph(icon: entry.isDirectory ? .folderOutline : .document,
                                      size: 14, color: Win.textSecondary, weight: 1.15)
                                Text(entry.relativePath)
                                    .font(Win.body(12)).foregroundStyle(Win.text)
                                    .lineLimit(1)
                                Spacer(minLength: 12)
                                Text(entry.status.rawValue)
                                    .font(Win.body(11))
                                    .foregroundStyle(colour(entry.status))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 26)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: min(260, maxHeight - 60))
            }
        }
    }

    private func colour(_ status: CompareEntry.Status) -> Color {
        switch status {
        case .onlyLeft, .onlyRight: return Win.accent
        case .different: return Win.danger
        case .same: return Win.textTertiary
        }
    }

    private func compare() {
        guard let left = leftURL, let right = rightURL else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FolderCompare.run(left: left, right: right)
            DispatchQueue.main.async {
                entries = result
                scanning = false
                scanned = true
            }
        }
    }

    /// One-way sync: everything missing or newer on the source goes to the target.
    private func sync(fromLeft: Bool) {
        guard let left = leftURL, let right = rightURL else { return }
        let source = fromLeft ? left : right
        let target = fromLeft ? right : left
        let wanted: CompareEntry.Status = fromLeft ? .onlyLeft : .onlyRight

        var byFolder: [URL: [URL]] = [:]
        for entry in entries where entry.status == wanted || entry.status == .different {
            if entry.status == .different && entry.isDirectory { continue }
            let from = source.appendingPathComponent(entry.relativePath)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            let destination = target.appendingPathComponent(entry.relativePath)
                .deletingLastPathComponent()
            // Nested folders that are copied whole don't need their children queued.
            if entry.isDirectory {
                byFolder[destination, default: []].append(from)
            } else {
                let parentCopied = byFolder.values.flatMap { $0 }
                    .contains { from.path.hasPrefix($0.path + "/") }
                if !parentCopied { byFolder[destination, default: []].append(from) }
            }
        }

        guard !byFolder.isEmpty else { NSSound.beep(); return }
        for (destination, sources) in byFolder {
            try? FileManager.default.createDirectory(at: destination,
                                                     withIntermediateDirectories: true)
            // Replace differing files rather than making " - Copy" duplicates.
            for source in sources {
                let existing = destination.appendingPathComponent(source.lastPathComponent)
                if FileManager.default.fileExists(atPath: existing.path) {
                    _ = Ops.trash([existing])
                }
            }
            TransferQueue.shared.enqueue(kind: .copy, sources: sources, to: destination)
        }
        onClose()
    }
}

struct FolderPickerRow: View {
    let title: String
    @Binding var url: URL?

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Win.body(12)).foregroundStyle(Win.textSecondary)
                .frame(width: 44, alignment: .leading)
            Text(url?.path ?? "Choose a folder")
                .font(Win.body(12))
                .foregroundStyle(url == nil ? Win.textTertiary : Win.text)
                .lineLimit(1).truncationMode(.head)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .background(WinRR(radius: 4).fill(Win.field))
                .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
            WinButton(padding: 10, height: 28) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Choose"
                panel.begin { response in
                    if response == .OK, let picked = panel.url { url = picked }
                }
            } content: {
                Text("Browse").font(Win.body(11)).foregroundStyle(Win.text)
            }
            .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
        }
    }
}
