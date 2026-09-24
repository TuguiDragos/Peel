import PeelCore
import SwiftUI

struct RemovalBar: View {
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(RemovalHistoryStore.self) private var history
    /// What the last removal moved while this bar was on screen, shown briefly in place of the selection.
    @State private var moved: RemovalBatch?
    let selectedSize: Int64
    /// False when a selected item's size is unknown, so the total shown is only a lower bound ("Over X").
    var isSelectionMeasured = true
    let isScanning: Bool
    /// The page's scan. Its count of items read is shown beside the spinner.
    var scan: ScanRun?
    let isEnabled: Bool
    let onRemove: () -> Void
    /// The button's title. iCloud Drive passes its own, since freeing a local copy isn't moving it to the Trash.
    var title: LocalizedStringResource = "Move to Trash"
    var systemImage = "trash"
    /// A short message about what the page's own action just did, shown in place of the selection, for an
    /// action History doesn't record (freeing iCloud files, for example).
    var notice: BarNotice?

    private var total: SizeTotal {
        SizeTotal(known: selectedSize, isComplete: isSelectionMeasured)
    }

    var body: some View {
        FloatingBar {
            if let notice {
                Text(verbatim: notice.figure)
                    .font(.barFigure)
                    .monospacedDigit()
                Text(notice.words)
                    .foregroundStyle(.secondary)
            } else if let moved {
                Text(moved.size.known > 0 ? moved.size.text : String(inflecting: "^[\(moved.records.count) item](inflect: true)"))
                    .font(.barFigure)
                    .monospacedDigit()
                Text("Moved")
                    .foregroundStyle(.secondary)
            } else if isScanning {
                ProgressView()
                    .controlSize(.small)
                ReadSoFar(scan: scan)
                    .foregroundStyle(.secondary)
            } else {
                Text(total.text)
                    .font(.barFigure)
                    .monospacedDigit()
                    // Given the value, the digits roll down when the total falls and up when it rises.
                    .contentTransition(.numericText(value: Double(selectedSize)))
                    .id(total.textKind)
                Text("Selected")
                    .foregroundStyle(.secondary)
            }
        } action: {
            Button(String(localized: title), systemImage: systemImage, action: onRemove)
                .disabled(!isEnabled || exclusions.exclusions.isUnreadable)
        }
        .focusedSceneValue(\.moveToTrash, MenuCommand(title: title, isEnabled: isEnabled && !exclusions.exclusions.isUnreadable, perform: onRemove))
        .motion(value: selectedSize)
        .motion(value: isScanning)
        .motion(value: moved)
        .motion(value: notice)
        .onChange(of: history.justMoved) { _, batch in
            moved = batch
        }
        .task(id: moved) {
            guard moved != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            moved = nil
        }
    }
}

extension Font {
    /// The figure in a floating bar. It has a fixed size rather than a text style, since the bar is one line tall.
    static let barFigure = Font.system(size: 14, weight: .bold)
}

struct BarNotice: Equatable {
    let id = UUID()
    let figure: String
    let words: LocalizedStringResource
}

