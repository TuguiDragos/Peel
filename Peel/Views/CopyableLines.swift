import SwiftUI

struct CopyableLines: View {
    let caption: Text
    let lines: [String]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                caption
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: lines.joined(separator: "\n"))
                    .font(.subheadline.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            CopyButton(text: lines.joined(separator: "\n"))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
