import SwiftUI
import AppKit

// MARK: - Server bookmarks

struct ServerBookmark: Codable, Identifiable, Hashable {
    var id: String { address }
    var address: String
    var title: String
}

enum RemoteServers {
    static let schemes = ["smb", "afp", "nfs", "ftp", "https", "http"]

    static var recent: [ServerBookmark] {
        get {
            guard let data = Store.defaults.data(forKey: "servers"),
                  let list = try? JSONDecoder().decode([ServerBookmark].self, from: data)
            else { return [] }
            return list
        }
        set {
            Store.defaults.set(try? JSONEncoder().encode(newValue), forKey: "servers")
        }
    }

    static func remember(_ address: String) {
        var list = recent.filter { $0.address != address }
        let host = URL(string: address)?.host ?? address
        list.insert(ServerBookmark(address: address, title: host), at: 0)
        recent = Array(list.prefix(12))
    }

    static func forget(_ bookmark: ServerBookmark) {
        recent = recent.filter { $0.id != bookmark.id }
    }

    /// Hands the URL to macOS, which owns the authentication UI and the keychain.
    /// Deliberately not reimplemented in-app: this way no password passes through
    /// File Explorer at all.
    static func connect(_ address: String, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: address), url.host != nil else {
            completion(nil)
            return
        }
        let before = Set(mountedVolumes().map(\.path))
        NSWorkspace.shared.open(url)
        remember(address)

        // Watch /Volumes for whatever appears once the user has authenticated.
        var waited = 0.0
        func poll() {
            waited += 1.0
            let now = mountedVolumes()
            if let fresh = now.first(where: { !before.contains($0.path) }) {
                completion(fresh)
                return
            }
            if waited > 90 { completion(nil); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: poll)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: poll)
    }

    static func mountedVolumes() -> [URL] {
        FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsLocalKey],
            options: [.skipHiddenVolumes]) ?? []
    }

    static func networkVolumes() -> [URL] {
        mountedVolumes().filter { url in
            let local = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal
            return local == false
        }
    }

    static func eject(_ url: URL) {
        try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
    }
}

// MARK: - Dialog

struct ConnectServerDialog: View {
    let onClose: () -> Void

    @State private var address = "smb://"
    @State private var bookmarks = RemoteServers.recent
    @State private var connecting = false
    @State private var note: String?

    var body: some View {
        WinDialog(title: "Connect to server", width: 500, onClose: onClose) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Address")
                    .font(Win.body(11)).foregroundStyle(Win.textTertiary)
                HStack(spacing: 8) {
                    TextField("smb://server/share", text: $address)
                        .textFieldStyle(.plain)
                        .font(Win.body(12))
                        .foregroundStyle(Win.text)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(WinRR(radius: 4).fill(Win.field))
                        .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
                        .onSubmit { connect() }
                    WinButton(padding: 8, height: 30) {
                        address = "smb://"
                    } content: {
                        Glyph(icon: .tabClose, size: 11, color: Win.textSecondary, weight: 1.2)
                    }
                }

                Text("SMB, AFP, NFS, FTP and WebDAV. macOS handles the sign-in, so no password is typed into File Explorer.")
                    .font(Win.body(11)).foregroundStyle(Win.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let note {
                    Text(note).font(Win.body(11)).foregroundStyle(Win.accent)
                }

                if !bookmarks.isEmpty {
                    Text("Recent servers")
                        .font(Win.body(11, weight: .semibold)).foregroundStyle(Win.textSecondary)
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(bookmarks) { bookmark in
                                HStack(spacing: 10) {
                                    Glyph(icon: .network, size: 15, color: Win.textSecondary, weight: 1.15)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(bookmark.title)
                                            .font(Win.body(12)).foregroundStyle(Win.text)
                                        Text(bookmark.address)
                                            .font(Win.body(11)).foregroundStyle(Win.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    WinButton(tooltip: "Forget", padding: 5, height: 24) {
                                        RemoteServers.forget(bookmark)
                                        bookmarks = RemoteServers.recent
                                    } content: {
                                        Glyph(icon: .tabClose, size: 10, color: Win.textTertiary, weight: 1.2)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 40)
                                .background(WinRR(radius: 5).fill(Win.controlFill.opacity(0.5)))
                                .contentShape(Rectangle())
                                .onTapGesture { address = bookmark.address }
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }
            .padding(18)
        } footer: {
            WinDialogButton(title: connecting ? "Connecting…" : "Connect", primary: true,
                            enabled: !connecting && address.contains("://")
                                && address.count > 7) {
                connect()
            }
            WinDialogButton(title: "Cancel", action: onClose)
        }
    }

    private func connect() {
        connecting = true
        note = "Waiting for macOS to mount the share."
        RemoteServers.connect(address) { mounted in
            connecting = false
            bookmarks = RemoteServers.recent
            if let mounted {
                AppState.shared.active?.go(to: mounted)
                onClose()
            } else {
                note = "No new volume appeared. If the sign-in window is still open, finish it and the share will show up under Network."
            }
        }
    }
}
