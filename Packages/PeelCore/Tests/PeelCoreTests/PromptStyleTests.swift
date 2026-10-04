import Foundation
@testable import PeelCore
import Testing

struct PromptStyleTests {
    @Test func everyStyleShowsInZshAsItsSampleAfterACommandThatWorkedAndOneThatFailed() throws {
        let shell = try ZshHome()
        let project = shell.home.appending(path: "Projects/peel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let git = Process()
        git.executableURL = URL(filePath: "/usr/bin/git")
        git.arguments = ["init", "-q", "-b", "main", project.path]
        git.environment = shell.environment
        try git.run()
        git.waitUntilExit()
        #expect(git.terminationStatus == 0)
        for style in PromptStyle.allCases {
            #expect(ShellFile.write(.init(prompt: style), to: shell.peelFile))
            for failed in [false, true] {
                let shown = try shell.output(
                    of: "cd ~/Projects/peel; (( $+functions[vcs_info] )) && vcs_info; \(failed ? "false" : "true"); print -rnP -- \"${(e)PROMPT}\""
                )
                let sample = style.sample(
                    user: NSUserName(),
                    host: PromptStyle.hostName(),
                    path: "~/Projects/peel",
                    branch: "main",
                    failed: failed
                )
                #expect(Self.merged(Self.segments(in: shown)) == Self.merged(sample), "\(style), failed: \(failed), shown: \(shown.debugDescription)")
            }
        }
    }

    static func segments(in text: String) -> [PromptStyle.Segment] {
        var segments: [PromptStyle.Segment] = []
        var color: Int?
        var rest = Substring(text)
        while !rest.isEmpty {
            if rest.hasPrefix("\u{1B}["), let end = rest.firstIndex(of: "m") {
                let code = Int(rest[rest.index(rest.startIndex, offsetBy: 2)..<end]) ?? 0
                color = (30...37).contains(code) ? code - 30 : (90...97).contains(code) ? code - 82 : nil
                rest = rest[rest.index(after: end)...]
            } else {
                let next = rest.dropFirst().firstIndex(of: "\u{1B}") ?? rest.endIndex
                segments.append(PromptStyle.Segment(String(rest[..<next]), color))
                rest = rest[next...]
            }
        }
        return segments
    }

    static func merged(_ segments: [PromptStyle.Segment]) -> [PromptStyle.Segment] {
        segments.reduce(into: []) { result, segment in
            guard !segment.text.isEmpty else { return }
            if let last = result.last, last.color == segment.color {
                result[result.count - 1] = PromptStyle.Segment(last.text + segment.text, last.color)
            } else {
                result.append(segment)
            }
        }
    }
}
