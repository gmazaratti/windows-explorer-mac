import SwiftUI
import AppKit

// MARK: - Windows-style dialog chrome

struct WinDialog<Content: View, Footer: View>: View {
    let title: String
    var width: CGFloat = 400
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(Win.body(13, weight: .semibold))
                    .foregroundStyle(Win.text)
                Spacer()
                CaptionButton(icon: .close, danger: true, action: onClose)
                    .frame(height: 34)
            }
            .padding(.leading, 16)
            .frame(height: 34)

            content()

            HStack(spacing: 8) {
                Spacer()
                footer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Win.chrome)
        }
        .frame(width: width)
        .background(Win.dialog)
        .clipShape(WinRR(radius: 8))
        .overlay(WinRR(radius: 8).stroke(Win.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
    }
}

struct WinDialogButton: View {
    let title: String
    var primary: Bool = false
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(title)
            .font(Win.body(12))
            .foregroundStyle(primary ? Win.textOnAccent : Win.text)
            .frame(width: 96, height: 32)
            .background(
                WinRR(radius: 4).fill(
                    primary ? (hovering ? Win.accentSecondary : Win.accent)
                            : (hovering ? Win.fieldHover : Win.controlFill))
            )
            .overlay(WinRR(radius: 4).stroke(primary ? .clear : Win.stroke, lineWidth: 1))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .onHover { hovering = $0 && enabled }
            .onTapGesture { if enabled { action() } }
    }
}

// MARK: - Properties

struct PropertiesDialog: View {
    let items: [FileItem]
    var maxHeight: CGFloat = 340
    let onClose: () -> Void
    @State private var tab = 0
    @State private var computed: (bytes: Int64, files: Int, folders: Int)?

    private var single: FileItem? { items.count == 1 ? items[0] : nil }

    private var totalBytes: Int64 {
        if let c = computed { return c.bytes }
        return items.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        WinDialog(title: "\(titleName) Properties", width: 420, onClose: onClose) {
            VStack(spacing: 0) {
                HStack(spacing: 22) {
                    ForEach(Array(["General", "Details"].enumerated()), id: \.offset) { i, name in
                        VStack(spacing: 4) {
                            Text(name)
                                .font(Win.body(12))
                                .foregroundStyle(tab == i ? Win.text : Win.textSecondary)
                            Capsule().fill(tab == i ? Win.accent : .clear).frame(height: 2)
                        }
                        .frame(width: 66)
                        .contentShape(Rectangle())
                        .onTapGesture { tab = i }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                Divider().overlay(Win.divider)

                ScrollView {
                    if tab == 0 { general } else { details }
                }
                .frame(height: min(340, maxHeight))
            }
        } footer: {
            WinDialogButton(title: "OK", primary: true, action: onClose)
            WinDialogButton(title: "Cancel", action: onClose)
        }
        .onAppear(perform: computeSize)
    }

    private var titleName: String {
        single.map { $0.displayName } ?? "\(items.count) items"
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                if let single { ItemIcon(item: single, size: 48) }
                else { FolderIcon(size: 48) }
                Text(titleName)
                    .font(Win.body(13)).foregroundStyle(Win.text).lineLimit(2)
            }
            .padding(.vertical, 16)

            Divider().overlay(Win.divider)

            VStack(spacing: 0) {
                if let single {
                    DialogRow("Type of file:", single.typeName)
                    DialogRow("Location:", single.url.deletingLastPathComponent().path)
                }
                DialogRow("Size:", "\(FileItem.friendlySize(totalBytes)) (\(FileItem.bytesText(totalBytes)))")
                if let c = computed {
                    DialogRow("Contains:", "\(c.files) Files, \(c.folders) Folders")
                }
                if let single {
                    Divider().overlay(Win.divider).padding(.vertical, 8)
                    DialogRow("Created:", single.createdText)
                    DialogRow("Modified:", single.modifiedText)
                    Divider().overlay(Win.divider).padding(.vertical, 8)
                    DialogRow("Attributes:", attributes(single))
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
    }

    private var details: some View {
        VStack(spacing: 0) {
            if let single {
                DialogRow("Name:", single.name)
                DialogRow("Item type:", single.typeName)
                DialogRow("Folder path:", single.url.deletingLastPathComponent().path)
                DialogRow("Full path:", single.url.path)
                DialogRow("Date modified:", single.modifiedText)
                DialogRow("Date created:", single.createdText)
                DialogRow("Size:", FileItem.bytesText(single.size))
                DialogRow("Owner:", NSUserName())
            } else {
                ForEach(items.prefix(30)) { i in
                    DialogRow(i.displayName, i.sizeText)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private func attributes(_ item: FileItem) -> String {
        var a: [String] = []
        if item.isHidden { a.append("Hidden") }
        if !FileManager.default.isWritableFile(atPath: item.url.path) { a.append("Read-only") }
        if item.isSymlink { a.append("Shortcut") }
        return a.isEmpty ? "None" : a.joined(separator: ", ")
    }

    private func computeSize() {
        let dirs = items.filter(\.isDirectory)
        guard !dirs.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            var bytes: Int64 = 0, files = 0, folders = 0
            for d in dirs {
                let r = Ops.folderSize(d.url)
                bytes += r.bytes; files += r.files; folders += r.folders
            }
            bytes += items.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size }
            DispatchQueue.main.async { computed = (bytes, files, folders) }
        }
    }
}

struct DialogRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(Win.body(12)).foregroundStyle(Win.textSecondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(Win.body(12)).foregroundStyle(Win.text)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Confirm delete

struct ConfirmDeleteDialog: View {
    let items: [FileItem]
    let permanent: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        WinDialog(title: permanent ? "Delete File" : "Delete", width: 440, onClose: onCancel) {
            HStack(alignment: .top, spacing: 16) {
                if let first = items.first { ItemIcon(item: first, size: 48) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(Win.body(12)).foregroundStyle(Win.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let f = items.first, items.count == 1 {
                        Text(f.displayName)
                            .font(Win.body(12, weight: .semibold)).foregroundStyle(Win.text)
                        Text("\(f.typeName)\n\(f.sizeText.isEmpty ? "" : "Size: " + f.sizeText)\nDate modified: \(f.modifiedText)")
                            .font(Win.body(11)).foregroundStyle(Win.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        } footer: {
            WinDialogButton(title: "Yes", primary: true, action: onConfirm)
            WinDialogButton(title: "No", action: onCancel)
        }
    }

    private var message: String {
        if items.count == 1 {
            return permanent
                ? "Are you sure you want to permanently delete this file?"
                : "Are you sure you want to move this file to the Recycle Bin?"
        }
        return permanent
            ? "Are you sure you want to permanently delete these \(items.count) items?"
            : "Are you sure you want to move these \(items.count) items to the Recycle Bin?"
    }
}

// MARK: - Error

struct ErrorDialog: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        WinDialog(title: "File Explorer", width: 420, onClose: onClose) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle().fill(Color(red: 0.77, green: 0.17, blue: 0.11)).frame(width: 34, height: 34)
                    Glyph(icon: .close, size: 16, color: .white, weight: 1.6)
                }
                Text(message)
                    .font(Win.body(12)).foregroundStyle(Win.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(20)
        } footer: {
            WinDialogButton(title: "OK", primary: true, action: onClose)
        }
    }
}
