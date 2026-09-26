import PeelCore
import SwiftUI

struct RemovalBar: View {
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(SelectionCarrier.self) private var carrier
    /// What the last removal moved while this bar was on screen, shown briefly in place of the selection.
    @State private var moved: RemovalBatch?
    /// What the question asks about: the parts as they were when Move to Trash was pressed.
    @State private var question: [CarriedSelection.Part] = []
    @State private var isAsking = false
    @State private var appToQuit = ""
    @State private var isAskingToQuit = false
    @State private var isShowingPages = false
    private let purpose: Purpose
    let isScanning: Bool
    /// The page's scan. Its count of items read is shown beside the spinner.
    var scan: ScanRun?
    /// The button's title. iCloud Drive passes its own, since freeing a local copy isn't moving it to the Trash.
    var title: LocalizedStringResource = "Move to Trash"
    var systemImage = "trash"
    /// A short message about what the page's own action just did, shown in place of the selection, for an
    /// action History doesn't record (freeing iCloud files, for example).
    var notice: BarNotice?

    private enum Purpose {
        /// What the page itself selected, which `onRemove` acts on.
        case own(SizeTotal, isEnabled: Bool, onRemove: () -> Void)
        /// A storage tool's page: the bar counts and moves what is selected there and on every such page seen
        /// before (`SelectionCarrier`). `message` goes under the question when only this page's selection moves.
        case carried(CarriedSelection.Page, message: Text?)
    }

    private struct Reading {
        let total: SizeTotal
        /// How many pages the selection is on, when one of them is not this page.
        let pages: Int?
        let isEnabled: Bool
        let remove: () -> Void
    }

    /// A bar for what the page itself selected. `isSelectionMeasured` is false when a selected item's size is
    /// unknown, so the total shown is only a lower bound ("Over X").
    init(
        selectedSize: Int64,
        isSelectionMeasured: Bool = true,
        isScanning: Bool,
        scan: ScanRun? = nil,
        isEnabled: Bool,
        onRemove: @escaping () -> Void,
        title: LocalizedStringResource = "Move to Trash",
        systemImage: String = "trash",
        notice: BarNotice? = nil
    ) {
        purpose = .own(SizeTotal(known: selectedSize, isComplete: isSelectionMeasured), isEnabled: isEnabled, onRemove: onRemove)
        self.isScanning = isScanning
        self.scan = scan
        self.title = title
        self.systemImage = systemImage
        self.notice = notice
    }

    /// A bar for a page of the storage tools, whose selection travels to the others' pages.
    init(page: CarriedSelection.Page, isScanning: Bool, scan: ScanRun? = nil, message: Text? = nil) {
        purpose = .carried(page, message: message)
        self.isScanning = isScanning
        self.scan = scan
    }

    private var page: CarriedSelection.Page? {
        if case .carried(let page, _) = purpose { page } else { nil }
    }

    private var reading: Reading {
        switch purpose {
        case .own(let total, let isEnabled, let onRemove):
            return Reading(total: total, pages: nil, isEnabled: isEnabled, remove: onRemove)
        case .carried(let page, _):
            let parts = carrier.parts(from: page)
            return Reading(
                total: parts.total,
                pages: parts.contains { $0.page != page } ? parts.count : nil,
                isEnabled: !parts.isEmpty && !carrier.isMoving && !isScanning,
                remove: { ask(about: parts) }
            )
        }
    }

    var body: some View {
        let reading = reading
        let isEnabled = reading.isEnabled && !exclusions.exclusions.isUnreadable
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
            } else if let pages = reading.pages, let page {
                // The pages go under the figure rather than beside it, so the capsule stays as wide as with the
                // selection of one page, which fits beside the button in every language at the narrowest column.
                Button {
                    isShowingPages = true
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        figure(reading.total)
                        HStack(spacing: 4) {
                            Text("Selected on ^[\(pages) page](inflect: true)")
                            Image(systemName: "chevron.up")
                                .font(.caption2.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingPages, arrowEdge: .top) {
                    CarriedPartsList(page: page)
                }
            } else {
                figure(reading.total)
                Text("Selected")
                    .foregroundStyle(.secondary)
            }
        } action: {
            Button(String(localized: title), systemImage: systemImage, action: reading.remove)
                .disabled(!isEnabled)
        }
        .focusedSceneValue(\.moveToTrash, MenuCommand(title: title, isEnabled: isEnabled, perform: reading.remove))
        .motion(value: reading.total)
        .motion(value: reading.pages)
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
        .task(id: page) {
            if let page { carrier.saw(page) }
        }
        .confirmationDialog(Text.movingToTrash(question.itemCount, question.total), isPresented: $isAsking) {
            Button("Move to Trash") {
                let parts = question
                Task { await carrier.move(parts) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            questionMessage
        }
        .alert("Quit \(appToQuit) before removing its files.", isPresented: $isAskingToQuit) {
            Button("OK", role: .cancel) {}
        }
    }

    private func figure(_ total: SizeTotal) -> some View {
        Text(total.text)
            .font(.barFigure)
            .monospacedDigit()
            // Given the value, the digits roll down when the total falls and up when it rises.
            .contentTransition(.numericText(value: Double(total.known)))
            .id(total.textKind)
    }

    /// Asks before moving anything, unless an open app keeps one of the parts: then nothing moves until it quits
    /// or its part is deselected.
    private func ask(about parts: [CarriedSelection.Part]) {
        if let app = carrier.appToQuit(among: parts) {
            appToQuit = app
            isAskingToQuit = true
        } else {
            question = parts
            isAsking = true
        }
    }

    /// Under the question: the page's own words when only its selection moves, and otherwise a line for each page.
    @ViewBuilder
    private var questionMessage: some View {
        if case .carried(let page, let message) = purpose, question.map(\.page) == [page] {
            message
        } else {
            Text(verbatim: question.map(line).joined(separator: "\n"))
        }
    }

    private func line(_ part: CarriedSelection.Part) -> String {
        let total = part.total
        if total.known == 0 {
            return String(inflecting: "\(part.title): ^[\(part.count) item](inflect: true)")
        }
        return total.isComplete
            ? String(inflecting: "\(part.title): ^[\(part.count) item](inflect: true), \(total.known.byteCount)")
            : String(inflecting: "\(part.title): ^[\(part.count) item](inflect: true), over \(total.known.byteCount)")
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
