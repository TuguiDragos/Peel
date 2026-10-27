import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

/// Behavior that changes in macOS 27. The file marks and paths these checks rely on are the same on macOS 26,
/// so they are checked on the current machine instead of waiting for the upgrade.
struct MacOS27Tests {
    /// From macOS 27, launchd does not run a job whose property list still carries a download's quarantine mark.
    @Test func noticesADownloadedLaunchdPlist() throws {
        let directory = try TemporaryDirectory()
        let plain = try directory.file("plain.plist", bytes: 16)
        let downloaded = try directory.file("downloaded.plist", bytes: 16)

        let marker = Process()
        marker.executableURL = URL(filePath: "/usr/bin/xattr")
        marker.arguments = ["-w", "com.apple.quarantine", "0081;00000000;Peel;", downloaded.path(percentEncoded: false)]
        try marker.run()
        marker.waitUntilExit()
        try #require(marker.terminationStatus == 0)

        #expect(Quarantine.marks(downloaded))
        #expect(!Quarantine.marks(plain))
        // Only where launchd refuses such a job: macOS 27 and later.
        if #available(macOS 27, *) {
            #expect(Quarantine.stopsLaunchd(downloaded))
        } else {
            #expect(!Quarantine.stopsLaunchd(downloaded))
        }
        #expect(!Quarantine.stopsLaunchd(plain))
    }

    /// macOS 26 still installs on Intel Macs, where Intel software runs natively.
    @Test func knowsWhatKindOfProcessorThisMacHas() {
        #expect(HostArchitecture.integer("hw.optional.peel.nonesuch") == nil)
        // Read from the machine running the test, under the same key `sysctl` prints.
        let arm64 = HostArchitecture.integer("hw.optional.arm64")
        #expect(HostArchitecture.isAppleSilicon == (arm64 == 1))
        #expect(arm64 == 1 || arm64 == nil || arm64 == 0)
    }

    /// macOS 27 does not reinstall Rosetta after an upgrade, so a Mac that ran Intel apps before may not anymore.
    @Test func knowsWhetherIntelSoftwareCanRunAtAll() async throws {
        #expect(!Rosetta.installed(among: ["/nowhere/rosetta"]))

        let directory = try TemporaryDirectory()
        let present = try directory.file("rosetta", bytes: 1).path(percentEncoded: false)
        #expect(Rosetta.installed(among: ["/nowhere/rosetta", present]))

        // Asked of macOS itself: on Apple silicon Intel code runs only through Rosetta, and an Intel Mac has none.
        guard HostArchitecture.isAppleSilicon else {
            #expect(!Rosetta.isInstalled)
            return
        }
        let answer = await Subprocess.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"], timeout: 60)
        guard case .success(let output) = answer else {
            Issue.record("arch didn't answer: \(answer)")
            return
        }
        #expect(Rosetta.isInstalled == (output.status == 0))
    }
}
