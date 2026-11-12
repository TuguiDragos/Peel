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
            (["/bin/bash", "-e", "/Library/Scripts/backup.sh"], nil),
            (["/usr/bin/python3", "/opt/tool/run.py", "-c", "/etc/tool.conf"], nil),
            (["/usr/local/bin/node", "/opt/app/server.js", "-e", "production"], nil),
            (["/usr/bin/php", "-c", "/etc/php.ini", "/opt/app/cron.php"], nil),
            (["/usr/bin/perl", "-c", "/opt/app/check.pl"], nil),
            (["/bin/bash", "-lc", "echo hello"], .runsCodeFromItsSettings),
            (["/usr/bin/perl", "-ne", "print"], .runsCodeFromItsSettings),
            (["/usr/bin/php", "-r", "echo 1;"], .runsCodeFromItsSettings),
            (["/usr/local/bin/node", "--eval", "1"], .runsCodeFromItsSettings),
            (["/usr/local/bin/convert", "/Users/me/notes-base64.txt", "--decode"], nil),
            (["/usr/bin/base64", "-i", "in.bin", "-o", "out.txt"], nil),
        ]
        for (arguments, expected) in cases {
            #expect(UnusualCommand(arguments: arguments) == expected, "\(arguments)")
        }
    }

    @Test func anOptionsValueIsNeitherTheScriptNorMoreOptions() {
        let code: [[String]] = [
            ["/usr/bin/osascript", "-l", "JavaScript", "-e", "run()"],
            ["/usr/bin/osascript", "-lJavaScript", "-s", "o", "-e", "run()"],
            ["/bin/bash", "-o", "pipefail", "-c", "true"],
            ["/bin/bash", "-oc", "pipefail", "true"],
            ["/bin/bash", "--rcfile", "/dev/null", "-O", "extglob", "-c", "true"],
            ["/bin/sh", "+e", "-c", "true"],
            ["/bin/zsh", "-xoshwordsplit", "-c", "true"],
            ["/bin/zsh", "--emulate", "sh", "-fbc", "true"],
            ["/bin/zsh", "+-rcs", "-c", "true"],
            ["/bin/ksh", "-R", "/dev/null", "-c", "true"],
            ["/usr/local/bin/fish", "-d", "debug", "--command=true"],
            ["/usr/local/bin/fish", "-C", "true"],
            ["/usr/bin/python3", "-W", "ignore", "-Xfaulthandler", "-uc", "pass"],
            ["/usr/bin/perl", "-I", "lib", "-MFile::Basename", "-l012e", "1"],
            ["/usr/bin/perl", "-C", "-pi", "-e", "1"],
            ["/usr/bin/ruby", "-r", "set", "-Ilib", "-W0", "-e", "1"],
            ["/usr/local/bin/node", "-r", "os", "--title", "job", "-pe", "1"],
            ["/usr/local/bin/node", "--require=os", "--eval=1"],
            ["/usr/local/bin/php", "-d", "display_errors=1", "-R", "echo 1;"],
        ]
        let none: [[String]] = [
            ["/usr/bin/perl", "-MFile::Basename", "/opt/app/report.pl"],
            ["/usr/bin/perl", "-pie", "s/a/b/", "/opt/app/list.txt"],
            ["/usr/bin/perl", "-d:Trace", "/opt/app/report.pl"],
            ["/usr/bin/ruby", "-rset", "-Ilib/e", "/opt/app/report.rb"],
            ["/usr/bin/python3", "-Wonce", "/opt/app/report.py"],
            ["/usr/bin/python3", "-m", "http.server", "-c", "8000"],
            ["/usr/local/bin/php", "-dmemory_limit=-1", "/opt/app/cron.php"],
            ["/usr/local/bin/php", "-f", "/opt/app/cron.php", "--", "-r"],
            ["/bin/tcsh", "-Dcolor=1", "-b", "-c", "/opt/app/start.csh"],
            ["/bin/zsh", "-o", "errexit", "/opt/app/start.zsh", "-c"],
            ["/bin/bash", "-o", "-c", "/opt/app/start.sh"],
            ["/bin/bash", "--", "-c", "true"],
            ["/bin/zsh", "-f-", "-c", "true"],
            ["/usr/local/bin/node", "--trace-warnings", "/opt/app/server.js", "-e", "production"],
            ["/usr/bin/osascript", "-s", "e", "/opt/app/report.scpt"],
        ]
        for arguments in code {
            #expect(UnusualCommand(arguments: arguments) == .runsCodeFromItsSettings, "\(arguments)")
        }
        for arguments in none {
            #expect(UnusualCommand(arguments: arguments) == nil, "\(arguments)")
        }
    }
}
