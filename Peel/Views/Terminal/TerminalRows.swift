import PeelCore
import SwiftUI

struct TerminalSwitchRow: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let footnote: String
    var caption: LocalizedStringResource?
    let isOn: Binding<Bool>
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    InfoNote(name: String(localized: title), detail: Text(detail), footnote: Text(verbatim: footnote))
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Toggle(isOn: isOn) { EmptyView() }
                .labelsHidden()
                .accessibilityRepresentation {
                    Toggle(isOn: isOn) { Text(title) }
                }
                .disabled(isDisabled)
        }
        .padding(.vertical, 4)
    }
}

struct PromptSample: View {
    let style: PromptStyle
    let theme: TerminalTheme?
    let width: CGFloat
    var user = NSUserName()
    var host = PromptStyle.hostName()

    private static let systemColors: [Color] = [.black, .red, .green, .yellow, .blue, .purple, .cyan, .white]
    private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    private static func segments(of style: PromptStyle, user: String, host: String) -> [PromptStyle.Segment] {
        style.sample(user: user, host: host, path: "~/Projects/peel", branch: "main", failed: false)
    }

    static func width(of styles: [PromptStyle], user: String = NSUserName(), host: String = PromptStyle.hostName()) -> CGFloat {
        let lines = styles.flatMap { segments(of: $0, user: user, host: host).map(\.text).joined().split(separator: "\n") }
        return ceil(lines.map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0) + 16
    }

    var body: some View {
        Text(Self.segments(of: style, user: user, host: host).reduce(into: AttributedString()) { text, segment in
            var run = AttributedString(segment.text)
            run.foregroundColor = color(segment.color)
            text += run
        })
        .font(Font(Self.font))
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width, alignment: .leading)
        .background(theme.map { Color(terminal: $0.background) } ?? Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }
        .accessibilityHidden(true)
    }

    private func color(_ index: Int?) -> Color {
        guard let index else { return theme.map { Color(terminal: $0.text) } ?? .primary }
        if let theme, theme.ansi.indices.contains(index) {
            return Color(terminal: theme.ansi[index])
        }
        return Self.systemColors[index % 8]
    }
}
