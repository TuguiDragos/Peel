import PeelCore
import SwiftUI

/// A detail pane's total, with a caption under it that says what it counts.
struct TotalLabel: View {
    let total: SizeTotal
    let caption: Text

    init(total: SizeTotal, caption: Text) {
        self.total = total
        self.caption = caption
    }

    init(bytes: Int64, caption: Text) {
        self.init(total: SizeTotal(known: bytes, isComplete: true), caption: caption)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(total.text)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(total.known)))
                .id(total.textKind)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            caption
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .motion(value: total)
    }
}
