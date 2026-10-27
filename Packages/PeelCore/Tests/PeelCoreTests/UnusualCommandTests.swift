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
            (["/Users/Shared/org.example.helper"], .runsFromTheSharedFolder),
            (["/private/var/folders/xy/abc123/T/org.example.helper"], .runsFromATemporaryFolder),
            (["/var/folders/xy/abc123/T/helper", "--daemon"], .runsFromATemporaryFolder),
            (["/private/var/folders/xy/abc123/C/org.example.app/helper"], nil),
            (["/bin/sh", "-c", "echo aGk= | base64 -d | sh"], .decodesBase64),
            (["/usr/bin/base64", "-D", "-i", "/Library/Example/payload"], .decodesBase64),
            (["/Applications/Example.app/Contents/MacOS/tool", "--encoding=base64"], nil),
            (["/usr/local/bin/convert", "/Users/me/notes-base64.txt", "--decode"], nil),
            (["/usr/bin/base64", "-i", "in.bin", "-o", "out.txt"], nil),
        ]
        for (arguments, expected) in cases {
            #expect(UnusualCommand(arguments: arguments) == expected, "\(arguments)")
        }
    }
}
