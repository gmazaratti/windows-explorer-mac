import SwiftUI

// MARK: - Compact path mini-language
//
// Icons are authored on Fluent's 16x16 design grid. Supported commands:
//   M x y      move to            L x y   line to
//   H x        horizontal line    V y     vertical line
//   C ...      cubic bezier       Q ...   quadratic bezier
//   Z          close subpath
//   O cx cy r          circle
//   R x y w h r        rounded rect
//   K cx cy r a0 a1    arc in degrees (0 = east, increasing = clockwise on screen)

enum PathSpec {

    /// Splits a spec into command letters and numbers, tolerating either
    /// "M 4 2" or the compact "M4 2" form.
    private static func tokenize(_ spec: String) -> [Substring] {
        var out: [Substring] = []
        var i = spec.startIndex
        while i < spec.endIndex {
            let c = spec[i]
            if c == " " || c == "," || c == "\n" {
                i = spec.index(after: i); continue
            }
            if c.isLetter {
                out.append(spec[i..<spec.index(after: i)])
                i = spec.index(after: i); continue
            }
            var j = i
            while j < spec.endIndex, !spec[j].isLetter, spec[j] != " ", spec[j] != ",", spec[j] != "\n" {
                j = spec.index(after: j)
            }
            out.append(spec[i..<j])
            i = j
        }
        return out
    }

    static func parse(_ spec: String, scale s: CGFloat) -> Path {
        var path = Path()
        var tokens = tokenize(spec)[...]
        var cmd: Character = "M"
        var cursor = CGPoint.zero
        var subpathStart = CGPoint.zero

        func num() -> CGFloat {
            guard let t = tokens.first else { return 0 }
            tokens = tokens.dropFirst()
            return CGFloat(Double(t) ?? 0)
        }
        func pt() -> CGPoint {
            let x = num(), y = num()
            return CGPoint(x: x * s, y: y * s)
        }

        while let token = tokens.first {
            if let c = token.first, c.isLetter {
                cmd = c
                tokens = tokens.dropFirst()
                if cmd == "Z" || cmd == "z" {
                    path.closeSubpath()
                    cursor = subpathStart
                    continue
                }
            }
            switch cmd {
            case "M":
                cursor = pt(); subpathStart = cursor; path.move(to: cursor)
            case "L":
                cursor = pt(); path.addLine(to: cursor)
            case "H":
                cursor = CGPoint(x: num() * s, y: cursor.y); path.addLine(to: cursor)
            case "V":
                cursor = CGPoint(x: cursor.x, y: num() * s); path.addLine(to: cursor)
            case "C":
                let c1 = pt(), c2 = pt(), e = pt()
                path.addCurve(to: e, control1: c1, control2: c2); cursor = e
            case "Q":
                let c1 = pt(), e = pt()
                path.addQuadCurve(to: e, control: c1); cursor = e
            case "O":
                let c = pt(), r = num() * s
                path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            case "R":
                let o = pt(), w = num() * s, h = num() * s, r = num() * s
                path.addRoundedRect(in: CGRect(x: o.x, y: o.y, width: w, height: h),
                                    cornerSize: CGSize(width: r, height: r),
                                    style: .continuous)
            case "K":
                let c = pt(), r = num() * s
                let a0 = num(), a1 = num()
                path.move(to: CGPoint(x: c.x + r * cos(a0 * .pi / 180),
                                      y: c.y + r * sin(a0 * .pi / 180)))
                path.addArc(center: c, radius: r,
                            startAngle: .degrees(Double(a0)), endAngle: .degrees(Double(a1)),
                            clockwise: false)
                cursor = CGPoint(x: c.x + r * cos(a1 * .pi / 180),
                                 y: c.y + r * sin(a1 * .pi / 180))
            default:
                tokens = tokens.dropFirst()
            }
        }
        return path
    }
}

// MARK: - Icon catalogue

enum Icon: String {
    // Navigation
    case back, forward, up, refresh, chevronRight, chevronDown, chevronUp, chevronLeft, search
    // Command bar
    case newItem, cut, copy, paste, rename, share, delete, sort, view, filter, more
    case info, detailsPane, undo, redo, selectAll, properties, openWith, compress, terminal
    // Caption
    case minimize, maximize, restore, close, tabClose, plus
    // Sidebar / places
    case home, gallery, cloud, desktop, download, document, picture, music, video
    case thisPC, network, recycleBin, folderOutline, newFolder, drive
    // Misc
    case pin, star, people, clock, gridView, listView, checkmark, sortAsc, sortDesc
    case link, eye, refreshSmall, dot, shield, hidden, settings, unpin, palette, keyboard, code

    var stroke: String { Icon.table[self]?.0 ?? "" }
    var fill: String { Icon.table[self]?.1 ?? "" }
    var accentStroke: String { Icon.accentTable[self]?.0 ?? "" }
    var accentFill: String { Icon.accentTable[self]?.1 ?? "" }

    /// Windows 11 draws part of several command-bar glyphs in the accent colour.
    static let accentTable: [Icon: (String, String)] = [
        .cut:    ("O 4.1 12.4 1.8 O 11.9 12.4 1.8", ""),
        .copy:   ("R 5.6 2.3 8.0 8.0 1.4", ""),
        .paste:  ("R 5.6 6.2 5.6 5.4 1.0", ""),
        .rename: ("M4.4 10.2 L6.5 5.6 L8.6 10.2 M5.15 8.6 H7.85", ""),
        .share:  ("M8.0 7.6 L13.2 2.6 M9.9 2.6 H13.4 V6.1", ""),
        .sort:   ("M11.3 3.3 V12.3 M9.2 10.2 L11.3 12.5 L13.4 10.2", ""),
        .view:   ("O 4.3 4.2 1.7 O 4.3 11.4 1.7", ""),
    ]

    // (strokedPath, filledPath)
    static let table: [Icon: (String, String)] = [
        .back:        ("M13 8 H3.6 M7.8 3.9 L3.5 8 L7.8 12.1", ""),
        .forward:     ("M3 8 H12.4 M8.2 3.9 L12.5 8 L8.2 12.1", ""),
        .up:          ("M8 13 V3.6 M3.9 7.8 L8 3.5 L12.1 7.8", ""),
        .refresh:     ("K 8 8 4.7 350 660", "M10.15 3.5 L13.1 4.9 L11.0 7.3 Z"),
        .chevronRight:("M6.2 3.4 L10.8 8 L6.2 12.6", ""),
        .chevronLeft: ("M9.8 3.4 L5.2 8 L9.8 12.6", ""),
        .chevronDown: ("M3.4 6.2 L8 10.8 L12.6 6.2", ""),
        .chevronUp:   ("M3.4 9.8 L8 5.2 L12.6 9.8", ""),
        .search:      ("O 6.9 6.9 4.3 M10 10 L13.5 13.5", ""),

        .newItem:     ("O 8 8 5.7 M8 5.1 V10.9 M5.1 8 H10.9", ""),
        .cut:         ("M4.3 2.5 L10.4 11.1 M11.7 2.5 L5.6 11.1", ""),
        .copy:        ("M10.2 12.8 H4.4 C3.4 12.8 2.6 12.0 2.6 11.0 V5.4", ""),
        .paste:       ("R 3.4 3.0 9.2 10.6 1.5 M6.2 3.0 V2.4 C6.2 1.9 6.5 1.6 7 1.6 H9 C9.5 1.6 9.8 1.9 9.8 2.4 V3.0", ""),
        .rename:      ("R 2.2 4.0 8.6 8.2 1.3 M12.6 3.4 V12.6 M11.3 3.4 H13.9 M11.3 12.6 H13.9", ""),
        .share:       ("M9.2 3.3 H5.4 C4.3 3.3 3.5 4.1 3.5 5.2 V11.4 C3.5 12.5 4.3 13.3 5.4 13.3 H10.6 C11.7 13.3 12.5 12.5 12.5 11.4 V8.8", ""),
        .delete:      ("M2.9 4.3 H13.1 M6.3 4.3 V3.1 C6.3 2.85 6.5 2.7 6.75 2.7 H9.25 C9.5 2.7 9.7 2.85 9.7 3.1 V4.3 M4.4 4.3 L5.0 12.9 C5.02 13.15 5.25 13.3 5.5 13.3 H10.5 C10.75 13.3 10.98 13.15 11 12.9 L11.6 4.3", ""),
        .sort:        ("M4.3 12.7 V3.7 M2.2 5.8 L4.3 3.5 L6.4 5.8", ""),
        .view:        ("M8.6 4.2 H13.8 M8.6 6.8 H11.8 M8.6 10.0 H13.8 M8.6 12.6 H11.8", ""),
        .filter:      ("M2.4 3.4 H13.6 L9.2 8.6 V13.4 L6.8 11.8 V8.6 Z", ""),
        .more:        ("", "O 3.3 8 1.1 O 8 8 1.1 O 12.7 8 1.1"),
        .info:        ("O 8 8 5.8 M8 7.2 V11.3", "O 8 5.2 0.75"),
        .detailsPane: ("R 2 3.2 12 9.6 1.3 M9.6 3.2 V12.8 M4.1 6.2 H7.5 M4.1 8.6 H7.5", ""),
        .undo:        ("M6.2 4.2 L2.9 7.5 L6.2 10.8 M2.9 7.5 H9.8 C12.1 7.5 13.4 9 13.4 11 V12.6", ""),
        .redo:        ("M9.8 4.2 L13.1 7.5 L9.8 10.8 M13.1 7.5 H6.2 C3.9 7.5 2.6 9 2.6 11 V12.6", ""),
        .selectAll:   ("R 2.4 2.4 11.2 11.2 1.4 M5.1 8.2 L7.2 10.4 L11 5.9", ""),
        .properties:  ("O 8 8 5.8 M8 7.2 V11.3", "O 8 5.2 0.75"),
        .openWith:    ("M8.8 2.6 H13.4 V7.2 M13.4 2.6 L7.6 8.4 M11.4 9.6 V13.4 H2.6 V4.6 H6.4", ""),
        .compress:    ("M2 12.6 V4 H6.5 L7.9 5.6 H14 V12.6 Z M9 7.4 H10.6 M9 9.2 H10.6 M9 11 H10.6", ""),
        .terminal:    ("R 2.2 3.2 11.6 9.6 1.2 M4.8 6.6 L6.9 8.5 L4.8 10.4 M8.4 10.6 H11.2", ""),

        .minimize:    ("M3 8 H13", ""),
        .maximize:    ("R 3.6 3.6 8.8 8.8 0.7", ""),
        .restore:     ("R 2.8 5.2 8 8 0.7 M5.4 5.2 V2.8 H13.2 V10.6 H10.8", ""),
        .close:       ("M3.8 3.8 L12.2 12.2 M12.2 3.8 L3.8 12.2", ""),
        .tabClose:    ("M4.6 4.6 L11.4 11.4 M11.4 4.6 L4.6 11.4", ""),
        .plus:        ("M8 3.4 V12.6 M3.4 8 H12.6", ""),

        .home:        ("M2.4 7.8 L8 2.9 L13.6 7.8 M4.1 6.6 V13.1 H11.9 V6.6", ""),
        .gallery:     ("R 2.1 3.3 11.8 9.4 1.3 M2.1 10.7 L5.6 7.5 L8.4 10.2 L10.5 8.4 L13.9 11.6 O 10.5 6.2 1.15", ""),
        .cloud:       ("M4.7 12.3 C2.7 12.3 1.9 10.8 2.5 9.6 C2.9 8.8 3.9 8.5 4.6 8.7 C4.6 6.1 6.6 4.4 8.8 4.6 C10.9 4.8 12.3 6.5 12.5 8.4 C13.9 8.6 14.6 9.9 14.2 11.1 C13.9 12.0 13.1 12.3 12.3 12.3 Z", ""),
        .desktop:     ("R 1.8 3 12.4 8.3 1.1 M6.1 11.3 V13.3 M9.9 11.3 V13.3 M4.6 13.4 H11.4", ""),
        .download:    ("M8 2.6 V10.4 M5.1 7.6 L8 10.6 L10.9 7.6 M2.8 12.9 H13.2", ""),
        .document:    ("M4.1 2.2 H9.4 L12.3 5.1 V13.8 H4.1 Z M9.4 2.2 V5.1 H12.3 M6.1 8.2 H10.3 M6.1 10.6 H10.3", ""),
        .picture:     ("R 1.9 3.2 12.2 9.6 1.3 M1.9 11.1 L5.5 7.6 L8 9.9 L10.2 8 L14.1 11.5 O 10.6 6.2 1.1", ""),
        .music:       ("M6 12.1 V3.6 L12.4 2.2 V10.6 O 4.3 12.2 1.75 O 10.7 10.8 1.75", ""),
        .video:       ("R 1.8 3.4 12.4 9.2 1.3", "M6.4 6.1 L10.6 8 L6.4 9.9 Z"),
        .thisPC:      ("R 1.8 3 12.4 8.3 1.1 M6.1 11.3 V13.3 M9.9 11.3 V13.3 M4.6 13.4 H11.4", ""),
        .drive:       ("R 1.8 5.6 12.4 5.6 1.2 M4.2 8.4 H4.3 M6.2 8.4 H11.6", ""),
        .network:     ("O 8 8 5.8 M2.2 8 H13.8 M8 2.2 C10.5 4.7 10.5 11.3 8 13.8 C5.5 11.3 5.5 4.7 8 2.2", ""),
        .recycleBin:  ("M2.9 4.3 H13.1 M6.3 4.3 V2.8 H9.7 V4.3 M4.3 4.3 L4.9 13.3 H11.1 L11.7 4.3", ""),
        .folderOutline:("M1.9 12.7 V4 H6.4 L7.8 5.6 H14.1 V12.7 Z", ""),
        .newFolder:   ("M1.9 12.7 V4 H6.4 L7.8 5.6 H14.1 V12.7 Z M8 7.4 V11 M6.2 9.2 H9.8", ""),

        .pin:         ("M9.5 1.9 L14.1 6.5 M11.3 3.7 L8.6 6.4 C7.0 6.0 5.4 6.6 4.6 7.6 L8.4 11.4 C9.4 10.6 10.0 9.0 9.6 7.4 L12.3 4.7 M6.5 9.5 L2.5 13.5", ""),
        .star:        ("M8 2.3 L9.8 6.2 L14 6.7 L10.9 9.6 L11.7 13.7 L8 11.7 L4.3 13.7 L5.1 9.6 L2 6.7 L6.2 6.2 Z", ""),
        .people:      ("O 6 5.4 2.6 M1.9 13.1 C1.9 10.3 3.7 8.7 6 8.7 C8.3 8.7 10.1 10.3 10.1 13.1 O 11.5 5.9 2.05 M11.5 9 C13.3 9 14.4 10.5 14.4 13.1", ""),
        .clock:       ("O 8 8 5.8 M8 4.7 V8.2 L10.4 9.8", ""),
        .gridView:    ("R 2.4 2.4 4.5 4.5 0.9 R 9.1 2.4 4.5 4.5 0.9 R 2.4 9.1 4.5 4.5 0.9 R 9.1 9.1 4.5 4.5 0.9", ""),
        .listView:    ("M2.4 4 H4.3 M6.1 4 H13.6 M2.4 8 H4.3 M6.1 8 H13.6 M2.4 12 H4.3 M6.1 12 H13.6", ""),
        .checkmark:   ("M3 8.4 L6.4 11.8 L13 4.4", ""),
        .sortAsc:     ("", "M8 5.4 L11.8 10.2 L4.2 10.2 Z"),
        .sortDesc:    ("", "M8 10.6 L4.2 5.8 L11.8 5.8 Z"),
        .link:        ("M6.8 9.2 C7.8 10.2 9.4 10.2 10.4 9.2 L12.6 7 C13.6 6 13.6 4.4 12.6 3.4 C11.6 2.4 10 2.4 9 3.4 L8.2 4.2 M9.2 6.8 C8.2 5.8 6.6 5.8 5.6 6.8 L3.4 9 C2.4 10 2.4 11.6 3.4 12.6 C4.4 13.6 6 13.6 7 12.6 L7.8 11.8", ""),
        .eye:         ("M1.6 8 C3.7 4.9 6 3.5 8 3.5 C10 3.5 12.3 4.9 14.4 8 C12.3 11.1 10 12.5 8 12.5 C6 12.5 3.7 11.1 1.6 8 Z O 8 8 2.05", ""),
        .hidden:      ("M1.6 8 C3.7 4.9 6 3.5 8 3.5 C10 3.5 12.3 4.9 14.4 8 C12.3 11.1 10 12.5 8 12.5 C6 12.5 3.7 11.1 1.6 8 Z M2.6 13.4 L13.4 2.6", ""),
        .shield:      ("M8 2.2 L13.2 4 V8.2 C13.2 11.2 10.9 13.2 8 13.9 C5.1 13.2 2.8 11.2 2.8 8.2 V4 Z", ""),
        .refreshSmall:("K 8 8 4.7 350 660", "M10.15 3.5 L13.1 4.9 L11.0 7.3 Z"),
        .dot:         ("", "O 8 8 2.4"),
        .code:        ("M6.0 4.6 L2.2 8 L6.0 11.4 M10.0 4.6 L13.8 8 L10.0 11.4", ""),
        .settings:    ("O 8 8 2.4 O 8 8 5.2 M13.2 8 H14.5 M11.87 11.87 L12.79 12.79 M8 13.2 V14.5 M4.13 11.87 L3.21 12.79 M2.8 8 H1.5 M4.13 4.13 L3.21 3.21 M8 2.8 V1.5 M11.87 4.13 L12.79 3.21", ""),
        .unpin:       ("M9.5 1.9 L14.1 6.5 M11.3 3.7 L8.6 6.4 C7.0 6.0 5.4 6.6 4.6 7.6 L8.4 11.4 C9.4 10.6 10.0 9.0 9.6 7.4 L12.3 4.7 M6.5 9.5 L2.5 13.5 M2.2 2.2 L13.8 13.8", ""),
        .palette:     ("M8 2.2 C11.4 2.2 14 4.6 14 7.7 C14 9.8 12.5 10.9 11 10.9 H9.8 C9.1 10.9 8.6 11.4 8.6 12 C8.6 12.3 8.7 12.5 8.9 12.8 C9.1 13.1 9.2 13.4 9.2 13.7 C9.2 14.3 8.7 14.8 8 14.8 C4.6 14.8 2 12.1 2 8.5 C2 4.9 4.6 2.2 8 2.2 Z O 5.2 7.2 1.0 O 8.4 5.2 1.0 O 11.2 7.4 1.0", ""),
        .keyboard:    ("R 1.6 4.2 12.8 7.6 1.3 M4.2 6.6 H4.3 M6.6 6.6 H6.7 M9.0 6.6 H9.1 M11.4 6.6 H11.5 M4.2 9.4 H11.4", ""),
    ]
}

// MARK: - Renderer

struct Glyph: View {
    let icon: Icon
    var size: CGFloat = 16
    var color: Color = Win.text
    /// Stroke width expressed at the 16pt design size.
    var weight: CGFloat = 1.15
    /// Draws the accent layer some Fluent glyphs carry.
    var twoTone: Bool = true
    var accentColor: Color = Win.accentSecondary

    var body: some View {
        let s = size / 16
        Canvas { ctx, _ in
            let fill = icon.fill
            if !fill.isEmpty {
                ctx.fill(PathSpec.parse(fill, scale: s), with: .color(color))
            }
            let stroke = icon.stroke
            if !stroke.isEmpty {
                ctx.stroke(PathSpec.parse(stroke, scale: s), with: .color(color),
                           style: StrokeStyle(lineWidth: weight * s,
                                              lineCap: .round, lineJoin: .round))
            }
            if twoTone {
                let af = icon.accentFill
                if !af.isEmpty {
                    ctx.fill(PathSpec.parse(af, scale: s), with: .color(accentColor))
                }
                let a = icon.accentStroke
                if !a.isEmpty {
                    ctx.stroke(PathSpec.parse(a, scale: s), with: .color(accentColor),
                               style: StrokeStyle(lineWidth: weight * s,
                                                  lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}
