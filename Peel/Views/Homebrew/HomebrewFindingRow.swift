import PeelCore
import SwiftUI

/// A row showing one thing `brew doctor` found.
///
/// The first line of Homebrew's text is the summary, and the lines after it, usually paths, are listed under
/// it. Then come Homebrew's advice and each command it suggests, with a Copy button beside each command.
struct HomebrewFindingRow: View {
    let finding: HomebrewFinding

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: summary)
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
                ForEach(Array(details.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let remedy {
                    Text(verbatim: remedy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
                ForEach(Array(finding.commands.enumerated()), id: \.offset) { _, command in
                    HStack(spacing: 8) {
                        Text(verbatim: command)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: .rect(cornerRadius: 6))
                        CopyButton(text: command)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var lines: [String] {
        finding.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var summary: String { lines.first ?? finding.text }

    private var details: [String] { Array(lines.dropFirst()) }

    /// Homebrew's advice without the backticks it puts around commands. The commands have rows of their own
    /// below, so the marks would only be clutter.
    private var remedy: String? {
        finding.remedy?.replacingOccurrences(of: "`", with: "")
    }
}
