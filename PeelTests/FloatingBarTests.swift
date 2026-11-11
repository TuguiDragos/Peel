import AppKit
@testable import Peel
import PeelCore
import SwiftUI
import Testing

@MainActor
private final class Frames {
    var words = CGRect.zero
    var button = CGRect.zero
}

@MainActor
struct FloatingBarTests {
    private enum Reading {
        case selected, count, onPages, moved, lookedAt, moving, removing, waiting, puttingBack
    }

    @ViewBuilder private func words(_ reading: Reading) -> some View {
        let figure = Text(verbatim: "888.8 MB").font(.barFigure).monospacedDigit()
        switch reading {
        case .selected: figure; Text("Selected").foregroundStyle(.secondary)
        case .count: Text("^[\(888) item](inflect: true)").font(.barFigure); Text("Selected").foregroundStyle(.secondary)
        case .onPages:
            VStack(alignment: .leading, spacing: 0) {
                figure
                HStack(spacing: 4) {
                    Text("Selected on ^[\(12) page](inflect: true)")
                    Image(systemName: "chevron.up").font(.caption2.weight(.semibold))
                }
                .font(.subheadline)
            }
        case .moved: figure; Text("Moved").foregroundStyle(.secondary)
        case .lookedAt: ProgressView().controlSize(.small); Text("Looked at ^[\(1_234_567) item](inflect: true)")
        case .moving:
            ProgressView().controlSize(.small)
            Text("Moved \(12_345, format: .number) of \(67_890, format: .number)")
        case .removing:
            ProgressView().controlSize(.small)
            Text("Removed \(12_345, format: .number) of \(67_890, format: .number)")
        // An app's name can be any length, so a short one leaves what is measured to the sentence's own words.
        case .waiting: ProgressView().controlSize(.small); Text("Waiting for \("Xcode") to quit")
        case .puttingBack: ProgressView().controlSize(.small); Text("Putting back…")
        }
    }

    private func ideal(_ view: some View, in language: String) -> CGFloat {
        NSHostingView(rootView: view.environment(\.locale, Locale(identifier: language)).fixedSize()).fittingSize.width
    }

    private func button(_ title: LocalizedStringKey) -> some View {
        Button(title, systemImage: "trash") {}
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
    }

    private func symbolButton(_ title: LocalizedStringKey) -> some View {
        Button(title, systemImage: "trash") {}
            .labelStyle(.iconOnly)
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
    }

    /// What the bar gives its words and its button in a column `width` wide.
    private func laidOut(
        _ reading: Reading, beside title: LocalizedStringKey, width: CGFloat, in language: String
    ) async -> Frames {
        let frames = Frames()
        let bar = FloatingBar {
            HStack(spacing: 8) { words(reading) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.words = $0 }
        } action: {
            Button(title, systemImage: "trash") {}
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.button = $0 }
        }
        .environment(\.locale, Locale(identifier: language))
        .frame(width: width)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 200), styleMask: [.titled], backing: .buffered,
            defer: true
        )
        window.contentView = NSHostingView(rootView: bar)
        for _ in 0..<100 where frames.words.isEmpty || frames.button.isEmpty {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return frames
    }

    @Test func everyBarFitsTheNarrowestColumnItStandsInWithNothingCut() async {
        let detail: CGFloat = 480
        let bars: [(column: CGFloat, title: LocalizedStringKey, readings: [Reading])] = [
            (detail, "Move to Trash", [.selected, .onPages, .moved, .lookedAt, .moving, .waiting]),
            (ListColumn.width, "Move to Trash", [.selected, .onPages, .moved, .lookedAt, .moving, .waiting]),
            (detail, "Remove Downloads", [.selected, .lookedAt]),
            (detail, "Stop", [.removing]),
            (detail, "Put Back", [.count, .puttingBack]),
        ]
        var cut: [String] = []
        var needs: Set<Int> = []
        for language in Bundle.main.localizations where language != "Base" {
            for bar in bars {
                let whole = ideal(button(bar.title), in: language)
                let symbol = ideal(symbolButton(bar.title), in: language)
                for reading in bar.readings {
                    let needed = ideal(HStack(spacing: 8) { words(reading) }.lineLimit(1), in: language) * 0.8
                    needs.insert(Int(needed))
                    let given = await laidOut(reading, beside: bar.title, width: bar.column, in: language)
                    let button = given.button.width
                    if given.words.width < needed - 0.5 || button < whole - 0.5 && abs(button - symbol) > 0.5 {
                        cut.append("\(language) \(reading) in \(Int(bar.column)): words \(Int(given.words.width)) of "
                            + "\(Int(needed)), button \(Int(button)) of \(Int(whole))")
                    }
                }
            }
        }

        #expect(needs.count > 1, "every language measured alike, so the locale never reached the words")
        #expect(cut.isEmpty, "\(cut)")
    }

    @Test func aBarKeepsItsButtonsTitleWhereItFits() async {
        let given = await laidOut(.selected, beside: "Move to Trash", width: ListColumn.width, in: "en")

        #expect(abs(given.button.width - ideal(button("Move to Trash"), in: "en")) <= 0.5)
    }
}

