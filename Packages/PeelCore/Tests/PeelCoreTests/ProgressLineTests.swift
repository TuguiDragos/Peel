import Darwin
import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

struct ProgressLineTests {
    private func spaces(_ count: Int) -> String {
        String(repeating: " ", count: count)
    }

    @Test func aTerminalIsShownHowFarTheScanHasGotAndTheLineGoesWhenItEnds() async throws {
        let terminal = try PseudoTerminal()

        await ProgressLine.reporting(on: terminal.replica) { show in
            show("Looked at 3 items")
            terminal.read(until: "Looked at 3 items")
        }

        #expect(terminal.everything() == "\rLooked at 3 items" + "\r" + spaces(17) + "\r")
    }

    @Test func aShorterLineCoversTheLongerOneBeforeIt() async throws {
        let terminal = try PseudoTerminal()

        await ProgressLine.reporting(on: terminal.replica) { show in
            show("Looking for files: 12345 found")
            terminal.read(until: "found")
            show("Comparing files: 1 of 2")
            terminal.read(until: "1 of 2")
        }

        let shorter = "\rComparing files: 1 of 2" + spaces(7)
        #expect(terminal.everything() == "\rLooking for files: 12345 found" + shorter + "\r" + spaces(23) + "\r")
    }

    @Test func theLineStaysShortOfTheTerminalsLastColumn() async throws {
        let terminal = try PseudoTerminal(columns: 20)

        await ProgressLine.reporting(on: terminal.replica) { show in
            show("Looked at 12345 items")
            terminal.read(until: "Looked at 12345 ite")
        }

        #expect(terminal.everything() == "\rLooked at 12345 ite" + "\r" + spaces(19) + "\r")
    }

    @Test func aScanSaysHowManyItemsItHasRead() async throws {
        let folder = try TemporaryDirectory()
        try folder.file("a")
        try folder.file("b/c")
        let terminal = try PseudoTerminal()

        await ProgressLine.counting(on: terminal.replica) {
            _ = await FileSize.contents(of: folder.url)
            terminal.read(until: "items")
        }

        #expect(terminal.everything() == "\rLooked at 3 items" + "\r" + spaces(17) + "\r")
    }

    @Test func aPipeOrAFileGetsNothing() async throws {
        let directory = try TemporaryDirectory()
        let file = open(directory.url.appending(path: "notes").path(percentEncoded: false), O_WRONLY | O_CREAT, 0o600)
        var ends: [Int32] = [0, 0]
        #expect(pipe(&ends) == 0)
        let terminal = try PseudoTerminal()

        // The terminal's line is drawn last of the three, so by then the others would have been too.
        await ProgressLine.reporting(on: ends[1]) { toThePipe in
            await ProgressLine.reporting(on: file) { toTheFile in
                await ProgressLine.reporting(on: terminal.replica) { toTheTerminal in
                    for show in [toThePipe, toTheFile, toTheTerminal] {
                        show("Looked at 3 items")
                    }
                    terminal.read(until: "Looked at 3 items")
                }
            }
        }

        close(ends[1])
        close(file)
        var buffer = [UInt8](repeating: 0, count: 64)
        #expect(read(ends[0], &buffer, buffer.count) == 0)
        close(ends[0])
        let written = try FileManager.default.attributesOfItem(atPath: directory.url.appending(path: "notes").path)
        #expect(written[.size] as? Int == 0)
        #expect(terminal.everything().hasPrefix("\rLooked at 3 items"))
    }

    @Test func countsReadAsTheAppSaysThem() {
        #expect(ProgressLine.lookedAt(0) == nil)
        #expect(ProgressLine.lookedAt(1) == "Looked at 1 item")
        #expect(ProgressLine.lookedAt(12_345) == "Looked at 12345 items")
    }

    @Test func duplicatesSayWhichStepTheyAreOn() {
        #expect(DuplicatesCommand.progress(.listing(foldersFound: 1_234)) == "Looking through folders: 1234 found")
        #expect(DuplicatesCommand.progress(.collecting(filesFound: 12_345)) == "Looking for files: 12345 found")
        #expect(DuplicatesCommand.progress(.comparing(filesCompared: 120, filesToCompare: 3_400)) == "Comparing files: 120 of 3400")
        #expect(
            DuplicatesCommand.progress(.verifying(bytesRead: 1_200_000_000, bytesToRead: 3_400_000_000))
                == "Reading contents: 1.2 GB of 3.4 GB"
        )
    }

    @Test func updatesSayHowManyAppsHaveBeenChecked() {
        #expect(UpdatesCommand.progress(checked: 12, of: 80) == "Checked 12 of 80 apps")
        #expect(UpdatesCommand.progress(checked: 1, of: 1) == "Checked 1 of 1 app")
    }
}
