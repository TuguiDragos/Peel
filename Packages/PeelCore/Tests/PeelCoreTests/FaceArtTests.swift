import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

struct FaceArtTests {
    private let totals = RemovalTotals(
        bytes: SizeTotal(known: 2_350_000_000, isComplete: true), items: 60, apps: 1,
        biggest: SizeTotal(known: 0, isComplete: true)
    )

    @Test func everyDrawingGivesEachCharacterItsToneFromTheLargestDown() {
        #expect(FaceArt.drawings.map(\.width) == FaceArt.drawings.map(\.width).sorted(by: >))
        for drawing in FaceArt.drawings {
            #expect(drawing.characters.count == drawing.tones.count)
            for (characters, tones) in zip(drawing.characters, drawing.tones) {
                #expect(characters.count == tones.count)
                for (character, tone) in zip(characters, tones) {
                    #expect((character == " ") == (tone == " "))
                    #expect(tone == " " || FaceArt.colors[tone] != nil)
                }
            }
        }
    }

    @Test func plainIsASCIIThatFitsEightyColumns() {
        let text = FaceArt.text(colored: false, totals: totals, version: "1.3.0", build: "261104")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(text.unicodeScalars.allSatisfy { $0.isASCII })
        #expect(!text.contains("\u{1B}"))
        #expect(lines.allSatisfy { $0.count <= 80 })
        #expect(lines.contains { $0.hasSuffix("Peel 1.3.0 (261104)") })
        #expect(lines.contains { $0.hasSuffix("Moved to Trash  2.35 GB") })
        #expect(lines.contains { $0.hasSuffix("Apps removed    1") })
        #expect(lines.contains { $0.hasSuffix("Items moved     60") })
        #expect(lines.contains { $0.hasSuffix("Nothing left to peel.") })
        #expect(lines.prefix(FaceArt.large.characters.count).map { String($0.prefix(FaceArt.large.width)) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            == FaceArt.large.characters.map { $0.trimmingCharacters(in: .whitespaces) })
    }

    @Test func coloredDrawsTheSameTextInTheFacesColors() throws {
        let colored = FaceArt.text(colored: true, totals: totals, version: "1.3.0", build: "261104")
        let plain = FaceArt.text(colored: false, totals: totals, version: "1.3.0", build: "261104")
        let escapes = try Regex(#"\u{1B}\[[0-9;]*m"#)
        let shown = colored.replacing(escapes, with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        #expect(colored.contains("\u{1B}[38;2;255;153;51m"))
        #expect(colored.contains("\u{1B}[39m"))
        #expect(colored.contains("\u{1B}[48;2;255;153;51m"))
        #expect(shown.filter { !$0.isEmpty }
            == plain.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Which drawing the text holds, and whether its words stand beside it.
    private func drawn(columns: Int?, rows: Int?) -> (width: Int?, isBeside: Bool) {
        let lines = FaceArt.text(
            colored: false, totals: totals, version: "1.3.0", build: "261104", columns: columns, rows: rows
        ).split(separator: "\n").map(String.init)
        let drawing = FaceArt.drawings.first { drawing in
            let eyes = drawing.characters[drawing.characters.count / 2].trimmingCharacters(in: .whitespaces)
            return lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(eyes) }
        }
        let last = "Nothing left to peel."
        return (drawing?.width, lines.contains { $0.hasSuffix(last) && $0 != last })
    }

    @Test func theLargestFaceTheTerminalHasRoomForIsDrawnBesideItsWordsOrAboveThem() {
        let large = FaceArt.large.width, medium = FaceArt.medium.width, small = FaceArt.small.width
        #expect(drawn(columns: nil, rows: nil) == (large, true))
        #expect(drawn(columns: 80, rows: 24) == (large, true))
        #expect(drawn(columns: 60, rows: 24) == (medium, true))
        #expect(drawn(columns: 50, rows: 24) == (small, true))
        #expect(drawn(columns: 80, rows: 15) == (medium, true))
        #expect(drawn(columns: 80, rows: 11) == (small, true))
        #expect(drawn(columns: 44, rows: 24) == (medium, false))
        #expect(drawn(columns: 44, rows: 40) == (large, false))
        #expect(drawn(columns: 30, rows: 40) == (medium, false))
        #expect(drawn(columns: 20, rows: 40) == (small, false))
        #expect(drawn(columns: 17, rows: 40) == (nil, false))
    }

    @Test func colorsOnlyATerminalThatShowsThemAndNoColorTurnsThemOff() {
        let truecolor = ["COLORTERM": "truecolor"]
        #expect(FaceArt.drawsInColor(environment: truecolor, isTerminal: true))
        #expect(FaceArt.drawsInColor(environment: ["COLORTERM": "24bit"], isTerminal: true))
        #expect(!FaceArt.drawsInColor(environment: truecolor, isTerminal: false))
        #expect(!FaceArt.drawsInColor(environment: [:], isTerminal: true))
        #expect(!FaceArt.drawsInColor(environment: truecolor.merging(["NO_COLOR": "1"]) { $1 }, isTerminal: true))
        #expect(FaceArt.drawsInColor(environment: truecolor.merging(["NO_COLOR": ""]) { $1 }, isTerminal: true))
        #expect(!FaceArt.drawsInColor(environment: truecolor.merging(["TERM": "dumb"]) { $1 }, isTerminal: true))
    }

    @Test func nothingGoesPastTheTerminalAtAnySize() throws {
        let escapes = try Regex(#"\u{1B}\[[0-9;]*m"#)
        for colored in [false, true] {
            let words = FaceArt.text(colored: colored, totals: totals, version: "1.3.0", build: "261104", columns: 1)
                .replacing(escapes, with: "").split(separator: "\n", omittingEmptySubsequences: false).dropLast()
            let widest = words.map(\.count).max() ?? 0
            for rows in [nil, 6, 9, 12, 17, 24, 60] as [Int?] {
                for columns in 1...200 {
                    let lines = FaceArt.text(
                        colored: colored, totals: totals, version: "1.3.0", build: "261104",
                        columns: columns, rows: rows
                    ).replacing(escapes, with: "").split(separator: "\n", omittingEmptySubsequences: false).dropLast()
                    let size = "at \(columns) by \(rows.map(String.init) ?? "any")"
                    #expect(lines.allSatisfy { $0.count <= max(columns, widest) }, "\(size)")
                    #expect(lines.count <= max(rows ?? .max, words.count), "\(size)")
                    #expect(lines.contains { $0.hasSuffix("Nothing left to peel.") }, "\(size)")
                }
            }
        }
    }

    @Test func onlyPeelPeelIsTheGreeting() {
        #expect(PeelCommand.isGreeting(["peel"]))
        #expect(!PeelCommand.isGreeting([]))
        #expect(!PeelCommand.isGreeting(["peel", "--json"]))
        #expect(!PeelCommand.isGreeting(["apps"]))
    }
}
