import SwiftUI
import AppKit

// MARK: - Global frame reporting (used to anchor flyouts)

struct FrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, b in b })
    }
}

extension View {
    func reportFrame(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: FrameKey.self, value: [id: g.frame(in: .named("root"))])
        })
    }
}

// MARK: - Menus

struct MenuEntry: Identifiable {
    let id = UUID()
    var title: String = ""
    var icon: Icon? = nil
    var shortcut: String? = nil
    var enabled: Bool = true
    var checked: Bool = false
    var radio: Bool = false
    var separator: Bool = false
    var header: Bool = false
    var submenu: [MenuEntry]? = nil
    var action: (() -> Void)? = nil

    static func sep() -> MenuEntry { MenuEntry(separator: true) }
    static func head(_ t: String) -> MenuEntry { MenuEntry(title: t, header: true) }
}

/// Windows 11 context menus lead with a compact row of icon-only commands.
struct MenuIconRow: Identifiable {
    let id = UUID()
    var items: [(Icon, String, Bool, () -> Void)]
}

final class MenuController: ObservableObject {
    struct Open: Identifiable {
        let id: String
        var anchor: CGRect
        var entries: [MenuEntry]
        var width: CGFloat = 240
        var iconRow: MenuIconRow? = nil
        /// Position at an explicit point (context menus) instead of under a control.
        var point: CGPoint? = nil
    }

    @Published var open: Open?

    func show(id: String, anchor: CGRect, entries: [MenuEntry], width: CGFloat = 240,
              iconRow: MenuIconRow? = nil, point: CGPoint? = nil) {
        if open?.id == id && point == nil { open = nil; return }
        open = Open(id: id, anchor: anchor, entries: entries, width: width, iconRow: iconRow, point: point)
    }

    func close() { open = nil }
}

// MARK: - Toolbar button

struct WinButton<Content: View>: View {
    var id: String? = nil
    var tooltip: String? = nil
    var enabled: Bool = true
    var active: Bool = false
    var padding: CGFloat = 8
    var height: CGFloat = 32
    var corner: CGFloat = Win.M.corner
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        content()
            .padding(.horizontal, padding)
            .frame(height: height)
            .background(
                WinRR(radius: corner)
                    .fill(background)
            )
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.42)
            .onHover { hovering = $0 && enabled }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if enabled { pressing = true } }
                    .onEnded { g in
                        pressing = false
                        guard enabled else { NSSound.beep(); return }
                        // Only fire when the pointer is still inside.
                        if g.translation.width.magnitude < 40 && g.translation.height.magnitude < 40 {
                            action()
                        }
                    }
            )
            .modifier(HelpIfPresent(text: tooltip))
            .ifLet(id) { v, i in v.reportFrame(i) }
    }

    private var background: Color {
        if !enabled { return .clear }
        if pressing { return Win.subtlePress }
        if active { return Win.selected }
        if hovering { return Win.subtleHover }
        return .clear
    }
}

struct HelpIfPresent: ViewModifier {
    let text: String?
    func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
    }
}

extension View {
    @ViewBuilder
    func ifLet<T, V: View>(_ value: T?, transform: (Self, T) -> V) -> some View {
        if let value { transform(self, value) } else { self }
    }
}

// MARK: - Flyout rendering

struct FlyoutView: View {
    let open: MenuController.Open
    /// True when there isn't room to the right, so submenus open leftwards.
    var flipSubmenus: Bool = false
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let row = open.iconRow {
                HStack(spacing: 2) {
                    ForEach(Array(row.items.enumerated()), id: \.offset) { _, entry in
                        WinButton(tooltip: entry.1, enabled: entry.2, padding: 9, height: 32) {
                            onDismiss(); entry.3()
                        } content: {
                            Glyph(icon: entry.0, size: 16, color: Win.text)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                Divider().overlay(Win.divider).padding(.horizontal, 1)
            }
            ForEach(open.entries) { entry in
                MenuRow(entry: entry, parentWidth: open.width,
                        flipSubmenus: flipSubmenus, onDismiss: onDismiss)
            }
        }
        .padding(.vertical, 4)
        .frame(width: open.width)
        .background(
            WinRR(radius: 8)
                .fill(Win.flyout)
                .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
        )
        .overlay(WinRR(radius: 8).stroke(Win.stroke, lineWidth: 1))
    }
}

private let menuSubmenuCloseDelay = 0.28

struct MenuRow: View {
    let entry: MenuEntry
    var parentWidth: CGFloat = 240
    var flipSubmenus: Bool = false
    let onDismiss: () -> Void
    @State private var hovering = false
    @State private var showSub = false
    @State private var closeTask: DispatchWorkItem?

    /// Submenus sit flush against the parent. A gap would drop the hover, and
    /// an overlap would cover the parent's own items.
    private static let submenuWidth: CGFloat = 224

    private func scheduleClose() {
        closeTask?.cancel()
        let task = DispatchWorkItem { showSub = false }
        closeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + menuSubmenuCloseDelay, execute: task)
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    var body: some View {
        if entry.separator {
            Divider().overlay(Win.divider).padding(.vertical, 4).padding(.horizontal, 10)
        } else if entry.header {
            Text(entry.title)
                .font(Win.body(11, weight: .semibold))
                .foregroundStyle(Win.textTertiary)
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 3)
        } else {
            HStack(spacing: 10) {
                ZStack {
                    if entry.checked {
                        Glyph(icon: .checkmark, size: 14, color: Win.text, weight: 1.4)
                    } else if entry.radio {
                        Glyph(icon: .dot, size: 14, color: Win.text)
                    } else if let icon = entry.icon {
                        Glyph(icon: icon, size: 16, color: Win.text)
                    }
                }
                .frame(width: 18, height: 16)

                Text(entry.title)
                    .font(Win.body(12))
                    .foregroundStyle(entry.enabled ? Win.text : Win.textDisabled)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let s = entry.shortcut {
                    Text(s)
                        .font(Win.body(11))
                        .foregroundStyle(Win.textTertiary)
                }
                if entry.submenu != nil {
                    Glyph(icon: .chevronRight, size: 12, color: Win.textSecondary, weight: 1.3)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                WinRR(radius: 4)
                    .fill(hovering && entry.enabled ? Win.subtleHover : .clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                guard entry.submenu != nil else { return }
                if h { cancelClose(); showSub = true } else { scheduleClose() }
            }
            .onTapGesture {
                guard entry.enabled else { return }
                if entry.submenu == nil {
                    onDismiss()
                    entry.action?()
                } else {
                    cancelClose(); showSub = true
                }
            }
            .overlay(alignment: .topTrailing) {
                if let sub = entry.submenu, showSub {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sub) { s in
                            MenuRow(entry: s, parentWidth: MenuRow.submenuWidth,
                                    flipSubmenus: flipSubmenus, onDismiss: onDismiss)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(width: MenuRow.submenuWidth)
                    .background(
                        WinRR(radius: 8).fill(Win.flyout)
                            .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
                    )
                    .overlay(WinRR(radius: 8).stroke(Win.stroke, lineWidth: 1))
                    .offset(x: flipSubmenus ? -parentWidth + 1 : MenuRow.submenuWidth - 1, y: -5)
                    .onHover { h in if h { cancelClose() } else { scheduleClose() } }
                    .zIndex(10)
                }
            }
        }
    }
}

// MARK: - AppKit-backed text field
//
// Used for the address bar and inline rename: needs precise first-responder
// control, Esc/Enter handling, and Windows' "select the stem, not the extension".

struct WinField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var fontSize: CGFloat = 12
    var selectStem: Bool = false
    var selectAll: Bool = true
    var onCommit: (String) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onTab: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSTextField {
        let f = FocusField()
        f.delegate = context.coordinator
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = NSFont(name: Win.uiFontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        f.placeholderString = placeholder
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.cell?.wraps = false
        f.cell?.isScrollable = true
        f.stringValue = text
        f.textColor = NSColor(Win.text)
        DispatchQueue.main.async {
            f.window?.makeFirstResponder(f)
            if let editor = f.currentEditor() {
                if selectStem {
                    let stem = (text as NSString).deletingPathExtension
                    editor.selectedRange = NSRange(location: 0, length: max(stem.count, 0))
                } else if selectAll {
                    editor.selectAll(nil)
                }
            }
        }
        return f
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.textColor = NSColor(Win.text)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: WinField
        init(_ p: WinField) { parent = p }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            parent.text = f.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommit(control.stringValue); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel(); return true
            case #selector(NSResponder.insertTab(_:)):
                if let t = parent.onTab { t(); return true }
                return false
            default:
                return false
            }
        }
    }

    /// Commits on focus loss, matching Explorer's inline rename.
    final class FocusField: NSTextField {
        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
        }
    }
}

// MARK: - Small helpers

struct HoverFill: ViewModifier {
    @State private var hovering = false
    var corner: CGFloat = 4
    var enabled: Bool = true
    func body(content: Content) -> some View {
        content
            .background(WinRR(radius: corner).fill(hovering && enabled ? Win.subtleHover : .clear))
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverFill(corner: CGFloat = 4, enabled: Bool = true) -> some View {
        modifier(HoverFill(corner: corner, enabled: enabled))
    }
}

/// Windows' item check boxes (View > Show > Item check boxes).
struct WinCheckbox: View {
    let checked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        WinRR(radius: 3)
            .fill(checked ? Win.accent : (hovering ? Win.fieldHover : Win.field))
            .overlay(WinRR(radius: 3).stroke(checked ? Win.accent : Win.strokeStrong, lineWidth: 1))
            .overlay {
                if checked { Glyph(icon: .checkmark, size: 11, color: Win.textOnAccent, weight: 1.6) }
            }
            .frame(width: 15, height: 15)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

/// Makes a region drag the window, the way the Explorer tab strip does.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.zoom(nil) }
            else { window?.performDrag(with: event) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) === self ? self : super.hitTest(point)
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
