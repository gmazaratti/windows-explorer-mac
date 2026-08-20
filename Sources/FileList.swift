import SwiftUI
import AppKit

// MARK: - Right-click support (Windows-style flyouts instead of AppKit menus)

/// Routes right-clicks to the right target.
///
/// Rather than fighting AppKit hit-testing (which would also swallow the left
/// clicks SwiftUI needs), every context-menu target registers an invisible
/// marker view. A window-level monitor then picks the smallest registered
/// target under the pointer, falling back to the file-area background.
final class RightClickRouter {
    static let shared = RightClickRouter()

    private let targets = NSHashTable<RightClickCatcher.View>.weakObjects()
    /// Frame of the file area in root (window, top-left origin) coordinates.
    var contentFrame: CGRect = .zero

    func register(_ view: RightClickCatcher.View) { targets.add(view) }
    func unregister(_ view: RightClickCatcher.View) { targets.remove(view) }

    /// Converts a window-coordinate event location into root coordinates.
    static func rootPoint(_ event: NSEvent) -> CGPoint {
        guard let content = event.window?.contentView else { return event.locationInWindow }
        let p = event.locationInWindow
        return CGPoint(x: p.x, y: content.bounds.height - p.y)
    }

    /// The most specific target under a point, if any.
    func target(at point: CGPoint, in window: NSWindow?) -> RightClickCatcher.View? {
        var best: RightClickCatcher.View?
        var bestArea = CGFloat.greatestFiniteMagnitude
        for view in targets.allObjects {
            guard view.window === window, !view.isHiddenOrHasHiddenAncestor,
                  let frame = view.rootFrame, frame.contains(point) else { continue }
            let area = frame.width * frame.height
            if area < bestArea { bestArea = area; best = view }
        }
        return best
    }

    /// Handles a right-click. Returns true when it was consumed.
    @discardableResult
    func route(_ event: NSEvent) -> Bool {
        let point = RightClickRouter.rootPoint(event)
        if let view = target(at: point, in: event.window) {
            view.onClick?(point)
            return true
        }
        if contentFrame.contains(point) {
            NotificationCenter.default.post(name: .backgroundContextMenu, object: point)
            return true
        }
        return false
    }
}

struct RightClickCatcher: NSViewRepresentable {
    let onClick: (CGPoint) -> Void

    final class View: NSView {
        var onClick: ((CGPoint) -> Void)?
        override var isFlipped: Bool { true }

        /// Invisible to hit-testing: the router dispatches to it explicitly.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { RightClickRouter.shared.unregister(self) }
            else { RightClickRouter.shared.register(self) }
        }

        /// This view's bounds in root (window, top-left origin) coordinates.
        var rootFrame: CGRect? {
            guard let window, let content = window.contentView else { return nil }
            let inWindow = convert(bounds, to: nil)
            return CGRect(x: inWindow.minX,
                          y: content.bounds.height - inWindow.maxY,
                          width: inWindow.width, height: inWindow.height)
        }
    }

    func makeNSView(context: Context) -> View {
        let v = View(); v.onClick = onClick; return v
    }
    func updateNSView(_ nsView: View, context: Context) { nsView.onClick = onClick }
}

extension View {
    /// Marks this view as a context-menu target. The marker sits behind the
    /// content and is invisible to SwiftUI hit-testing, so taps, drags and
    /// drops keep working exactly as before.
    func onRightClick(perform: @escaping (CGPoint) -> Void) -> some View {
        background(RightClickCatcher(onClick: perform).allowsHitTesting(false))
    }
}

// MARK: - Content area

struct FileArea: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        ZStack {
            Win.content
            if case .home = ex.tab.location, !ex.tab.searching {
                HomeView(ex: ex, menus: menus)
            } else if ex.tab.items.isEmpty {
                EmptyFolderView(ex: ex, menus: menus)
            } else {
                switch prefs.viewMode {
                case .details:
                    DetailsView(ex: ex, menus: menus)
                case .list:
                    ListFlowView(ex: ex, menus: menus)
                case .tiles, .content:
                    TilesView(ex: ex, menus: menus, mode: prefs.viewMode)
                default:
                    IconGridView(ex: ex, menus: menus)
                }
            }
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { RightClickRouter.shared.contentFrame = g.frame(in: .named("root")) }
                .onChange(of: g.frame(in: .named("root"))) { _, f in
                    RightClickRouter.shared.contentFrame = f
                }
        })
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let dir = ex.currentDirectory else { return false }
            return DropHandler.handle(providers: providers, into: dir, ex: ex)
        }
        .onReceive(NotificationCenter.default.publisher(for: .backgroundContextMenu)) { note in
            guard let point = note.object as? CGPoint else { return }
            guard AppState.shared.explorer(for: NSApp.keyWindow) === ex else { return }
            ex.selectNone()
            menus.show(id: "bg", anchor: .zero, entries: ContextMenus.background(ex),
                       width: 250, iconRow: nil, point: point)
        }
    }
}

extension Notification.Name {
    static let backgroundContextMenu = Notification.Name("winexp.bgContextMenu")
}

struct EmptyFolderView: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    var body: some View {
        VStack(spacing: 6) {
            Text(ex.tab.searching ? "No items match your search." : "This folder is empty.")
                .font(Win.body(12))
                .foregroundStyle(Win.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Selection & activation helpers shared by every view mode

struct ItemInteraction: ViewModifier {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let item: FileItem

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { ex.open(item) }
            .onTapGesture(count: 1) {
                let f = NSEvent.modifierFlags
                ex.select(item,
                          extend: f.contains(.shift),
                          toggle: f.contains(.control) || f.contains(.command))
            }
            .onRightClick { p in
                if !ex.tab.selection.contains(item.id) {
                    ex.select(item, extend: false, toggle: false)
                }
                menus.show(id: "item", anchor: .zero,
                           entries: ContextMenus.item(ex),
                           width: 260,
                           iconRow: ContextMenus.iconRow(ex),
                           point: p)
            }
            .onDrag {
                if !ex.tab.selection.contains(item.id) {
                    ex.select(item, extend: false, toggle: false)
                }
                return NSItemProvider(object: item.url as NSURL)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard item.isDirectory && !item.isPackage else { return false }
                return DropHandler.handle(providers: providers, into: item.url, ex: ex)
            }
    }
}

extension View {
    func itemInteraction(_ ex: Explorer, _ menus: MenuController, _ item: FileItem) -> some View {
        modifier(ItemInteraction(ex: ex, menus: menus, item: item))
    }
}

// MARK: - Details view

struct DetailsView: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    @ObservedObject var prefs = Prefs.shared

    @State private var nameWidth: CGFloat = 300
    @State private var dateWidth: CGFloat = 150
    @State private var typeWidth: CGFloat = 140
    @State private var sizeWidth: CGFloat = 90

    private var rowHeight: CGFloat { prefs.compactMode ? 24 : 32 }

    var body: some View {
        GeometryReader { geo in
            // The name column absorbs whatever space the others leave, so the
            // list can never push the window wider than it is.
            let others = dateWidth + typeWidth + sizeWidth + 26
            let name = max(120, min(nameWidth, geo.size.width - others))
            content(nameColumn: name)
        }
    }

    private func content(nameColumn: CGFloat) -> some View {
        VStack(spacing: 0) {
            header(nameColumn: nameColumn)
            Divider().overlay(Win.divider)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(ex.tab.items) { item in
                            DetailsRow(ex: ex, menus: menus, item: item,
                                       height: rowHeight,
                                       nameWidth: nameColumn, dateWidth: dateWidth,
                                       typeWidth: typeWidth, sizeWidth: sizeWidth)
                                .id(item.id)
                        }
                        Color.clear
                            .frame(height: 40)
                            .contentShape(Rectangle())
                            .onTapGesture { ex.selectNone() }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
                .onChange(of: ex.tab.scrollTarget) { _, target in
                    if let t = target { withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(t, anchor: .center) } }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let dir = ex.currentDirectory else { return false }
            return DropHandler.handle(providers: providers, into: dir, ex: ex)
        }
    }

    private func header(nameColumn: CGFloat) -> some View {
        HStack(spacing: 0) {
            ColumnHeader(title: "Name", key: .name, width: $nameWidth,
                         effective: nameColumn, ex: ex, leading: 34)
            ColumnHeader(title: "Date modified", key: .modified, width: $dateWidth, ex: ex)
            ColumnHeader(title: "Type", key: .type, width: $typeWidth, ex: ex)
            ColumnHeader(title: "Size", key: .size, width: $sizeWidth, ex: ex, trailing: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 28)
    }
}

struct ColumnHeader: View {
    let title: String
    let key: SortKey
    @Binding var width: CGFloat
    /// The width actually used for layout, which may be clamped to fit.
    var effective: CGFloat? = nil
    @ObservedObject var ex: Explorer
    var leading: CGFloat = 10
    var trailing: Bool = false
    @State private var hovering = false
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    if trailing { Spacer(minLength: 0) }
                    Text(title)
                        .font(Win.body(12))
                        .foregroundStyle(Win.textSecondary)
                        .lineLimit(1)
                    if !trailing { Spacer(minLength: 0) }
                }
                .padding(.leading, trailing ? 6 : leading)
                .padding(.trailing, trailing ? 10 : 6)

                if prefs.sortKey == key {
                    Glyph(icon: prefs.sortAscending ? .sortAsc : .sortDesc,
                          size: 10, color: Win.accent)
                        .offset(y: -3)
                }
            }
            .frame(width: effective ?? width, height: 26)
            .background(WinRR(radius: 4).fill(hovering ? Win.subtleHover : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                if prefs.sortKey == key { prefs.sortAscending.toggle() }
                else { prefs.sortKey = key; prefs.sortAscending = true }
                ex.resort()
            }

            Rectangle()
                .fill(Color.clear)
                .frame(width: 6, height: 20)
                .overlay(Rectangle().fill(Win.divider).frame(width: 1))
                .contentShape(Rectangle())
                .onHover { NSCursor.resizeLeftRight.set(); if !$0 { NSCursor.arrow.set() } }
                .gesture(DragGesture()
                    .onChanged { g in width = max(60, width + g.translation.width / 12) })
        }
    }
}

struct DetailsRow: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let item: FileItem
    let height: CGFloat
    let nameWidth: CGFloat
    let dateWidth: CGFloat
    let typeWidth: CGFloat
    let sizeWidth: CGFloat
    @State private var hovering = false
    @ObservedObject private var prefs = Prefs.shared

    private var selected: Bool { ex.tab.selection.contains(item.id) }
    private var cutOut: Bool { Clipboard.cutPaths.contains(item.url.path) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                if prefs.itemCheckBoxes {
                    WinCheckbox(checked: selected) {
                        ex.select(item, extend: false, toggle: true)
                    }
                }
                ItemIcon(item: item, size: 16)
                    .opacity(cutOut ? 0.45 : 1)
                if ex.tab.editing == item.id {
                    RenameField(ex: ex, item: item)
                        .frame(height: 20)
                } else {
                    Text(item.displayName)
                        .font(Win.body(12))
                        .foregroundStyle(item.isHidden ? Win.textTertiary : Win.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(cutOut ? 0.45 : 1)
                }
            }
            .padding(.leading, 10)
            .frame(width: nameWidth, alignment: .leading)

            Text(item.modifiedText)
                .font(Win.body(12)).foregroundStyle(Win.textSecondary)
                .lineLimit(1)
                .padding(.leading, 6)
                .frame(width: dateWidth, alignment: .leading)

            Text(item.typeName)
                .font(Win.body(12)).foregroundStyle(Win.textSecondary)
                .lineLimit(1)
                .padding(.leading, 6)
                .frame(width: typeWidth, alignment: .leading)

            Text(item.sizeText)
                .font(Win.body(12)).foregroundStyle(Win.textSecondary)
                .lineLimit(1)
                .padding(.trailing, 10)
                .frame(width: sizeWidth, alignment: .trailing)

            Spacer(minLength: 0)
        }
        .frame(height: height)
        .background(
            WinRR(radius: 4).fill(
                selected ? (hovering ? Win.selectedHover : Win.selected)
                         : (hovering ? Win.subtleHover : .clear))
        )
        .onHover { hovering = $0 }
        .itemInteraction(ex, menus, item)
    }
}

struct RenameField: View {
    @ObservedObject var ex: Explorer
    let item: FileItem
    @State private var text: String = ""

    var body: some View {
        WinField(text: $text, fontSize: 12,
                 selectStem: !item.isDirectory,
                 selectAll: item.isDirectory,
                 onCommit: { s in ex.commitRename(item, to: s) },
                 onCancel: { ex.tab.editing = nil })
            .padding(.horizontal, 4)
            .background(WinRR(radius: 3).fill(Win.fieldFocus))
            .overlay(WinRR(radius: 3).stroke(Win.accent, lineWidth: 1))
            .onAppear { text = Prefs.shared.showExtensions ? item.name : item.displayName }
    }
}

// MARK: - Icon grid

struct IconGridView: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let cell = prefs.viewMode.cellSize
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cell.width, maximum: cell.width * 1.4),
                                             spacing: 4, alignment: .top)],
                          alignment: .leading, spacing: 4) {
                    ForEach(ex.tab.items) { item in
                        IconCell(ex: ex, menus: menus, item: item,
                                 size: prefs.viewMode.iconSize, cell: cell)
                            .id(item.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: ex.tab.scrollTarget) { _, t in
                if let t { proxy.scrollTo(t, anchor: .center) }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let dir = ex.currentDirectory else { return false }
            return DropHandler.handle(providers: providers, into: dir, ex: ex)
        }
    }
}

struct IconCell: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let item: FileItem
    let size: CGFloat
    let cell: CGSize
    @State private var hovering = false
    @ObservedObject private var prefs = Prefs.shared

    private var selected: Bool { ex.tab.selection.contains(item.id) }
    private var cutOut: Bool { Clipboard.cutPaths.contains(item.url.path) }

    var body: some View {
        VStack(spacing: 6) {
            ItemIcon(item: item, size: size)
                .opacity(cutOut ? 0.45 : 1)
            if ex.tab.editing == item.id {
                RenameField(ex: ex, item: item).frame(height: 20).padding(.horizontal, 4)
            } else {
                Text(item.displayName)
                    .font(Win.body(12))
                    .foregroundStyle(Win.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
                    .opacity(cutOut ? 0.45 : 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .frame(width: cell.width, height: cell.height)
        .background(
            WinRR(radius: 4).fill(
                selected ? (hovering ? Win.selectedHover : Win.selected)
                         : (hovering ? Win.subtleHover : .clear))
        )
        .overlay(alignment: .topLeading) {
            if prefs.itemCheckBoxes && (hovering || selected) {
                WinCheckbox(checked: selected) {
                    ex.select(item, extend: false, toggle: true)
                }
                .padding(6)
            }
        }
        .onHover { hovering = $0 }
        .itemInteraction(ex, menus, item)
    }
}

// MARK: - List view (columns flow top-to-bottom, as in Explorer)

struct ListFlowView: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController

    var body: some View {
        GeometryReader { geo in
            let rowH: CGFloat = 22
            let perColumn = max(1, Int((geo.size.height - 24) / rowH))
            let columns = stride(from: 0, to: ex.tab.items.count, by: perColumn).map {
                Array(ex.tab.items[$0..<min($0 + perColumn, ex.tab.items.count)])
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(col) { item in
                                SmallRow(ex: ex, menus: menus, item: item, width: 220, height: rowH)
                            }
                        }
                        .frame(width: 220)
                    }
                }
                .padding(12)
            }
        }
    }
}

struct SmallRow: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let item: FileItem
    let width: CGFloat
    let height: CGFloat
    @State private var hovering = false
    private var selected: Bool { ex.tab.selection.contains(item.id) }

    var body: some View {
        HStack(spacing: 8) {
            ItemIcon(item: item, size: 16)
            if ex.tab.editing == item.id {
                RenameField(ex: ex, item: item).frame(height: 18)
            } else {
                Text(item.displayName)
                    .font(Win.body(12)).foregroundStyle(Win.text)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: height)
        .background(WinRR(radius: 4).fill(selected ? Win.selected : (hovering ? Win.subtleHover : .clear)))
        .onHover { hovering = $0 }
        .itemInteraction(ex, menus, item)
    }
}

// MARK: - Tiles / Content

struct TilesView: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let mode: ViewMode

    var body: some View {
        ScrollView(.vertical) {
            if mode == .tiles {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 6)],
                          alignment: .leading, spacing: 6) {
                    ForEach(ex.tab.items) { item in
                        TileCell(ex: ex, menus: menus, item: item)
                    }
                }
                .padding(12)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(ex.tab.items) { item in
                        ContentRow(ex: ex, menus: menus, item: item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }
}

struct TileCell: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let item: FileItem
    @State private var hovering = false
    private var selected: Bool { ex.tab.selection.contains(item.id) }

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(item: item, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                if ex.tab.editing == item.id {
                    RenameField(ex: ex, item: item).frame(height: 20)
                } else {
                    Text(item.displayName).font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
                }
                Text(item.typeName).font(Win.body(11)).foregroundStyle(Win.textSecondary).lineLimit(1)
                if !item.sizeText.isEmpty {
                    Text(item.sizeText).font(Win.body(11)).foregroundStyle(Win.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(height: 72)
        .background(WinRR(radius: 4).fill(selected ? Win.selected : (hovering ? Win.subtleHover : .clear)))
        .onHover { hovering = $0 }
        .itemInteraction(ex, menus, item)
    }
}

struct ContentRow: View {
    @ObservedObject var ex: Explorer
    @ObservedObject var menus: MenuController
    let item: FileItem
    @State private var hovering = false
    private var selected: Bool { ex.tab.selection.contains(item.id) }

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(item: item, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                if ex.tab.editing == item.id {
                    RenameField(ex: ex, item: item).frame(height: 20)
                } else {
                    Text(item.displayName).font(Win.body(12)).foregroundStyle(Win.text).lineLimit(1)
                }
                Text(item.modifiedText).font(Win.body(11)).foregroundStyle(Win.textSecondary)
            }
            Spacer(minLength: 0)
            Text(item.sizeText).font(Win.body(11)).foregroundStyle(Win.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(WinRR(radius: 4).fill(selected ? Win.selected : (hovering ? Win.subtleHover : .clear)))
        .onHover { hovering = $0 }
        .itemInteraction(ex, menus, item)
    }
}
