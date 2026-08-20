import Foundation
import AppKit

// MARK: - Model

struct TransferJob: Identifiable {
    enum Kind: String { case copy = "Copying", move = "Moving", delete = "Deleting" }
    enum State: Equatable { case waiting, running, finished, cancelled, failed(String) }

    let id = UUID()
    let kind: Kind
    let sources: [URL]
    let destination: URL?
    var state: State = .waiting
    var bytesTotal: Int64 = 0
    var bytesDone: Int64 = 0
    var filesTotal: Int = 0
    var filesDone: Int = 0
    var currentName: String = ""
    var startedAt: Date? = nil
    /// Paths produced by the job, for undo.
    var created: [URL] = []
    var moved: [(from: URL, to: URL)] = []

    var fraction: Double {
        guard bytesTotal > 0 else { return state == .finished ? 1 : 0 }
        return min(1, Double(bytesDone) / Double(bytesTotal))
    }

    var isActive: Bool { state == .waiting || state == .running }

    /// "12.4 MB of 300 MB", the way Explorer's copy dialog reads.
    var sizeText: String {
        "\(FileItem.friendlySize(bytesDone)) of \(FileItem.friendlySize(bytesTotal))"
    }

    var rateText: String {
        guard let startedAt, state == .running else { return "" }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0.6, bytesDone > 0 else { return "" }
        let perSecond = Double(bytesDone) / elapsed
        let remaining = Double(bytesTotal - bytesDone) / max(perSecond, 1)
        return "\(FileItem.friendlySize(Int64(perSecond)))/s, \(TransferJob.timeText(remaining)) left"
    }

    static func timeText(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded())) seconds" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded())) minutes" }
        return String(format: "%.1f hours", seconds / 3600)
    }
}

// MARK: - Queue

final class TransferQueue: ObservableObject {
    static let shared = TransferQueue()

    @Published private(set) var jobs: [TransferJob] = []
    @Published var panelOpen = false

    private let worker = DispatchQueue(label: "com.winexplorer.transfers", qos: .userInitiated)
    private var cancelled = Set<UUID>()
    private var completion: [UUID: (TransferJob) -> Void] = [:]
    private var running = false

    var active: [TransferJob] { jobs.filter(\.isActive) }
    var hasActive: Bool { !active.isEmpty }

    var overallFraction: Double {
        let running = active
        guard !running.isEmpty else { return 0 }
        return running.map(\.fraction).reduce(0, +) / Double(running.count)
    }

    var summary: String {
        let running = active
        guard let first = running.first else { return "" }
        if running.count > 1 { return "\(first.kind.rawValue) \(running.count) sets of items" }
        return "\(first.kind.rawValue) \(first.filesDone) of \(first.filesTotal) items"
    }

    // MARK: Submitting work

    func enqueue(kind: TransferJob.Kind, sources: [URL], to destination: URL?,
                 onFinish: ((TransferJob) -> Void)? = nil) {
        var job = TransferJob(kind: kind, sources: sources, destination: destination)
        job.filesTotal = sources.count
        jobs.append(job)
        if let onFinish { completion[job.id] = onFinish }
        pump()
    }

    func cancel(_ id: UUID) {
        cancelled.insert(id)
        if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state == .waiting {
            jobs[i].state = .cancelled
        }
    }

    func clearFinished() {
        jobs.removeAll { !$0.isActive }
    }

    // MARK: Running

    private func pump() {
        guard !running, let next = jobs.firstIndex(where: { $0.state == .waiting }) else { return }
        running = true
        let job = jobs[next]
        jobs[next].state = .running
        jobs[next].startedAt = Date()

        worker.async { [weak self] in
            guard let self else { return }
            let result = self.perform(job)
            DispatchQueue.main.async {
                if let i = self.jobs.firstIndex(where: { $0.id == job.id }) {
                    self.jobs[i] = result
                }
                self.completion.removeValue(forKey: job.id)?(result)
                self.running = false
                self.pump()
                if !self.hasActive {
                    // Tidy finished rows away once the queue drains.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                        if !self.hasActive && !self.panelOpen { self.clearFinished() }
                    }
                }
            }
        }
    }

    private func isCancelled(_ id: UUID) -> Bool {
        var result = false
        DispatchQueue.main.sync { result = self.cancelled.contains(id) }
        return result
    }

    private func update(_ id: UUID, _ change: @escaping (inout TransferJob) -> Void) {
        DispatchQueue.main.async {
            guard let i = self.jobs.firstIndex(where: { $0.id == id }) else { return }
            change(&self.jobs[i])
        }
    }

    private func perform(_ job: TransferJob) -> TransferJob {
        var job = job
        let fm = FileManager.default

        // Measure first so the progress bar means something.
        var totalBytes: Int64 = 0
        var totalFiles = 0
        for url in job.sources {
            let (bytes, files) = Transfers.measure(url)
            totalBytes += bytes
            totalFiles += files
        }
        job.bytesTotal = totalBytes
        job.filesTotal = totalFiles
        update(job.id) { $0.bytesTotal = totalBytes; $0.filesTotal = totalFiles }

        for source in job.sources {
            if isCancelled(job.id) { job.state = .cancelled; return job }

            do {
                switch job.kind {
                case .delete:
                    try fm.removeItem(at: source)
                    job.filesDone += 1
                    update(job.id) { $0.filesDone += 1; $0.currentName = source.lastPathComponent }

                case .move:
                    guard let destination = job.destination else { continue }
                    let target = Ops.uniqueURL(for: source.lastPathComponent,
                                               in: destination, copySuffix: false)
                    if Transfers.sameVolume(source, destination) {
                        try fm.moveItem(at: source, to: target)
                        job.moved.append((source, target))
                        job.bytesDone = job.bytesTotal
                        job.filesDone = job.filesTotal
                        update(job.id) {
                            $0.bytesDone = $0.bytesTotal
                            $0.filesDone = $0.filesTotal
                            $0.currentName = source.lastPathComponent
                        }
                    } else {
                        try copyTree(source, to: target, job: &job)
                        try fm.removeItem(at: source)
                        job.moved.append((source, target))
                    }

                case .copy:
                    guard let destination = job.destination else { continue }
                    let sameDir = source.deletingLastPathComponent().path == destination.path
                    let target = Ops.uniqueURL(for: source.lastPathComponent,
                                               in: destination, copySuffix: sameDir)
                    try copyTree(source, to: target, job: &job)
                    job.created.append(target)
                }
            } catch {
                job.state = .failed(error.localizedDescription)
                return job
            }
        }

        job.state = isCancelled(job.id) ? .cancelled : .finished
        job.bytesDone = job.bytesTotal
        return job
    }

    /// Copies a file or directory, reporting progress as it goes.
    private func copyTree(_ source: URL, to target: URL, job: inout TransferJob) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { return }

        if isDir.boolValue && !Transfers.isPackage(source) {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let children = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil))
                ?? []
            for child in children {
                if isCancelled(job.id) { return }
                try copyTree(child, to: target.appendingPathComponent(child.lastPathComponent),
                             job: &job)
            }
        } else {
            try copyFile(source, to: target, job: &job)
        }
    }

    private func copyFile(_ source: URL, to target: URL, job: inout TransferJob) throws {
        let fm = FileManager.default
        let id = job.id
        update(id) { $0.currentName = source.lastPathComponent }

        // Packages and anything unreadable as a stream fall back to a plain copy.
        guard let input = try? FileHandle(forReadingFrom: source) else {
            try fm.copyItem(at: source, to: target)
            job.filesDone += 1
            update(id) { $0.filesDone += 1 }
            return
        }
        defer { try? input.close() }

        fm.createFile(atPath: target.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: target) else {
            try? input.close()
            try fm.copyItem(at: source, to: target)
            return
        }
        defer { try? output.close() }

        let chunkSize = 1 << 20          // 1 MB
        var sinceUpdate: Int64 = 0
        while true {
            if isCancelled(id) { return }
            let chunk = input.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            output.write(chunk)
            job.bytesDone += Int64(chunk.count)
            sinceUpdate += Int64(chunk.count)
            // Throttle so the UI isn't flooded on fast disks.
            if sinceUpdate > 4 << 20 {
                let done = job.bytesDone
                sinceUpdate = 0
                update(id) { $0.bytesDone = done }
            }
        }

        job.filesDone += 1
        let done = job.bytesDone, files = job.filesDone
        update(id) { $0.bytesDone = done; $0.filesDone = files }

        // Carry over the modification date, as a copy should.
        if let attrs = try? fm.attributesOfItem(atPath: source.path),
           let modified = attrs[.modificationDate] {
            try? fm.setAttributes([.modificationDate: modified], ofItemAtPath: target.path)
        }
    }
}

// MARK: - Helpers

enum Transfers {
    static func measure(_ url: URL) -> (bytes: Int64, files: Int) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return (0, 0) }
        if !isDir.boolValue || isPackage(url) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return (Int64(size), 1)
        }
        var bytes: Int64 = 0, files = 0
        let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                   options: [], errorHandler: { _, _ in true })
        while let child = walker?.nextObject() as? URL {
            let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { continue }
            bytes += Int64(values?.fileSize ?? 0)
            files += 1
        }
        return (bytes, max(files, 1))
    }

    static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let idA = (try? a.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
        let idB = (try? b.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
        guard let x = idA as? NSObject, let y = idB as? NSObject else { return false }
        return x == y
    }
}
