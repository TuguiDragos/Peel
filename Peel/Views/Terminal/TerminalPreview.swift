import PeelCore
import SwiftUI

extension Color {
    init(terminal color: UInt32) {
        self.init(.sRGB, red: Double(color >> 16 & 0xFF) / 255, green: Double(color >> 8 & 0xFF) / 255, blue: Double(color & 0xFF) / 255)
    }
}

struct TerminalSession: View {
    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            line(prompt("ls"))
            line(run("Peel/", 4) + run("  ") + run("PeelCLI/", 4) + run("  README.md  ") + run("build.sh*", 2))
            line(prompt("git status -s"))
            line(run(" M", 1) + run(" ContentView.swift"))
            line(run("??", 1) + run(" notes.md"))
            line(prompt("swift test"))
            line(run("✓", 2) + run(" 1549 tests passed ") + run("(17 s)", 8))
            line(run("⚠", 3) + run(" 2 warnings"))
            line(run("✗ 1 failure", 1) + run(":", 8) + run(" ThemeTests"))
            swatches(0..<8)
                .padding(.top, 4)
            swatches(8..<16)
            HStack(spacing: 0) {
                line(prompt(""))
                Rectangle()
                    .fill(Color(terminal: theme.cursor))
                    .frame(width: 7, height: 13)
            }
            .padding(.top, 4)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(terminal: theme.background), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .accessibilityHidden(true)
    }

    private func line(_ text: AttributedString) -> some View {
        Text(text)
            .lineLimit(1)
            .fixedSize()
    }

    private func run(_ text: String, _ slot: Int? = nil) -> AttributedString {
        var run = AttributedString(text)
        run.foregroundColor = Color(terminal: slot.map { theme.ansi[$0] } ?? theme.text)
        return run
    }

    private func prompt(_ command: String) -> AttributedString {
        run("~/Projects/peel", 6) + run(" main", 3) + run(" ❯ ", 2) + run(command)
    }

    private func swatches(_ slots: Range<Int>) -> some View {
        HStack(spacing: 3) {
            ForEach(slots, id: \.self) { slot in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(terminal: theme.ansi[slot]))
                    .frame(width: 18, height: 9)
            }
        }
    }
}

struct TerminalThemeCard: View {
    let theme: TerminalTheme
    let isInUse: Bool

    var body: some View {
        VStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 5) {
                bars([(6, 34), (3, 14), (2, 8)])
                bars([(4, 22), (nil, 40)])
                bars([(1, 12), (8, 30)])
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach([1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14], id: \.self) { slot in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(terminal: theme.ansi[slot]))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .topLeading)
            .background(Color(terminal: theme.background), in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
            .overlay {
                if isInUse {
                    RoundedRectangle(cornerRadius: 11)
                        .inset(by: -3)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            Text(verbatim: theme.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contentShape(.rect)
    }

    private func bars(_ parts: [(slot: Int?, width: CGFloat)]) -> some View {
        HStack(spacing: 3) {
            ForEach(parts.indices, id: \.self) { index in
                Capsule()
                    .fill(Color(terminal: parts[index].slot.map { theme.ansi[$0] } ?? theme.text))
                    .frame(width: parts[index].width, height: 4)
            }
        }
    }
}
