import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A staging area: drop files in from anywhere, then drop them out somewhere
/// else. Survives navigation, which is the whole point.
final class Shelf: ObservableObject {
    static let shared = Shelf()

    @Published private(set) var items: [FileItem] = []

    private init() {
        let paths = Store.defaults.stringArray(forKey: "shelf") ?? []
        items = paths.compactMap { Loader.item(at: URL(fileURLWithPath: $0)) }
    }

    private func persist() {
        Store.defaults.set(items.map(\.url.path), forKey: "shelf")
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            if let item = Loader.item(at: url) { items.append(item) }
        }
        persist()
    }

    func remove(_ item: FileItem) {
        items.removeAll { $0.url == item.url }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    /// Drops anything that has been deleted or moved away since it was added.
    func prune() {
        let before = items.count
        items = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if items.count != before { persist() }
    }
}

struct ShelfPane: View {
    @ObservedObject var ex: Explorer
    @ObservedObject private var shelf = Shelf.shared
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Glyph(icon: .compress, size: 15, color: Win.textSecondary, weight: 1.15)
                Text("Shelf").font(Win.body(12, weight: .semibold)).foregroundStyle(Win.text)
                Spacer(minLength: 4)
                if !shelf.items.isEmpty {
                    WinButton(tooltip: "Empty the shelf", padding: 6, height: 24) {
                        shelf.clear()
                    } content: {
                        Glyph(icon: .delete, size: 13, color: Win.textSecondary, weight: 1.15)
                    }
                }
                WinButton(tooltip: "Hide the shelf", padding: 6, height: 24) {
                    Prefs.shared.showShelf = false
                } content: {
                    Glyph(icon: .tabClose, size: 11, color: Win.textSecondary, weight: 1.2)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            Divider().overlay(Win.divider)

            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Text("Drop files here to hold on to them.")
                        .font(Win.body(11)).foregroundStyle(Win.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shelf.items) { item in
                            ShelfRow(item: item, ex: ex)
                        }
                    }
                    .padding(6)
                }
            }

            Divider().overlay(Win.divider)

            HStack(spacing: 6) {
                WinButton(tooltip: "Copy everything on the shelf into this folder",
                          enabled: !shelf.items.isEmpty && ex.currentDirectory != nil,
                          padding: 8, height: 28) {
                    send(kind: .copy)
                } content: {
                    Text("Copy here").font(Win.body(11)).foregroundStyle(Win.text)
                }
                .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))

                WinButton(tooltip: "Move everything on the shelf into this folder",
                          enabled: !shelf.items.isEmpty && ex.currentDirectory != nil,
                          padding: 8, height: 28) {
                    send(kind: .move)
                } content: {
                    Text("Move here").font(Win.body(11)).foregroundStyle(Win.text)
                }
                .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
            }
            .padding(8)
        }
        .frame(width: 240)
        .background(Win.sidebar)
        .overlay(alignment: .leading) { Rectangle().fill(Win.divider).frame(width: 1) }
        .overlay(
            Rectangle()
                .strokeBorder(Win.accent.opacity(dropTargeted ? 0.9 : 0), lineWidth: 2)
                .animation(.easeOut(duration: 0.15), value: dropTargeted)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            collect(providers) { urls in Shelf.shared.add(urls) }
            return true
        }
        .onAppear { shelf.prune() }
    }

    private func send(kind: TransferJob.Kind) {
        guard let destination = ex.currentDirectory else { return }
        ex.transfer(kind: kind, sources: shelf.items.map(\.url), to: destination)
        if kind == .move { shelf.clear() }
    }

    private func collect(_ providers: [NSItemProvider], done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }
}

struct ShelfRow: View {
    let item: FileItem
    @ObservedObject var ex: Explorer
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            ItemIcon(item: item, size: 16)
            Text(item.displayName)
                .font(Win.body(11)).foregroundStyle(Win.text)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 2)
            if hovering {
                Button {
                    Shelf.shared.remove(item)
                } label: {
                    Glyph(icon: .tabClose, size: 10, color: Win.textSecondary, weight: 1.2)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(WinRR(radius: 4).fill(hovering ? Win.subtleHover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { ex.go(to: item.url.deletingLastPathComponent()) }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .help(item.url.path)
    }
}
