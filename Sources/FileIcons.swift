import SwiftUI
import AppKit
import QuickLookThumbnailing

// MARK: - Windows 11 folder

struct FolderIcon: View {
    var size: CGFloat = 16
    var open: Bool = false

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let r = w * 0.085

            // Back panel / tab
            var tab = Path()
            let tabTop = h * 0.115, tabBottom = h * 0.46
            tab.move(to: CGPoint(x: 0, y: tabTop + r))
            tab.addQuadCurve(to: CGPoint(x: r, y: tabTop), control: CGPoint(x: 0, y: tabTop))
            tab.addLine(to: CGPoint(x: w * 0.355, y: tabTop))
            tab.addLine(to: CGPoint(x: w * 0.475, y: h * 0.245))
            tab.addLine(to: CGPoint(x: w, y: h * 0.245))
            tab.addLine(to: CGPoint(x: w, y: tabBottom))
            tab.addLine(to: CGPoint(x: 0, y: tabBottom))
            tab.closeSubpath()
            ctx.fill(tab, with: .linearGradient(
                Gradient(colors: [Color(red: 0.91, green: 0.66, blue: 0.05),
                                  Color(red: 0.84, green: 0.58, blue: 0.0)]),
                startPoint: CGPoint(x: 0, y: tabTop), endPoint: CGPoint(x: 0, y: tabBottom)))

            // Front panel
            let bodyTop = h * 0.245
            let body = Path(roundedRect: CGRect(x: 0, y: bodyTop, width: w, height: h - bodyTop - h * 0.09),
                            cornerRadius: r, style: .continuous)
            ctx.fill(body, with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.50),
                                  Color(red: 1.0, green: 0.78, blue: 0.24)]),
                startPoint: CGPoint(x: w * 0.2, y: bodyTop),
                endPoint: CGPoint(x: w * 0.9, y: h)))
        }
        .frame(width: size, height: size)
    }
}

/// The zipped-folder icon: folder plus zipper.
struct ArchiveIcon: View {
    var size: CGFloat = 16
    var body: some View {
        ZStack {
            FolderIcon(size: size)
            Canvas { ctx, sz in
                let w = sz.width, h = sz.height
                var teeth = Path()
                var y = h * 0.30
                while y < h * 0.86 {
                    teeth.addRect(CGRect(x: w * 0.44, y: y, width: w * 0.12, height: h * 0.05))
                    y += h * 0.10
                }
                ctx.fill(teeth, with: .color(Color(white: 0.35, opacity: 0.75)))
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Generic file sheet

struct FileSheetIcon: View {
    var size: CGFloat = 16
    var kind: FileKind
    var label: String = ""

    private var accent: Color {
        switch kind {
        case .pdf: return Color(red: 0.90, green: 0.24, blue: 0.20)
        case .word: return Color(red: 0.16, green: 0.34, blue: 0.60)
        case .excel: return Color(red: 0.13, green: 0.45, blue: 0.27)
        case .powerpoint: return Color(red: 0.82, green: 0.28, blue: 0.15)
        case .image: return Color(red: 0.18, green: 0.49, blue: 0.60)
        case .video: return Color(red: 0.48, green: 0.31, blue: 0.75)
        case .audio: return Color(red: 0.77, green: 0.35, blue: 0.07)
        case .code: return Color(red: 0.29, green: 0.55, blue: 0.75)
        case .text: return Color(red: 0.36, green: 0.48, blue: 0.60)
        case .executable: return Color(red: 0.35, green: 0.38, blue: 0.42)
        case .font: return Color(red: 0.25, green: 0.25, blue: 0.28)
        case .disk: return Color(red: 0.42, green: 0.45, blue: 0.52)
        case .shortcut: return Color(red: 0.35, green: 0.55, blue: 0.80)
        default: return Color(red: 0.55, green: 0.60, blue: 0.66)
        }
    }

    private var badge: String {
        if !label.isEmpty { return label }
        switch kind {
        case .pdf: return "PDF"
        case .word: return "DOC"
        case .excel: return "XLS"
        case .powerpoint: return "PPT"
        case .image: return "IMG"
        case .video: return "VID"
        case .audio: return "MP3"
        case .code: return "<>"
        case .text: return "TXT"
        case .executable: return "EXE"
        case .font: return "TT"
        case .disk: return "ISO"
        default: return ""
        }
    }

    var body: some View {
        let s = size
        ZStack {
            Canvas { ctx, sz in
                let w = sz.width, h = sz.height
                let px = w * 0.16, pw = w * 0.68
                let fold = w * 0.26
                var page = Path()
                let r = w * 0.05
                page.move(to: CGPoint(x: px + r, y: h * 0.06))
                page.addLine(to: CGPoint(x: px + pw - fold, y: h * 0.06))
                page.addLine(to: CGPoint(x: px + pw, y: h * 0.06 + fold))
                page.addLine(to: CGPoint(x: px + pw, y: h * 0.94 - r))
                page.addQuadCurve(to: CGPoint(x: px + pw - r, y: h * 0.94),
                                  control: CGPoint(x: px + pw, y: h * 0.94))
                page.addLine(to: CGPoint(x: px + r, y: h * 0.94))
                page.addQuadCurve(to: CGPoint(x: px, y: h * 0.94 - r), control: CGPoint(x: px, y: h * 0.94))
                page.addLine(to: CGPoint(x: px, y: h * 0.06 + r))
                page.addQuadCurve(to: CGPoint(x: px + r, y: h * 0.06), control: CGPoint(x: px, y: h * 0.06))
                page.closeSubpath()

                ctx.fill(page, with: .linearGradient(
                    Gradient(colors: [Color(white: 1.0), Color(white: 0.90)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
                ctx.stroke(page, with: .color(Color(white: 0.62)), lineWidth: max(0.6, w * 0.025))

                // Folded corner
                var f = Path()
                f.move(to: CGPoint(x: px + pw - fold, y: h * 0.06))
                f.addLine(to: CGPoint(x: px + pw, y: h * 0.06 + fold))
                f.addLine(to: CGPoint(x: px + pw - fold, y: h * 0.06 + fold))
                f.closeSubpath()
                ctx.fill(f, with: .color(Color(white: 0.75)))

                // Coloured type band
                if w >= 20 {
                    let band = Path(roundedRect:
                        CGRect(x: px - w * 0.06, y: h * 0.56, width: pw * 0.86, height: h * 0.26),
                        cornerRadius: w * 0.035, style: .continuous)
                    ctx.fill(band, with: .color(accent))
                } else {
                    let band = Path(CGRect(x: px, y: h * 0.62, width: pw, height: h * 0.20))
                    ctx.fill(band, with: .color(accent))
                }
            }
            if s >= 28 {
                Text(badge)
                    .font(.system(size: s * 0.155, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: -s * 0.03, y: s * 0.19)
            }
        }
        .frame(width: s, height: s)
    }
}

// MARK: - Thumbnails

final class ThumbCache {
    static let shared = ThumbCache()
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight = Set<String>()

    func cached(_ url: URL, size: CGFloat) -> NSImage? {
        cache.object(forKey: key(url, size))
    }

    private func key(_ url: URL, _ size: CGFloat) -> NSString {
        "\(url.path)|\(Int(size))" as NSString
    }

    func request(_ url: URL, size: CGFloat, done: @escaping (NSImage) -> Void) {
        let k = key(url, size) as String
        if inFlight.contains(k) { return }
        inFlight.insert(k)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size),
            scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            DispatchQueue.main.async {
                self.inFlight.remove(k)
                guard let rep else { return }
                let img = rep.nsImage
                self.cache.setObject(img, forKey: self.key(url, size))
                done(img)
            }
        }
    }
}

struct ThumbnailIcon: View {
    let url: URL
    let size: CGFloat
    let kind: FileKind
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.28), radius: size * 0.02, y: size * 0.015)
            } else {
                FileSheetIcon(size: size, kind: kind)
            }
        }
        .onAppear {
            if let c = ThumbCache.shared.cached(url, size: size) { image = c; return }
            ThumbCache.shared.request(url, size: size) { img in image = img }
        }
    }
}

// MARK: - Dispatcher

/// A folder icon honouring any per-folder customisation.
struct FolderGlyph: View {
    let url: URL
    var size: CGFloat = 16
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        if let style = settings.style(for: url) {
            CustomFolderIcon(style: style, size: size)
        } else {
            FolderIcon(size: size)
        }
    }
}

struct ItemIcon: View {
    let item: FileItem
    var size: CGFloat = 16

    var body: some View {
        switch item.kind {
        case .folder:
            FolderGlyph(url: item.url, size: size)
        case .archive:
            ArchiveIcon(size: size)
        case .app, .executable:
            SystemIcon(url: item.url, size: size)
        case .image, .video, .pdf:
            if size >= 24 { ThumbnailIcon(url: item.url, size: size, kind: item.kind) }
            else { FileSheetIcon(size: size, kind: item.kind) }
        case .drive, .disk:
            FileSheetIcon(size: size, kind: .disk)
        default:
            FileSheetIcon(size: size, kind: item.kind,
                          label: item.ext.isEmpty ? "" : String(item.ext.prefix(3)).uppercased())
        }
    }
}

/// Windows shows an executable's embedded icon; the macOS equivalent is the bundle icon.
struct SystemIcon: View {
    let url: URL
    let size: CGFloat
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// A drive icon for This PC (rounded box + capacity bar handled by the caller).
struct DriveIcon: View {
    var size: CGFloat = 32
    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let body = Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.22, width: w * 0.88, height: h * 0.56),
                            cornerRadius: w * 0.09, style: .continuous)
            ctx.fill(body, with: .linearGradient(
                Gradient(colors: [Color(white: 0.86), Color(white: 0.68)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            let strip = Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.22, width: w * 0.88, height: h * 0.18),
                             cornerRadius: w * 0.06, style: .continuous)
            ctx.fill(strip, with: .color(Color(red: 0.42, green: 0.62, blue: 0.85)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.74, y: h * 0.56, width: w * 0.10, height: h * 0.10)),
                     with: .color(Color(white: 0.45)))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Coloured place icons for the navigation pane

struct PlaceIcon: View {
    let place: Place
    var size: CGFloat = 16

    private var tint: Color {
        switch place.accent {
        case .blue:   return Color(red: 0.25, green: 0.55, blue: 0.90)
        case .green:  return Color(red: 0.24, green: 0.66, blue: 0.36)
        case .teal:   return Color(red: 0.20, green: 0.60, blue: 0.65)
        case .purple: return Color(red: 0.55, green: 0.36, blue: 0.83)
        case .orange: return Color(red: 0.90, green: 0.49, blue: 0.13)
        case .pink:   return Color(red: 0.90, green: 0.35, blue: 0.55)
        case .red:    return Color(red: 0.85, green: 0.27, blue: 0.24)
        case .neutral: return Win.textSecondary
        }
    }

    var body: some View {
        Glyph(icon: place.icon, size: size, color: tint, weight: 1.25)
    }
}
