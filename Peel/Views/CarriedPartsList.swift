import PeelCore
import SwiftUI

/// The pages a selection is on, each with what is selected there: a click on another page goes there, and the
/// button beside each deselects what is selected on it.
struct CarriedPartsList: View {
    @Environment(SelectionCarrier.self) private var carrier
    @Environment(\.dismiss) private var dismiss
    @State private var pointingAt: CarriedSelection.Page?
    /// The page the list was opened from.
    let page: CarriedSelection.Page

    var body: some View {
        // As tall as its rows up to the ceiling Duplicates' scan settings keep, and scrolling past it.
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
        }
        .frame(width: 340)
        .frame(maxHeight: 460)
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(carrier.parts(from: page)) { part in
                HStack(spacing: 6) {
                    if part.page == page {
                        label(part)
                    } else {
                        Button {
                            carrier.show(part.page)
                            dismiss()
                        } label: {
                            label(part)
                        }
                        .buttonStyle(.plain)
                        .background(.quaternary.opacity(pointingAt == part.page ? 1 : 0), in: .rect(cornerRadius: 6))
                        .pointerStyle(.link)
                        .onHover { pointingAt = $0 ? part.page : (pointingAt == part.page ? nil : pointingAt) }
                    }
                    Button {
                        carrier.deselect(part)
                    } label: {
                        Label("Deselect", systemImage: "xmark.circle.fill")
                            .minimumTarget()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(Text("Deselect"))
                }
            }
        }
        .padding(10)
    }

    private func label(_ part: CarriedSelection.Part) -> some View {
        HStack(spacing: 10) {
            if let tool = Tool(rawValue: part.page.tool) {
                Image(systemName: tool.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityLabel(Text(tool.title))
                    // A tool that is one page is already named by the part's title.
                    .accessibilityHidden(part.title == String(localized: tool.title))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: part.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("^[\(part.count) item](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(part.total.text)
                .rowFigure()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
