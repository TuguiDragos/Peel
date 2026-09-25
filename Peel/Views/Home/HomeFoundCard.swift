import PeelCore
import SwiftUI

/// Home's front door: a line for each tool that found something the last time it looked, leading to that tool.
/// It says what each one found and when, and never adds the tools together or selects anything.
struct HomeFoundCard: View {
    @Environment(FoundLastTimeStore.self) private var store
    @AppStorage(SettingsKey.hiddenTools) private var hiddenTools = ""
    @State private var pointingAt: Tool?

    var body: some View {
        let lines = lines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.tool) { index, line in
                    if index > 0 {
                        Perforation().padding(.leading, HomePermissionsContent.markSize + 12)
                    }
                    row(line.tool, sentence: line.sentence, date: line.date, tilt: index.isMultiple(of: 2) ? -3 : 3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .sticker(radius: 14)
            .overlay(alignment: .topLeading) {
                TapeHeader(title: Text("Found"), fill: Album.charcoal, ink: .white, angle: -HomePermissionsContent.tapeAngle)
                    .alignmentGuide(.top) { $0[.top] + $0.height / 2 }
                    .alignmentGuide(.leading) { $0[.leading] + $0.width / 4 }
            }
            // The tape is rotated, so it reaches above the card. The gap leaves room for it under the banner.
            .padding(.top, 42)
        }
    }

    /// A tool turned off in Settings is left out, as it is from the sidebar.
    private var lines: [(tool: Tool, sentence: AttributedString, date: Date)] {
        let hidden = Tool.hidden(in: hiddenTools)
        return store.findings.compactMap { tool, finding in
            guard !hidden.contains(tool), let sentence = tool.sentence(for: Looked(count: finding.count, size: finding.size)) else {
                return nil
            }
            return (tool, sentence, finding.date)
        }
    }

    private func row(_ tool: Tool, sentence: AttributedString, date: Date, tilt: Double) -> some View {
        let isPointedAt = pointingAt == tool
        let markBody = HomePermissionsContent.markBody
        return Button { Navigator.shared.requestedTool = tool } label: {
            HStack(spacing: 12) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Album.charcoal)
                    .frame(width: markBody, height: markBody)
                    .sticker(radius: markBody / 2, fill: Album.cream, edge: HomePermissionsContent.markEdge)
                    .rotationEffect(.degrees(tilt))
                    .frame(width: HomePermissionsContent.markSize, height: HomePermissionsContent.markSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(isPointedAt ? Album.orangeInk : Album.ink)
                        .underline(isPointedAt, pattern: .solid)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sentence)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(date, format: .relative(presentation: .named))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .motion(.touch, value: isPointedAt)
        .onHover { pointingAt = $0 ? tool : nil }
        .help(Text("Open \(String(localized: tool.title))"))
    }
}
