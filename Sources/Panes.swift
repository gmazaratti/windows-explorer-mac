import SwiftUI
import AppKit

// MARK: - Status bar

struct StatusBar: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject private var transfers = TransferQueue.shared

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

            if transfers.hasActive {
                Button {
                    transfers.panelOpen.toggle()
                } label: {
                    HStack(spacing: 8) {
                        ProgressTrack(fraction: transfers.overallFraction)
                            .frame(width: 90, height: 4)
                        Text(transfers.summary)
                            .font(Win.body(11)).foregroundStyle(Win.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverFill(corner: 3)
                .help("Show file transfers")
                .padding(.trailing, 6)
            }

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

/// The thin Fluent progress bar used in the status bar and transfer rows.
struct ProgressTrack: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Win.controlFill)
                Capsule().fill(Win.accent)
                    .frame(width: max(2, geo.size.width * fraction))
                    .animation(.linear(duration: 0.2), value: fraction)
            }
        }
    }
}

// MARK: - Transfers

struct TransfersPanel: View {
    @ObservedObject var transfers = TransferQueue.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("File transfers")
                    .font(Win.body(13, weight: .semibold)).foregroundStyle(Win.text)
                Spacer()
                if transfers.jobs.contains(where: { !$0.isActive }) {
                    WinButton(padding: 8, height: 24) {
                        transfers.clearFinished()
                    } content: {
                        Text("Clear finished").font(Win.body(11)).foregroundStyle(Win.textSecondary)
                    }
                }
                WinButton(padding: 6, height: 24) {
                    transfers.panelOpen = false
                } content: {
                    Glyph(icon: .tabClose, size: 11, color: Win.textSecondary, weight: 1.3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().overlay(Win.divider)

            if transfers.jobs.isEmpty {
                Text("Nothing is being copied or moved.")
                    .font(Win.body(12)).foregroundStyle(Win.textTertiary)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(transfers.jobs) { job in
                            TransferRow(job: job)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(width: 400)
        .background(WinRR(radius: 8).fill(Win.flyout)
            .shadow(color: .black.opacity(0.34), radius: 16, y: 8))
        .overlay(WinRR(radius: 8).stroke(Win.stroke, lineWidth: 1))
    }
}

struct TransferRow: View {
    let job: TransferJob

    private var statusText: String {
        switch job.state {
        case .waiting: return "Waiting"
        case .running: return job.rateText.isEmpty ? job.sizeText : "\(job.sizeText)  \(job.rateText)"
        case .finished: return "Finished, \(job.filesTotal) item\(job.filesTotal == 1 ? "" : "s")"
        case .cancelled: return "Cancelled"
        case .failed(let message): return message
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Glyph(icon: job.kind == .move ? .cut : .copy, size: 16,
                  color: Win.textSecondary, weight: 1.15)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(job.kind.rawValue) to \(job.destination.map { Places.displayName(for: $0) } ?? "Recycle Bin")")
                    .font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
                if job.isActive {
                    ProgressTrack(fraction: job.fraction).frame(height: 4)
                }
                Text(job.currentName.isEmpty ? statusText : "\(job.currentName)  ·  \(statusText)")
                    .font(Win.body(11))
                    .foregroundStyle(job.state == .finished ? Win.textTertiary : Win.textSecondary)
                    .lineLimit(1)
            }

            if job.isActive {
                WinButton(tooltip: "Cancel", padding: 6, height: 24) {
                    TransferQueue.shared.cancel(job.id)
                } content: {
                    Glyph(icon: .tabClose, size: 11, color: Win.textSecondary, weight: 1.3)
                }
            } else if case .failed = job.state {
                Glyph(icon: .info, size: 14, color: Win.danger, weight: 1.2)
            } else if job.state == .finished {
                Glyph(icon: .checkmark, size: 14, color: Win.accent, weight: 1.4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
