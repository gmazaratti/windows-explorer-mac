import SwiftUI
import AppKit

/// Frames of the visible items, in the window's root coordinate space.
struct ItemFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, b in b })
    }
}

/// Rubber-band selection.
///
/// Handled at the AppKit level rather than with a SwiftUI drag gesture: the
/// list lives inside a ScrollView, which claims drags for scrolling long
/// before a gesture on the background would see them. A window-level monitor
/// takes the press only when it lands on empty space inside a pane, so drags
/// that start on an item still drag the item.
final class MarqueeController: ObservableObject {
    static let shared = MarqueeController()

    struct Zone {
        weak var explorer: Explorer?
        var frame: CGRect = .zero
        var items: [String: CGRect] = [:]
    }

    private var zones: [ObjectIdentifier: Zone] = [:]

    /// The rectangle being dragged, in root coordinates.
    @Published private(set) var rect: CGRect?
    private var owner: ObjectIdentifier?
    private var origin: CGPoint = .zero
    private var baseSelection: Set<String> = []
    private var moved = false

    var isDragging: Bool { owner != nil }

    // MARK: Registration

    func setZone(_ frame: CGRect, for explorer: Explorer) {
        var zone = zones[ObjectIdentifier(explorer)] ?? Zone()
        zone.explorer = explorer
        zone.frame = frame
        zones[ObjectIdentifier(explorer)] = zone
    }

    func setItems(_ items: [String: CGRect], for explorer: Explorer) {
        var zone = zones[ObjectIdentifier(explorer)] ?? Zone()
        zone.explorer = explorer
        zone.items = items
        zones[ObjectIdentifier(explorer)] = zone
    }

    func zone(for explorer: Explorer) -> Zone? { zones[ObjectIdentifier(explorer)] }

    // MARK: Dragging

    /// Starts a band if the point is on empty space inside a pane.
    @discardableResult
    func begin(at point: CGPoint, additive: Bool) -> Bool {
        guard let (id, zone) = zones.first(where: { $0.value.frame.contains(point) }),
              let explorer = zone.explorer else { return false }
        // A press on an item belongs to the item, not to a selection band.
        guard !zone.items.values.contains(where: { $0.contains(point) }) else { return false }

        owner = id
        origin = point
        moved = false
        baseSelection = additive ? explorer.tab.selection : []
        rect = CGRect(origin: point, size: .zero)
        return true
    }

    func update(to point: CGPoint) {
        guard let owner, let zone = zones[owner], let explorer = zone.explorer else { return }
        let band = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                          width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        if band.width > 3 || band.height > 3 { moved = true }
        rect = band.intersection(zone.frame)

        let hits = zone.items.filter { $0.value.intersects(band) }.map(\.key)
        explorer.applyMarquee(Set(hits), base: baseSelection)
    }

    func end() {
        defer {
            owner = nil
            rect = nil
            baseSelection = []
        }
        guard let owner, let zone = zones[owner], let explorer = zone.explorer else { return }
        // A press with no drag is just a click on the background.
        if !moved && baseSelection.isEmpty { explorer.selectNone() }
    }

    // MARK: Event routing

    /// Returns true when the event has been taken over by a selection band.
    func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            guard event.clickCount == 1 else { return false }
            let flags = event.modifierFlags
            let additive = flags.contains(.shift) || flags.contains(.command)
                || flags.contains(.control)
            return begin(at: RightClickRouter.rootPoint(event), additive: additive)
        case .leftMouseDragged:
            guard isDragging else { return false }
            update(to: RightClickRouter.rootPoint(event))
            return true
        case .leftMouseUp:
            guard isDragging else { return false }
            end()
            return true
        default:
            return false
        }
    }
}

// MARK: - View plumbing

extension View {
    /// Marks the scrollable region of a pane as somewhere a band can be drawn.
    func marqueeZone(_ explorer: Explorer) -> some View {
        background(GeometryReader { geo in
            Color.clear
                .onAppear {
                    MarqueeController.shared.setZone(geo.frame(in: .named("root")), for: explorer)
                }
                .onChange(of: geo.frame(in: .named("root"))) { _, frame in
                    MarqueeController.shared.setZone(frame, for: explorer)
                }
        })
    }

    /// Reports this item's position so the band knows what it is crossing.
    func marqueeItem(_ id: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: ItemFrameKey.self,
                                   value: [id: geo.frame(in: .named("root"))])
        })
    }
}

/// The band itself, drawn over the window in root coordinates.
struct MarqueeOverlay: View {
    @ObservedObject var controller = MarqueeController.shared

    var body: some View {
        if let rect = controller.rect, rect.width > 1 || rect.height > 1 {
            Rectangle()
                .fill(Win.accent.opacity(0.20))
                .overlay(Rectangle().stroke(Win.accent.opacity(0.85), lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }
}
