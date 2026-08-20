import SwiftUI
import AppKit

struct HomeView: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    @State private var quickExpanded = true
    @State private var recentExpanded = true
    @State private var recentTab = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Quick access", expanded: $quickExpanded)
                    .padding(.top, 10)

                if quickExpanded {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 460), spacing: 4)],
                              alignment: .leading, spacing: 4) {
                        ForEach(quickItems) { place in
                            QuickTile(place: place, ex: ex)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }

                HStack(spacing: 10) {
                    Button {
                        recentExpanded.toggle()
                    } label: {
                        Glyph(icon: recentExpanded ? .chevronDown : .chevronRight,
                              size: 13, color: Win.textSecondary, weight: 1.3)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .hoverFill()

                    Pill(title: "Recent", icon: .clock, selected: recentTab == 0) { recentTab = 0 }
                    Pill(title: "Favorites", icon: .star, selected: recentTab == 1) { recentTab = 1 }
                    Pill(title: "Shared", icon: .people, selected: recentTab == 2) { recentTab = 2 }
                }
                .padding(.leading, 8)
                .padding(.top, 20)

                if recentExpanded {
                    RecentTable(ex: ex, menus: menus, tab: recentTab)
                        .padding(.top, 10)
                }
                Color.clear.frame(height: 24)
            }
        }
    }

    @ObservedObject private var settings = Settings.shared

    private var quickItems: [Place] {
        var list = Places.quickAccess
        // Windows also surfaces frequently used folders below the pinned ones.
        let extras = Loader.contents(of: Places.home, showHidden: false)
            .filter { $0.isDirectory && !$0.isPackage }
            .filter { d in !list.contains { $0.url?.path == d.url.path } }
            .sorted { $0.modified > $1.modified }
            .prefix(3)
        for e in extras {
            list.append(Place(id: e.id, title: e.name, icon: .folderOutline, url: e.url,
                              pinned: false, accent: .neutral))
        }
        return list
    }
}

struct SectionHeader: View {
    let title: String
    @Binding var expanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Glyph(icon: expanded ? .chevronDown : .chevronRight, size: 13,
                  color: Win.textSecondary, weight: 1.3)
            Text(title)
                .font(Win.body(14, weight: .semibold))
                .foregroundStyle(Win.text)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(WinRR(radius: 4).fill(Color.clear))
        .hoverFill()
        .contentShape(Rectangle())
        .onTapGesture { expanded.toggle() }
        .padding(.leading, 8)
    }
}

struct Pill: View {
    let title: String
    let icon: Icon
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Glyph(icon: icon, size: 14, color: Win.text, weight: 1.2)
            Text(title).font(Win.body(12)).foregroundStyle(Win.text)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            Capsule().fill(selected ? Win.selected : (hovering ? Win.subtleHover : .clear))
        )
        .overlay(Capsule().stroke(selected ? Win.strokeStrong : Color.clear, lineWidth: 1))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

struct QuickTile: View {
    let place: Place
    @ObservedObject var ex: Explorer
    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            if let url = place.url, Settings.shared.style(for: url) != nil {
                FolderGlyph(url: url, size: 32)
            } else if place.icon == .folderOutline {
                FolderIcon(size: 32)
            } else {
                PlaceIcon(place: place, size: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(place.title)
                    .font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
                Text(subtitle)
                    .font(Win.body(11)).foregroundStyle(Win.textSecondary).lineLimit(1)
                if place.pinned {
                    Glyph(icon: .pin, size: 11, color: Win.textTertiary, weight: 1.2)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 62)
        .background(WinRR(radius: 4).fill(hovering ? Win.subtleHover : .clear))
        .dropHighlight(dropTargeted)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if let u = place.url { ex.go(to: u) } }
        .onTapGesture(count: 1) { if let u = place.url { ex.go(to: u) } }
        .onDrop(of: [.fileURL], isTargeted: place.url != nil ? $dropTargeted : nil) { providers in
            guard let u = place.url else { return false }
            dropTargeted = false
            return DropHandler.handle(providers: providers, into: u, ex: ex)
        }
    }

    private var subtitle: String {
        guard let url = place.url else { return "" }
        if url.path.contains("CloudStorage") || url.lastPathComponent.hasPrefix("OneDrive") {
            return "OneDrive"
        }
        let parent = url.deletingLastPathComponent()
        if parent.path == Places.home.path { return "Stored locally" }
        return "\(Places.displayName(for: parent))\\\(url.lastPathComponent)"
    }
}

struct RecentTable: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let tab: Int

    private var rows: [FileItem] {
        switch tab {
        case 1: return ex.recentFiles.filter { $0.kind == .image || $0.kind == .pdf }
        case 2: return []
        default: return ex.recentFiles
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Name").frame(width: 320, alignment: .leading).padding(.leading, 40)
                Text("Date accessed").frame(width: 190, alignment: .leading)
                Text("Account").frame(width: 160, alignment: .leading)
                Text("Activity").frame(width: 160, alignment: .leading)
                Spacer(minLength: 0)
            }
            .font(Win.body(12))
            .foregroundStyle(Win.textSecondary)
            .frame(height: 30)
            .padding(.horizontal, 12)

            Divider().overlay(Win.divider).padding(.horizontal, 12)

            if rows.isEmpty {
                Text(tab == 2 ? "No shared files." : "No recent files.")
                    .font(Win.body(12)).foregroundStyle(Win.textTertiary)
                    .padding(.horizontal, 52).padding(.vertical, 16)
            } else {
                ForEach(rows) { item in
                    RecentRow(ex: ex, menus: menus, item: item)
                }
            }
        }
    }
}

struct RecentRow: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let item: FileItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                ItemIcon(item: item, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
                    Text(parentLabel)
                        .font(Win.body(11)).foregroundStyle(Win.textSecondary).lineLimit(1)
                }
            }
            .frame(width: 320, alignment: .leading)
            .padding(.leading, 14)

            Text(item.modifiedText)
                .font(Win.body(12)).foregroundStyle(Win.textSecondary)
                .frame(width: 190, alignment: .leading)
            Text("").frame(width: 160)
            Text("").frame(width: 160)
            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .background(WinRR(radius: 4).fill(hovering ? Win.subtleHover : .clear).padding(.horizontal, 8))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { ex.open(item) }
        .onTapGesture(count: 1) { ex.open(item) }
        .onRightClick { p in
            menus.show(id: "recent", anchor: .zero, entries: [
                MenuEntry(title: "Open", icon: .openWith) { ex.open(item) },
                MenuEntry(title: "Open file location", icon: .folderOutline) {
                    ex.go(to: item.url.deletingLastPathComponent())
                },
                .sep(),
                MenuEntry(title: "Copy as path", icon: .copy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url.path, forType: .string)
                },
                MenuEntry(title: "Properties", icon: .properties) { ex.sheet = .properties([item]) },
            ], width: 240, point: p)
        }
    }

    private var parentLabel: String {
        let parent = item.url.deletingLastPathComponent()
        let grand = parent.deletingLastPathComponent()
        if grand.path == Places.home.path { return Places.displayName(for: parent) }
        return "\(Places.displayName(for: grand))\\\(parent.lastPathComponent)"
    }
}
