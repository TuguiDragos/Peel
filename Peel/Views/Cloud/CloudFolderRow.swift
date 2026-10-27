import PeelCore
import SwiftUI

struct CloudFolderRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let folder: CloudFolder
    let rows: SelectableRows<URL>
    let isOpen: Bool
    /// True while the files' rows have a note column, whose place the folder's row keeps, so the sizes line up.
    var hasNoteColumn = false
    let isFirst: Bool
    let selection: any RowSelection
    let toggleOpen: () -> Void

    private static let chevronWidth: CGFloat = 12
    private static let spacing: CGFloat = 10
    /// How far a file sits in from its folder, so its icon lines up under the folder's.
    static let indent = chevronWidth + spacing

    var body: some View {
        let selected = selection.selectedURLs
        let group = rows.groupSelection(in: selected)
        HStack(alignment: .checkboxTitleLine, spacing: 5) {
            NativeCheckbox(
                // A click follows the folder's rule, whatever state AppKit moved the box to.
                isOn: Binding(
                    get: { group == .all },
                    set: { _ in selection.select(rows.clickingGroup(in: selection.selectedURLs)) }
                ),
                label: spoken,
                isMixed: group == .some
            )
            .disabled(rows.clickingGroup(in: selected) == selected)
            // Only the chevron is animated: rows a list inserts in an animation that shows or hides the scroll bar
            // leave AppKit's table wider than the list, and the section header with it.
            Button(action: toggleOpen) {
                HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .animation(reduceMotion ? nil : Motion.step.animation, value: isOpen)
                        .frame(width: Self.chevronWidth)
                    AppIcon(url: folder.url)
                        .frame(width: 18, height: 18)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                        .frame(width: 20)
                    // Finder's path separator, the same in every language Peel speaks.
                    Text(verbatim: folder.names.joined(separator: " ▸ "))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .checkboxTitleLine()
                    Text("^[\(folder.files.count) file](inflect: true)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(folder.size.byteCount)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: RowColumns.size, alignment: .trailing)
                }
                .padding(.trailing, hasNoteColumn ? RemovalRow.controlWidth + 6 : 0)
                .contentShape(.rect)
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityLabel(Text(verbatim: spoken))
            .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        }
        .tableRow(isFirst: isFirst)
    }

    private var spoken: String {
        let count = String(inflecting: "^[\(folder.files.count) file](inflect: true)")
        return (folder.names + [count, folder.size.byteCount]).joined(separator: ", ")
    }
}
