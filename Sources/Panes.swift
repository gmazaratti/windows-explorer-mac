import SwiftUI
import AppKit

// MARK: - Status bar

struct StatusBar: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        HStack(spacing: 0) {
            Text(ex.statusText)
                .font(Win.body(12))
                .foregroundStyle(Win.textSecondary)
                .padding(.leading, 12)

            if let sel = ex.selectionText {
                Rectangle().fill(Win.divider).frame(width: 1, height: 12).padding(.horizontal, 10)
                Text(sel).font(Win.body(12)).foregroundStyle(Win.textSecondary)
            }

            Spacer(minLength: 8)

            WinButton(tooltip: "Details view (Ctrl+Shift+6)",
                      active: prefs.viewMode == .details, padding: 6, height: 22, corner: 3) {
                prefs.viewMode = .details
            } content: { Glyph(icon: .listView, size: 14, color: Win.textSecondary, weight: 1.15) }

            WinButton(tooltip: "Large icons view (Ctrl+Shift+2)",
                      active: prefs.viewMode == .largeIcons, padding: 6, height: 22, corner: 3) {
                prefs.viewMode = .largeIcons
            } content: { Glyph(icon: .gridView, size: 14, color: Win.textSecondary, weight: 1.15) }
                .padding(.trailing, 8)
        }
        .frame(height: Win.M.statusBarHeight)
        .background(Win.statusBar)
        .overlay(alignment: .top) { Rectangle().fill(Win.divider).frame(height: 1) }
    }
}

// MARK: - Details pane

struct DetailsPane: View {
    @ObservedObject var ex: Explorer

    private var item: FileItem? {
        let sel = ex.selectedItems
        if sel.count == 1 { return sel[0] }
        if sel.isEmpty, let dir = ex.currentDirectory { return Loader.item(at: dir) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ex.selectedItems.count > 1 {
                multiple
            } else if let item {
                single(item)
            } else {
                Text("Select a file to see its details.")
                    .font(Win.body(12)).foregroundStyle(Win.textTertiary)
                    .padding(16)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 300)
        .background(Win.sidebar)
        .overlay(alignment: .leading) { Rectangle().fill(Win.divider).frame(width: 1) }
    }

    private var multiple: some View {
        let sel = ex.selectedItems
        let bytes = sel.reduce(Int64(0)) { $0 + $1.size }
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(sel.count) items selected")
                .font(Win.body(14, weight: .semibold)).foregroundStyle(Win.text)
            PropRow(label: "Total size", value: FileItem.friendlySize(bytes))
            PropRow(label: "Folders", value: "\(sel.filter(\.isDirectory).count)")
            PropRow(label: "Files", value: "\(sel.filter { !$0.isDirectory }.count)")
        }
        .padding(16)
    }

    private func single(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                ItemIcon(item: item, size: 96)
                Text(item.displayName)
                    .font(Win.body(13, weight: .semibold))
                    .foregroundStyle(Win.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(item.typeName)
                    .font(Win.body(11)).foregroundStyle(Win.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)

            Divider().overlay(Win.divider)

            VStack(alignment: .leading, spacing: 12) {
                PropRow(label: "Date modified", value: item.modifiedText)
                PropRow(label: "Date created", value: item.createdText)
                if !item.isDirectory {
                    PropRow(label: "Size", value: FileItem.friendlySize(item.size))
                }
                PropRow(label: "Location", value: item.url.deletingLastPathComponent().path)
                PropRow(label: "Attributes", value: item.isHidden ? "Hidden" : "A")
            }
            .padding(16)
        }
    }
}

struct PropRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Win.body(11)).foregroundStyle(Win.textTertiary)
            Text(value).font(Win.body(12)).foregroundStyle(Win.text)
                .lineLimit(3).textSelection(.enabled)
        }
    }
}

// MARK: - Preview pane

struct PreviewPane: View {
    @ObservedObject var ex: Explorer
    @State private var image: NSImage?

    private var item: FileItem? { ex.selectedItems.first }

    var body: some View {
        VStack {
            if let item {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(12)
                } else {
                    ItemIcon(item: item, size: 96).padding(.top, 40)
                    Text("No preview available")
                        .font(Win.body(12)).foregroundStyle(Win.textTertiary).padding(.top, 8)
                }
            } else {
                Text("Select a file to preview.")
                    .font(Win.body(12)).foregroundStyle(Win.textTertiary).padding(16)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 320)
        .background(Win.sidebar)
        .overlay(alignment: .leading) { Rectangle().fill(Win.divider).frame(width: 1) }
        .onChange(of: item?.id) { _, _ in loadPreview() }
        .onAppear(perform: loadPreview)
    }

    private func loadPreview() {
        image = nil
        guard let item, !item.isDirectory else { return }
        if let cached = ThumbCache.shared.cached(item.url, size: 512) { image = cached; return }
        ThumbCache.shared.request(item.url, size: 512) { img in
            if self.item?.id == item.id { image = img }
        }
    }
}
