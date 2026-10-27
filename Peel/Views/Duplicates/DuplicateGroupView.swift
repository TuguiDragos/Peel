import PeelCore
import QuickLook
import SwiftUI

struct DuplicateGroupView: View {
    @Environment(DuplicateLibrary.self) private var duplicates
    @State private var preview = QuickLookTarget()
    let group: DuplicateGroup

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

            Section {
                let staying = duplicates.staying(in: group)
                ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                    DuplicateFileRow(
                        duplicates: duplicates,
                        preview: preview,
                        file: file,
                        group: group,
                        isSelected: duplicates.isSelected(file),
                        canChangeSelection: duplicates.canChange(file, staying: staying),
                        isFirst: index == 0
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                heading("Copies", copiesNote)
            }
            .disabled(duplicates.isRemoving)
        }
        .scrollBarBelowSectionHeaders()
        .edgeBar(.bottom) {
            DuplicateRemovalBar()
        }
        .fadesInColumn(whenRowsChange: group.files.map(\.id))
        .navigationTitle(Text(verbatim: group.files[0].url.lastPathComponent))
        .toolbar(removing: .title)
        .quickLookPreview(Bindable(preview).url, in: group.files.map(\.url))
    }

    /// What the note beside Copies says, which follows what the group holds.
    private var copiesNote: LocalizedStringResource {
        if group.everyCopySyncs {
            "These copies sync to your other devices, so Peel lists them and never moves one: the Trash would take it from every device."
        } else if group.holdsASyncedCopy, group.holdsACopyWithWhatOthersLack {
            "Selected copies go to the Trash. A copy marked Stays syncs to your other devices, or has Finder tags, a Finder comment, or a resource fork the others don’t, and is never moved."
        } else if group.holdsASyncedCopy {
            "Selected copies go to the Trash. Peel always keeps at least one. A copy marked Stays syncs to your other devices and is never moved."
        } else if group.holdsACopyWithWhatOthersLack {
            "Selected copies go to the Trash. A copy marked Stays has Finder tags, a Finder comment, or a resource fork the others don’t, and is never moved."
        } else {
            "Selected copies go to the Trash. Peel always keeps at least one."
        }
    }

    private var header: some View {
        HStack(spacing: 20) {
            copies
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: group.files[0].url.lastPathComponent)
                    .pageTitle()
                    .help(Text(verbatim: group.files[0].url.lastPathComponent))
                FlowLayout(spacing: 6) {
                    Badge(title: Text(verbatim: group.size.byteCount), systemImage: "doc")
                    Badge(title: Text(group.files.count, format: .number), systemImage: "doc.on.doc")
                        .accessibilityLabel(Text("^[\(group.files.count) copy](inflect: true)"))
                    if sharesStorage {
                        NoteBadge(
                            title: Text("Shares storage"), systemImage: "link",
                            name: String(localized: "Shares storage"),
                            detail: Text("These copies share storage, so removing them frees less than their size.")
                        )
                            .help(Text("These copies share storage, so removing them frees less than their size."))
                    }
                }
            }
            Spacer(minLength: 8)
            // The selection's total, not the group's, so the figure changes as the user selects or deselects copies.
            DuplicateSelectedTotal(bytes: duplicates.selectedSize(in: group))
        }
        .padding(.vertical, 8)
    }

    /// Thumbnails of up to three copies, stacked with the first on top.
    private var copies: some View {
        ZStack {
            ForEach(Array(group.files.prefix(3).enumerated()).reversed(), id: \.offset) { index, file in
                FileThumbnail(url: file.url)
                    .frame(width: 62, height: 62)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .offset(x: [0, 8, -9][index], y: [0, -4, 5][index])
                .zIndex(Double(3 - index))
            }
        }
        .frame(width: 92, height: 80)
        .accessibilityHidden(true)
    }

    /// True when a copy other than the first, which Peel suggests keeping, shares its blocks with something else.
    /// This checks blocks, not sizes: a compressed or sparse file is smaller on disk without sharing anything.
    private var sharesStorage: Bool {
        group.files.dropFirst().contains { $0.sharesStorage }
    }
}

private struct DuplicateFileRow: View {
    let duplicates: DuplicateLibrary
    /// An object, as `duplicates` is, so the row compares equal from one change of the page to the next: a closure
    /// made in the page's body never would, and every row would be built again at every check (`RowSelection`).
    let preview: QuickLookTarget
    let file: DuplicateFile
    let group: DuplicateGroup
    let isSelected: Bool
    let canChangeSelection: Bool
    var isFirst = false

    var body: some View {
        // On the first text baseline, with each button centered on that line as the thumbnail is: centered on the
        // whole row, a button sat below the badge and the size beside it.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let heldBack = file.heldBack {
                // No checkbox: the copy can never be selected, and a disabled one would dim the very words the
                // person reads here, where the copy is. The mark of why it stays stands where the other rows'
                // checkbox stands, 16 points wide and 5 before the item, so the copies of a group line up.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: heldBack != .inTheCloud ? "tag" : file.syncSymbol)
                        .foregroundStyle(heldBack == .inTheCloud ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary))
                        .frame(width: 16, height: 16)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                        .accessibilityHidden(true)
                    item
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text(heldBack.explanation))
                .help(Text(heldBack.explanation))

                // Where the copy is matters more than a look at it: what is done with it is done in Finder or on
                // another device. The folder symbol, the menu's for Show in Finder, is close to the eye's width, so
                // the two buttons read as one column.
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .minimumTarget()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(Text("Show in Finder"))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
            } else {
                Toggle(isOn: Binding(get: { isSelected }, set: { duplicates.setSelected($0, file, in: group) })) {
                    item
                }
                .toggleStyle(.checkbox)
                .disabled(!canChangeSelection)
                .help(canChangeSelection ? Text(verbatim: file.url.path(percentEncoded: false)) : Text("Peel always keeps at least one copy."))

                Button {
                    preview.url = file.url
                } label: {
                    Label("Quick Look", systemImage: "eye")
                        .minimumTarget()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(Text("Quick Look"))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
            }
        }
        .tableRow(isFirst: isFirst)
        .contextMenu {
            Button("Quick Look", systemImage: "eye") { preview.url = file.url }
            ItemMenu(url: file.url)
        }
    }

    /// The thumbnail, the path with its date, the badge and the size, which every copy's row shows.
    private var item: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            FileThumbnail(url: file.url)
                .frame(width: 20, height: 20)
                .clipShape(.rect(cornerRadius: 4, style: .continuous))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.abbreviatedPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Modified \(file.modificationDate, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if file.heldBack != nil {
                Badge(title: Text("Stays"), systemImage: "hand.raised")
            } else if !isSelected {
                Badge(title: Text("Keep"), systemImage: "checkmark", tint: .green)
            }
            Text(file.size.byteCount)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// The copy Quick Look shows, held by the page.
@Observable
private final class QuickLookTarget {
    var url: URL?
}

/// A group's total to free, which follows the copies selected in it.
struct DuplicateSelectedTotal: View {
    let bytes: Int64

    var body: some View {
        TotalLabel(bytes: bytes, caption: Text("to free"))
            .accessibilityLabel(Text("\(bytes.byteCount) can be freed"))
    }
}

extension DuplicateFile {
    var syncSymbol: String {
        Self.syncSymbol(throughACloud: syncsThroughACloud)
    }

    /// The cloud for copies that sync through iCloud Drive or a cloud's File Provider, and arrows for those an app
    /// keeps in step, such as Syncthing, which go through no cloud.
    static func syncSymbol(throughACloud: Bool) -> String {
        throughACloud ? "icloud" : "arrow.triangle.2.circlepath"
    }
}
