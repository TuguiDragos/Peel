import PeelCore
import SwiftUI

/// The menu bar panel's list of what each tool found the last time it looked: a line per tool, in the sidebar's
/// order, that opens the tool. It never adds the tools together or selects anything. Applications is left out,
/// since the panel's own row counts its updates, and a tool turned off in Settings is left out, as in the sidebar.
struct MenuBarFound: View {
    @Environment(FoundLastTimeStore.self) private var store
    @AppStorage(SettingsKey.hiddenTools) private var hiddenTools = ""
    @State private var pointingAt: Tool?
    let open: (Tool) -> Void

    private struct Line {
        let tool: Tool
        let figure: String
        let sentence: AttributedString
        let date: Date
    }

    var body: some View {
        let lines = lines
        if !lines.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text("Found")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, MenuBarPanel.rowPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(lines.enumerated()), id: \.element.tool) { index, line in
                    if index > 0 {
                        Divider().padding(.leading, MenuBarPanel.wordsInset)
                    }
                    row(line)
                }
            }
            .padding(.bottom, 6)
        }
    }

    private var lines: [Line] {
        let hidden = Tool.hidden(in: hiddenTools)
        return store.findings.compactMap { tool, finding in
            let looked = Looked(count: finding.count, size: finding.size)
            guard
                tool != .applications,
                !hidden.contains(tool),
                let sentence = tool.sentence(for: looked),
                let figure = tool.figure(for: looked)
            else { return nil }
            return Line(tool: tool, figure: figure, sentence: sentence, date: finding.date)
        }
    }

    private func row(_ line: Line) -> some View {
        let isPointedAt = pointingAt == line.tool
        return Button { open(line.tool) } label: {
            HStack(spacing: MenuBarPanel.iconSpacing) {
                Image(systemName: line.tool.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(Album.orangeInk)
                    .frame(width: MenuBarPanel.iconWidth)
                // The figure sits beside the name while both fit whole, and under it otherwise, so neither is cut
                // and no word breaks.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        words(line).fixedSize()
                        Spacer(minLength: 0)
                        figure(line)
                    }
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            words(line).fixedSize(horizontal: false, vertical: true)
                            figure(line)
                        }
                        .padding(.vertical, 3)
                        Spacer(minLength: 0)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, MenuBarPanel.rowPadding)
            .padding(.vertical, 5)
            .frame(minHeight: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(isPointedAt ? Album.slot : .clear)
        .motion(.touch, value: isPointedAt)
        .onHover { pointingAt = $0 ? line.tool : (pointingAt == line.tool ? nil : pointingAt) }
        .onDisappear { if pointingAt == line.tool { pointingAt = nil } }
        .help(Text("Open \(String(localized: line.tool.title))"))
        .accessibilityLabel(Text(line.tool.title))
        .accessibilityValue(Text(
            "\(line.sentence) Found \(line.date, format: .relative(presentation: .named)).",
            comment: "What VoiceOver reads for a line of the menu bar panel's Found list. The first %@ is the tool's own sentence, such as \"3.2 GB in 5 groups.\", with its own full stop; the second is when the tool found it, as macOS words a relative time, such as \"2 hours ago\" or \"yesterday\"."
        ))
    }

    private func words(_ line: Line) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(line.tool.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(line.date, format: .relative(presentation: .named))
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private func figure(_ line: Line) -> some View {
        Text(verbatim: line.figure)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .fixedSize()
    }
}
