import SwiftUI
import AppKit

// MARK: - Key chords

struct KeyChord: Codable, Hashable {
    /// Physical key code, used for keys whose character changes with Shift.
    var code: UInt16? = nil
    /// Character (lowercased), used for letters.
    var char: String? = nil
    var ctrl = false
    var shift = false
    var alt = false

    init(code: UInt16? = nil, char: String? = nil, ctrl: Bool = false, shift: Bool = false, alt: Bool = false) {
        self.code = code; self.char = char; self.ctrl = ctrl; self.shift = shift; self.alt = alt
    }

    func matches(_ event: NSEvent) -> Bool {
        let f = event.modifierFlags
        guard (f.contains(.command) || f.contains(.control)) == ctrl,
              f.contains(.shift) == shift,
              f.contains(.option) == alt else { return false }
        if let code { return event.keyCode == code }
        if let char { return (event.charactersIgnoringModifiers ?? "").lowercased() == char }
        return false
    }

    static func from(_ event: NSEvent) -> KeyChord {
        let f = event.modifierFlags
        let ctrl = f.contains(.command) || f.contains(.control)
        let shift = f.contains(.shift)
        let alt = f.contains(.option)
        let raw = (event.charactersIgnoringModifiers ?? "").lowercased()
        let isLetter = raw.count == 1 && raw.first!.isLetter
        return isLetter
            ? KeyChord(char: raw, ctrl: ctrl, shift: shift, alt: alt)
            : KeyChord(code: event.keyCode, ctrl: ctrl, shift: shift, alt: alt)
    }

    var display: String {
        var parts: [String] = []
        if ctrl { parts.append("Ctrl") }
        if alt { parts.append("Alt") }
        if shift { parts.append("Shift") }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    var keyName: String {
        if let char { return char.uppercased() }
        if let code { return KeyChord.names[code] ?? "Key \(code)" }
        return "—"
    }

    static let names: [UInt16: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        36: "Enter", 48: "Tab", 49: "Space", 51: "Backspace", 53: "Esc", 76: "Enter",
        115: "Home", 116: "Page Up", 117: "Delete", 119: "End", 121: "Page Down",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    ]

    static let digitCodes: [Int: UInt16] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25, 0: 29]
}

// MARK: - Commands

enum Command: String, Codable, CaseIterable {
    case copy, cut, paste, pasteShortcut, copyPath
    case undo, redo
    case selectAll, selectNone, invertSelection
    case rename, delete, deletePermanent, newFolder, newTextDocument, compress, createShortcut
    case newTab, closeTab, nextTab, prevTab, newWindow
    case refresh, back, forward, up, focusAddress, focusSearch
    case goHome, goDesktop, goDownloads, goDocuments, goPictures, goMusic, goVideos, goThisPC
    case showDesktop
    case properties, openTerminal, showInFinder
    case toggleHidden, toggleExtensions, toggleNavPane, toggleDetailsPane, togglePreviewPane
    case fullScreen, openSettings
    case viewExtraLarge, viewLarge, viewMedium, viewSmall, viewList, viewDetails, viewTiles, viewContent

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .cut: return "Cut"
        case .paste: return "Paste"
        case .pasteShortcut: return "Paste shortcut"
        case .copyPath: return "Copy as path"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .selectAll: return "Select all"
        case .selectNone: return "Select none"
        case .invertSelection: return "Invert selection"
        case .rename: return "Rename"
        case .delete: return "Delete (Recycle Bin)"
        case .deletePermanent: return "Delete permanently"
        case .newFolder: return "New folder"
        case .newTextDocument: return "New text document"
        case .compress: return "Compress to ZIP"
        case .createShortcut: return "Create shortcut"
        case .newTab: return "New tab"
        case .closeTab: return "Close tab"
        case .nextTab: return "Next tab"
        case .prevTab: return "Previous tab"
        case .newWindow: return "New window"
        case .goHome: return "Go to Home"
        case .goDesktop: return "Go to Desktop folder"
        case .showDesktop: return "Show desktop (hide all windows)"
        case .goDownloads: return "Go to Downloads"
        case .goDocuments: return "Go to Documents"
        case .goPictures: return "Go to Pictures"
        case .goMusic: return "Go to Music"
        case .goVideos: return "Go to Videos"
        case .goThisPC: return "Go to This PC"
        case .refresh: return "Refresh"
        case .back: return "Back"
        case .forward: return "Forward"
        case .up: return "Up one level"
        case .focusAddress: return "Focus address bar"
        case .focusSearch: return "Focus search"
        case .properties: return "Properties"
        case .openTerminal: return "Open in Terminal"
        case .showInFinder: return "Show in Finder"
        case .toggleHidden: return "Show hidden items"
        case .toggleExtensions: return "Show file name extensions"
        case .toggleNavPane: return "Navigation pane"
        case .toggleDetailsPane: return "Details pane"
        case .togglePreviewPane: return "Preview pane"
        case .fullScreen: return "Full screen"
        case .openSettings: return "Settings"
        case .viewExtraLarge: return "Extra large icons"
        case .viewLarge: return "Large icons"
        case .viewMedium: return "Medium icons"
        case .viewSmall: return "Small icons"
        case .viewList: return "List"
        case .viewDetails: return "Details"
        case .viewTiles: return "Tiles"
        case .viewContent: return "Content"
        }
    }

    var group: String {
        switch self {
        case .copy, .cut, .paste, .pasteShortcut, .copyPath, .undo, .redo:
            return "Clipboard"
        case .selectAll, .selectNone, .invertSelection:
            return "Selection"
        case .rename, .delete, .deletePermanent, .newFolder, .newTextDocument, .compress, .createShortcut:
            return "Files"
        case .newTab, .closeTab, .nextTab, .prevTab, .newWindow, .fullScreen, .openSettings:
            return "Tabs & windows"
        case .refresh, .back, .forward, .up, .focusAddress, .focusSearch, .properties,
             .openTerminal, .showInFinder,
             .goHome, .goDesktop, .goDownloads, .goDocuments, .goPictures,
             .goMusic, .goVideos, .goThisPC:
            return "Navigation"
        case .showDesktop:
            return "Tabs & windows"
        default:
            return "View"
        }
    }

    var defaultChords: [KeyChord] {
        func d(_ n: Int) -> UInt16 { KeyChord.digitCodes[n]! }
        switch self {
        case .copy:           return [KeyChord(char: "c", ctrl: true)]
        case .cut:            return [KeyChord(char: "x", ctrl: true)]
        case .paste:          return [KeyChord(char: "v", ctrl: true)]
        case .pasteShortcut:  return [KeyChord(char: "v", ctrl: true, shift: true)]
        case .copyPath:       return [KeyChord(char: "c", ctrl: true, shift: true)]
        case .undo:           return [KeyChord(char: "z", ctrl: true)]
        case .redo:           return [KeyChord(char: "y", ctrl: true), KeyChord(char: "z", ctrl: true, shift: true)]
        case .selectAll:      return [KeyChord(char: "a", ctrl: true)]
        case .selectNone:     return [KeyChord(char: "a", ctrl: true, shift: true)]
        case .invertSelection: return []
        case .rename:         return [KeyChord(code: 120)]
        case .delete:         return [KeyChord(code: 117), KeyChord(code: 51, ctrl: true)]
        case .deletePermanent: return [KeyChord(code: 117, shift: true), KeyChord(code: 51, ctrl: true, shift: true)]
        case .newFolder:      return [KeyChord(char: "n", ctrl: true, shift: true)]
        case .newTextDocument: return []
        case .compress:       return []
        case .createShortcut: return []
        case .newTab:         return [KeyChord(char: "t", ctrl: true)]
        case .closeTab:       return [KeyChord(char: "w", ctrl: true)]
        case .nextTab:        return [KeyChord(code: 48, ctrl: true)]
        case .prevTab:        return [KeyChord(code: 48, ctrl: true, shift: true)]
        case .newWindow:      return [KeyChord(char: "n", ctrl: true)]
        case .goHome:         return [KeyChord(char: "h", ctrl: true, shift: true)]
        case .goDesktop:      return [KeyChord(char: "d", ctrl: true, shift: true)]
        case .showDesktop:    return [KeyChord(char: "d", ctrl: true)]
        case .goDownloads:    return [KeyChord(char: "j", ctrl: true, shift: true)]
        case .goDocuments:    return []
        case .goPictures:     return []
        case .goMusic:        return []
        case .goVideos:       return []
        case .goThisPC:       return []
        case .refresh:        return [KeyChord(code: 96), KeyChord(char: "r", ctrl: true)]
        case .back:           return [KeyChord(code: 123, alt: true), KeyChord(code: 51)]
        case .forward:        return [KeyChord(code: 124, alt: true)]
        case .up:             return [KeyChord(code: 126, alt: true)]
        case .focusAddress:   return [KeyChord(char: "l", ctrl: true), KeyChord(char: "d", alt: true), KeyChord(code: 118)]
        case .focusSearch:    return [KeyChord(char: "f", ctrl: true), KeyChord(char: "e", ctrl: true), KeyChord(code: 99)]
        case .properties:     return [KeyChord(code: 36, alt: true)]
        case .openTerminal:   return []
        case .showInFinder:   return []
        case .toggleHidden:   return [KeyChord(char: "h", ctrl: true)]
        case .toggleExtensions: return []
        case .toggleNavPane:  return []
        case .toggleDetailsPane: return [KeyChord(char: "p", shift: true, alt: true)]
        case .togglePreviewPane: return [KeyChord(char: "p", alt: true)]
        case .fullScreen:     return [KeyChord(code: 103)]
        case .openSettings:   return [KeyChord(char: ",", ctrl: true), KeyChord(code: 43, ctrl: true)]
        case .viewExtraLarge: return [KeyChord(code: d(1), ctrl: true, shift: true)]
        case .viewLarge:      return [KeyChord(code: d(2), ctrl: true, shift: true)]
        case .viewMedium:     return [KeyChord(code: d(3), ctrl: true, shift: true)]
        case .viewSmall:      return [KeyChord(code: d(4), ctrl: true, shift: true)]
        case .viewList:       return [KeyChord(code: d(5), ctrl: true, shift: true)]
        case .viewDetails:    return [KeyChord(code: d(6), ctrl: true, shift: true)]
        case .viewTiles:      return [KeyChord(code: d(7), ctrl: true, shift: true)]
        case .viewContent:    return [KeyChord(code: d(8), ctrl: true, shift: true)]
        }
    }

    static let groups = ["Clipboard", "Selection", "Files", "Navigation", "View", "Tabs & windows"]
}

// MARK: - Folder appearance overrides

struct FolderStyle: Codable, Hashable {
    /// Icon.rawValue, or "folder" for the standard Windows folder.
    var icon: String = "folder"
    /// sRGB hex, e.g. "FFCE44".
    var tint: String = ""

    var iconCase: Icon? { icon == "folder" ? nil : Icon(rawValue: icon) }
    var color: Color? { tint.isEmpty ? nil : Color(hex: tint) }
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Theme

enum ThemeMode: String, Codable, CaseIterable {
    case system = "Use system setting"
    case light = "Light"
    case dark = "Dark"

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct AccentOption: Identifiable, Hashable {
    let id: String
    let name: String
    let dark: String
    let light: String
}

// MARK: - Settings store

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = Store.defaults

    @Published var theme: ThemeMode { didSet { save(); applyTheme() } }
    @Published var accentID: String { didSet { save() } }
    @Published var bindings: [String: [KeyChord]] { didSet { save() } }
    @Published var folderStyles: [String: FolderStyle] { didSet { save() } }
    @Published var pinned: [String] { didSet { save() } }
    @Published var hiddenPlaces: Set<String> { didSet { save() } }

    static let accents: [AccentOption] = [
        AccentOption(id: "blue",    name: "Windows blue", dark: "60CDFF", light: "0067C0"),
        AccentOption(id: "teal",    name: "Teal",         dark: "5FD9CF", light: "00786B"),
        AccentOption(id: "green",   name: "Green",        dark: "6CCB5F", light: "107C10"),
        AccentOption(id: "orange",  name: "Orange",       dark: "FFB556", light: "C2540A"),
        AccentOption(id: "red",     name: "Red",          dark: "FF8A80", light: "C42B1C"),
        AccentOption(id: "pink",    name: "Pink",         dark: "FF9DC4", light: "C1358A"),
        AccentOption(id: "purple",  name: "Purple",       dark: "C9A2FF", light: "6B4BA8"),
        AccentOption(id: "graphite", name: "Graphite",    dark: "C8C8C8", light: "4A4A4A"),
    ]

    var accent: AccentOption {
        Settings.accents.first { $0.id == accentID } ?? Settings.accents[0]
    }

    private init() {
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        accentID = d.string(forKey: "accentID") ?? "blue"
        bindings = Settings.decode([String: [KeyChord]].self, d.data(forKey: "bindings")) ?? [:]
        folderStyles = Settings.decode([String: FolderStyle].self, d.data(forKey: "folderStyles")) ?? [:]
        pinned = d.stringArray(forKey: "pinned") ?? []
        hiddenPlaces = Set(d.stringArray(forKey: "hiddenPlaces") ?? [])
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save() {
        d.set(theme.rawValue, forKey: "theme")
        d.set(accentID, forKey: "accentID")
        d.set(try? JSONEncoder().encode(bindings), forKey: "bindings")
        d.set(try? JSONEncoder().encode(folderStyles), forKey: "folderStyles")
        d.set(pinned, forKey: "pinned")
        d.set(Array(hiddenPlaces), forKey: "hiddenPlaces")
    }

    func applyTheme() {
        NSApp.appearance = theme.appearance
    }

    // MARK: Shortcuts

    func chords(for command: Command) -> [KeyChord] {
        bindings[command.rawValue] ?? command.defaultChords
    }

    func display(for command: Command) -> String? {
        chords(for: command).first?.display
    }

    func command(for event: NSEvent) -> Command? {
        for c in Command.allCases where chords(for: c).contains(where: { $0.matches(event) }) {
            return c
        }
        return nil
    }

    /// Any other command already using this chord.
    func conflict(for chord: KeyChord, excluding command: Command) -> Command? {
        Command.allCases.first { $0 != command && chords(for: $0).contains(chord) }
    }

    func setChord(_ chord: KeyChord, for command: Command) {
        if let other = conflict(for: chord, excluding: command) {
            var otherChords = chords(for: other)
            otherChords.removeAll { $0 == chord }
            bindings[other.rawValue] = otherChords
        }
        bindings[command.rawValue] = [chord]
    }

    func resetChords(for command: Command) {
        bindings.removeValue(forKey: command.rawValue)
    }

    func resetAllChords() { bindings = [:] }

    var customisedCommands: [Command] {
        Command.allCases.filter { bindings[$0.rawValue] != nil }
    }

    // MARK: Folder styles

    func style(for url: URL) -> FolderStyle? { folderStyles[url.path] }

    func setStyle(_ style: FolderStyle?, for url: URL) {
        if let style { folderStyles[url.path] = style }
        else { folderStyles.removeValue(forKey: url.path) }
    }

    // MARK: Pinning

    func isPinned(_ url: URL) -> Bool {
        pinned.contains(url.path) || Places.defaultPinnedPaths.contains(url.path)
    }

    func pin(_ url: URL) {
        guard !pinned.contains(url.path) else { return }
        hiddenPlaces.remove(url.path)
        pinned.append(url.path)
    }

    func unpin(_ url: URL) {
        pinned.removeAll { $0 == url.path }
        if Places.defaultPinnedPaths.contains(url.path) { hiddenPlaces.insert(url.path) }
    }

    func togglePin(_ url: URL) {
        if isPinned(url) && !hiddenPlaces.contains(url.path) { unpin(url) } else { pin(url) }
    }
}
