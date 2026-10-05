import Foundation
@testable import PeelCore
import Testing

struct PromptTests {
    @Test(arguments: Prompt.all)
    func everyPromptShowsInZshAsItsSampleAfterACommandThatWorkedAndOneThatFailed(prompt: Prompt) throws {
        let shell = try ZshHome()
        let project = shell.home.appending(path: "Projects/peel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        if prompt.showsBranch {
            let git = Process()
            git.executableURL = URL(filePath: "/usr/bin/git")
            git.arguments = ["init", "-q", "-b", "main", project.path]
            git.environment = shell.environment
            try git.run()
            git.waitUntilExit()
            #expect(git.terminationStatus == 0)
        }
        #expect(ShellFile.write(.init(prompt: prompt), to: shell.peelFile))
        let shown = try shell.output(
            of: "cd ~/Projects/peel; (( $+functions[vcs_info] )) && vcs_info; true; print -rnP -- \"${(e)PROMPT}\"; "
                + "print -n '|'; false; print -rnP -- \"${(e)PROMPT}\""
        )
        let parts = shown.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        #expect(parts.count == 2)
        for (part, failed) in zip(parts, [false, true]) {
            let sample = prompt.sample(
                user: NSUserName(),
                host: Prompt.hostName(),
                path: "~/Projects/peel",
                branch: "main",
                failed: failed
            )
            #expect(Self.merged(Self.segments(in: part)) == Self.merged(sample), "failed: \(failed), shown: \(part.debugDescription)")
        }
    }

    @Test func atHomeThePromptShowsATilde() throws {
        let shell = try ZshHome()
        for start in Prompt.Start.allCases {
            let prompt = Prompt(start: start, showsBranch: false)
            #expect(ShellFile.write(.init(prompt: prompt), to: shell.peelFile))
            let shown = try shell.output(of: "cd ~; print -rnP -- \"${(e)PROMPT}\"")
            let sample = prompt.sample(user: NSUserName(), host: Prompt.hostName(), path: "~", branch: nil, failed: false)
            #expect(Self.merged(Self.segments(in: shown)) == Self.merged(sample), "\(start)")
        }
    }

    @Test func aPromptTheStartupFileSetsAfterPeelsLineIsTheOneZshShows() throws {
        let peelsOwn = Prompt(start: .path, showsBranch: false, symbol: .dollar, turnsRedAfterAFailure: false)
        for (lines, setsItsOwn) in [
            (["PROMPT='mine> '"], true),
            (["export PS1='mine> '"], true),
            (["  typeset -g PROMPT='mine> '"], true),
            (["# PROMPT='mine> '"], false),
            (["alias ll='ls -l'"], false),
        ] {
            let shell = try ZshHome(thenRun: lines)
            #expect(ShellFile.write(.init(prompt: peelsOwn), to: shell.peelFile))
            let startup = shell.home.appending(path: ".zshrc")
            #expect(ShellFile.setsItsOwnPrompt(after: shell.peelFile, in: startup, home: shell.home) == setsItsOwn, "\(lines)")
            let shown = try shell.output(of: "print -rnP -- \"$PROMPT\"")
            #expect(shown.hasSuffix("mine> ") == setsItsOwn, "\(lines): \(shown.debugDescription)")
        }
        let before = try ZshHome()
        let startup = before.home.appending(path: ".zshrc")
        let line = ShellFile.line(sourcing: before.peelFile, home: before.home)
        try "PROMPT='mine> '\n\(line)\n".write(to: startup, atomically: true, encoding: .utf8)
        #expect(!ShellFile.setsItsOwnPrompt(after: before.peelFile, in: startup, home: before.home))
        try "PROMPT='mine> '\n".write(to: startup, atomically: true, encoding: .utf8)
        #expect(!ShellFile.setsItsOwnPrompt(after: before.peelFile, in: startup, home: before.home))
    }

    @Test func aBranchNeedsVcsInfoAndNothingElseNeedsAnything() async throws {
        let known = try #require(await ShellFile.knownToZsh())
        for prompt in Prompt.all {
            #expect(prompt.isKnown(by: known), "\(prompt)")
            #expect(prompt.isKnown(by: []) == !prompt.showsBranch, "\(prompt)")
        }
        #expect(!Prompt(showsBranch: true).isKnown(by: known.subtracting(["function:vcs_info"])))
    }

    static func segments(in text: String) -> [Prompt.Segment] {
        var segments: [Prompt.Segment] = []
        var color: Int?
        var rest = Substring(text)
        while !rest.isEmpty {
            if rest.hasPrefix("\u{1B}["), let end = rest.firstIndex(of: "m") {
                let code = Int(rest[rest.index(rest.startIndex, offsetBy: 2)..<end]) ?? 0
                color = (30...37).contains(code) ? code - 30 : (90...97).contains(code) ? code - 82 : nil
                rest = rest[rest.index(after: end)...]
            } else {
                let next = rest.dropFirst().firstIndex(of: "\u{1B}") ?? rest.endIndex
                segments.append(Prompt.Segment(String(rest[..<next]), color))
                rest = rest[next...]
            }
        }
        return segments
    }

    static func merged(_ segments: [Prompt.Segment]) -> [Prompt.Segment] {
        segments.reduce(into: []) { result, segment in
            guard !segment.text.isEmpty else { return }
            if let last = result.last, last.color == segment.color {
                result[result.count - 1] = Prompt.Segment(last.text + segment.text, last.color)
            } else {
                result.append(segment)
            }
        }
    }
}
