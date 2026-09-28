import Foundation
@testable import PeelCore
import Testing

struct UnusualCommandTests {
    /// A command is worth a second look for its shape, never for a name: what it runs, from where, and how.
    @Test func readsTheShapeOfAJobsCommand() {
        let cases: [([String], UnusualCommand?)] = [
            (["/usr/bin/curl", "-fsSL", "https://example.org/x.sh"], .downloads),
            (["/usr/local/bin/wget", "-q", "https://example.org/x"], .downloads),
            (["/bin/sh", "-c", "echo hello"], .runsCodeFromItsSettings),
            (["/usr/bin/osascript", "-e", "display dialog \"hi\""], .runsCodeFromItsSettings),
            (["/usr/bin/python3", "-c", "print(1)"], .runsCodeFromItsSettings),
            (["/private/tmp/org.example.helper", "--daemon"], .runsFromATemporaryFolder),
            (["/tmp/helper"], .runsFromATemporaryFolder),
            (["/bin/bash", "/Library/Scripts/run.sh", "base64", "--decode"], .decodesBase64),
            (["/Applications/Example.app/Contents/MacOS/Example", "--background"], nil),
            (["/bin/sh", "/Library/Application Support/Example/start.sh"], nil),
            (["/usr/bin/open", "-e", "/Users/Shared/notes.txt"], nil),
        ]
        for (arguments, expected) in cases {
            #expect(UnusualCommand(arguments: arguments) == expected, "\(arguments)")
        }
    }
}
