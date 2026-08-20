import SwiftUI
import AppKit

// MARK: - The rename rule

struct RenamePlan {
    enum CaseMode: String, CaseIterable { case unchanged = "Unchanged", lower = "lowercase",
                                          upper = "UPPERCASE", title = "Title Case" }

    var find = ""
    var replace = ""
    var caseSensitive = false
    var prefix = ""
    var suffix = ""
    var numbering = false
    var startAt = 1
    var digits = 2
    var caseMode: CaseMode = .unchanged
    var newExtension = ""

    /// Applies the rule to one name. `index` is the item's position in the list.
    func apply(to name: String, index: Int) -> String {
        let ns = name as NSString
        var stem = ns.deletingPathExtension
        var ext = ns.pathExtension

        if !find.isEmpty {
            stem = stem.replacingOccurrences(
                of: find, with: replace,
                options: caseSensitive ? [] : [.caseInsensitive])
        }

        switch caseMode {
        case .unchanged: break
        case .lower: stem = stem.lowercased()
        case .upper: stem = stem.uppercased()
        case .title: stem = stem.capitalized
        }

        stem = prefix + stem + suffix

        if numbering {
            let number = startAt + index
            stem += String(format: "%0\(max(1, digits))d", number)
        }

        if !newExtension.isEmpty {
            ext = newExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }

        if stem.isEmpty { stem = "unnamed" }
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }
}

// MARK: - Dialog

struct BatchRenameDialog: View {
    @ObservedObject var ex: Explorer
    let items: [FileItem]
    var maxHeight: CGFloat = 340
    let onClose: () -> Void

    @State private var plan = RenamePlan()

    private var results: [(item: FileItem, newName: String)] {
        items.enumerated().map { ($0.element, plan.apply(to: $0.element.name, index: $0.offset)) }
    }

    /// Two items renamed to the same thing, or onto a file that already exists.
    private var conflicts: Set<String> {
        var seen: [String: Int] = [:]
        var bad = Set<String>()
        let fm = FileManager.default
        for (item, newName) in results {
            seen[newName.lowercased(), default: 0] += 1
            if seen[newName.lowercased()]! > 1 { bad.insert(newName) }
            let target = item.url.deletingLastPathComponent().appendingPathComponent(newName)
            if newName != item.name && fm.fileExists(atPath: target.path) { bad.insert(newName) }
        }
        return bad
    }

    private var changedCount: Int {
        results.filter { $0.newName != $0.item.name }.count
    }

    var body: some View {
        WinDialog(title: "Rename \(items.count) items", width: 620, onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                rules
                Divider().overlay(Win.divider)
                preview
            }
        } footer: {
            if !conflicts.isEmpty {
                Text("\(conflicts.count) name\(conflicts.count == 1 ? "" : "s") would clash")
                    .font(Win.body(11)).foregroundStyle(Win.danger)
                Spacer()
            }
            WinDialogButton(title: "Rename", primary: true,
                            enabled: changedCount > 0 && conflicts.isEmpty) {
                apply()
            }
            WinDialogButton(title: "Cancel", action: onClose)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LabelledField(label: "Find", text: $plan.find, width: 170)
                LabelledField(label: "Replace with", text: $plan.replace, width: 170)
                HStack(spacing: 7) {
                    WinCheckbox(checked: plan.caseSensitive) { plan.caseSensitive.toggle() }
                    Text("Match case").font(Win.body(11)).foregroundStyle(Win.textSecondary)
                }
                .padding(.top, 14)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                LabelledField(label: "Prefix", text: $plan.prefix, width: 130)
                LabelledField(label: "Suffix", text: $plan.suffix, width: 130)
                LabelledField(label: "New extension", text: $plan.newExtension, width: 110)
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                HStack(spacing: 7) {
                    WinCheckbox(checked: plan.numbering) { plan.numbering.toggle() }
                    Text("Number them").font(Win.body(12)).foregroundStyle(Win.text)
                }
                if plan.numbering {
                    Stepper("Start at \(plan.startAt)", value: $plan.startAt, in: 0...9999)
                        .font(Win.body(11)).foregroundStyle(Win.textSecondary)
                    Stepper("\(plan.digits) digits", value: $plan.digits, in: 1...6)
                        .font(Win.body(11)).foregroundStyle(Win.textSecondary)
                }
                Spacer(minLength: 0)
                WinSegmented(options: RenamePlan.CaseMode.allCases.map { ($0.rawValue, $0) },
                             selection: $plan.caseMode)
            }
        }
        .padding(16)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Preview").font(Win.body(11, weight: .semibold))
                    .foregroundStyle(Win.textSecondary)
                Spacer()
                Text("\(changedCount) of \(items.count) will change")
                    .font(Win.body(11)).foregroundStyle(Win.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 10) {
                            ItemIcon(item: row.item, size: 16)
                            Text(row.item.name)
                                .font(Win.body(12)).foregroundStyle(Win.textSecondary)
                                .lineLimit(1).frame(width: 220, alignment: .leading)
                            Glyph(icon: .forward, size: 12, color: Win.textTertiary, weight: 1.2)
                            Text(row.newName)
                                .font(Win.body(12))
                                .foregroundStyle(conflicts.contains(row.newName) ? Win.danger
                                                 : (row.newName == row.item.name ? Win.textTertiary : Win.text))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 26)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(height: min(220, maxHeight - 150))
        }
    }

    private func apply() {
        var renames: [(from: URL, to: URL)] = []
        for (item, newName) in results where newName != item.name {
            let target = item.url.deletingLastPathComponent().appendingPathComponent(newName)
            do {
                try FileManager.default.moveItem(at: item.url, to: target)
                renames.append((item.url, target))
            } catch {
                ex.sheet = .error("Could not rename “\(item.name)”. \(error.localizedDescription)")
                return
            }
        }
        ex.recordBatchRename(renames)
        onClose()
        ex.reload()
    }
}

struct LabelledField: View {
    let label: String
    @Binding var text: String
    var width: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Win.body(11)).foregroundStyle(Win.textTertiary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Win.body(12))
                .foregroundStyle(Win.text)
                .padding(.horizontal, 8)
                .frame(width: width, height: 26)
                .background(WinRR(radius: 4).fill(Win.field))
                .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
        }
    }
}
