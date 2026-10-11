import PeelCore
import SwiftUI

/// A folder of the iCloud Drive page: its box selects the downloads in it Peel recommends, and the rest of the row
/// opens the folder to list them under it.
struct CloudFolderRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let folder: CloudFolder
    let rows: SelectableRows<URL>
    let isOpen: Bool
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
            Button {
                withAnimation(reduceMotion ? nil : Motion.step.animation) { toggleOpen() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: Self.chevronWidth)
                    AppIcon(url: folder.url)
                        .frame(width: 18, height: 18)
                        // Centers the icon on the first line of text, as a file's row does.
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                        .frame(width: 20)
                    // Finder's own separator between the folders of a path, the same in every language Peel speaks.
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
