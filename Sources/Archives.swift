import Foundation
import AppKit

struct ArchiveEntry {
    let path: String
    let size: Int64
    let modified: Date
    let isDirectory: Bool
}

/// Reads archives with the system's bsdtar, which handles zip and the tar
/// family. RAR and 7z would need binaries macOS does not ship.
enum Archives {
    static let readable: Set<String> = [
        "zip", "jar", "war", "ipa", "cbz", "xpi",
        "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst",
    ]

    static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard readable.contains(ext) else { return false }
        // "foo.tar.gz" reads fine, but a bare ".gz" of a single file does not
        // list usefully, so only treat gz as an archive when it wraps a tar.
        if ext == "gz" || ext == "bz2" || ext == "xz" || ext == "zst" {
            return url.deletingPathExtension().pathExtension.lowercased() == "tar"
        }
        return true
    }

    private static var cache: [String: (stamp: Date, entries: [ArchiveEntry])] = [:]

    static func list(_ archive: URL) -> [ArchiveEntry] {
        let stamp = (try? archive.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        if let hit = cache[archive.path], hit.stamp == stamp { return hit.entries }

        let output = run(["/usr/bin/bsdtar", "-tvf", archive.path])
        var entries: [ArchiveEntry] = []
        for line in output.split(separator: "\n") {
            guard let entry = parse(String(line)) else { continue }
            entries.append(entry)
        }
        cache[archive.path] = (stamp, entries)
        return entries
    }

    /// `-rw-r--r--  0 user group  1234 Aug 20 00:15 path/to/file`
    private static func parse(_ line: String) -> ArchiveEntry? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 9 else { return nil }
        let permissions = String(parts[0])
        guard let size = Int64(parts[4]) else { return nil }

        // The name starts after the three date fields, and may contain spaces.
        var name = parts[8...].joined(separator: " ")
        if let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("./") { name.removeFirst(2) }
        let isDirectory = permissions.hasPrefix("d") || name.hasSuffix("/")
        if name.hasSuffix("/") { name.removeLast() }
        guard !name.isEmpty else { return nil }

        let stamp = "\(parts[5]) \(parts[6]) \(parts[7])"
        return ArchiveEntry(path: name, size: size,
                            modified: date(from: stamp), isDirectory: isDirectory)
    }

    private static let listingDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d HH:mm"
        return f
    }()

    private static let listingYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d yyyy"
        return f
    }()

    private static func date(from text: String) -> Date {
        if let parsed = listingYear.date(from: text) { return parsed }
        guard let parsed = listingDate.date(from: text) else { return .distantPast }
        // The listing omits the year for recent entries, so graft this one on.
        let calendar = Calendar.current
        var components = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
        components.year = calendar.component(.year, from: Date())
        return calendar.date(from: components) ?? parsed
    }

    /// The immediate children of a path inside the archive.
    static func children(of archive: URL, at inner: String) -> [FileItem] {
        let entries = list(archive)
        let prefix = inner.isEmpty ? "" : inner + "/"
        var seen = Set<String>()
        var items: [FileItem] = []

        for entry in entries {
            guard entry.path.hasPrefix(prefix) else { continue }
            let remainder = String(entry.path.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }
            let components = remainder.split(separator: "/")
            let name = String(components[0])
            guard !seen.contains(name) else { continue }
            seen.insert(name)

            // A name with more path after it is a folder, whether or not the
            // archive bothered to store an entry for it.
            let isDirectory = components.count > 1 || entry.isDirectory
            let fullPath = prefix + name
            items.append(FileItem(
                url: archive.appendingPathComponent(fullPath),
                name: name,
                isDirectory: isDirectory,
                isPackage: false,
                isHidden: name.hasPrefix("."),
                isSymlink: false,
                size: isDirectory ? 0 : entry.size,
                modified: entry.modified,
                created: entry.modified,
                ext: isDirectory ? "" : (name as NSString).pathExtension))
        }
        return items
    }

    /// Extracts whole entries, or the entire archive when `entries` is empty.
    @discardableResult
    static func extract(_ archive: URL, entries: [String], to destination: URL) -> String? {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var arguments = ["/usr/bin/bsdtar", "-x", "-f", archive.path, "-C", destination.path]
        arguments += entries
        let output = run(arguments)
        return output.contains("Error") ? output : nil
    }

    /// Pulls one file out to a scratch folder so it can be opened.
    static func stage(_ archive: URL, entry: String) -> URL? {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("winexp-archive")
            .appendingPathComponent(UUID().uuidString)
        if extract(archive, entries: [entry], to: scratch) != nil { return nil }
        let staged = scratch.appendingPathComponent(entry)
        return FileManager.default.fileExists(atPath: staged.path) ? staged : nil
    }

    /// A sensible folder name for "extract all", beside the archive.
    static func extractionFolder(for archive: URL) -> URL {
        var name = archive.deletingPathExtension().lastPathComponent
        if (name as NSString).pathExtension.lowercased() == "tar" {
            name = (name as NSString).deletingPathExtension
        }
        return Ops.uniqueURL(for: name, in: archive.deletingLastPathComponent(), copySuffix: false)
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return "Error: \(error.localizedDescription)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
