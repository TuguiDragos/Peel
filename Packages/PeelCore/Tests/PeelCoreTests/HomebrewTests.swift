import Foundation
import Synchronization
@testable import PeelCore
import Testing

struct HomebrewTests {
    /// `man brew`: unless `HOMEBREW_NO_INSTALL_CLEANUP` is set, `brew upgrade` runs `brew cleanup` by itself, for
    /// the upgraded packages and every 30 days for all of them, which deletes old versions and downloads for good.
    /// Peel deletes those only through Clean Up, which asks first, so no call it makes may clean up on its own.
    @Test func anUpgradeNeverCleansUpOnItsOwn() {
        for autoUpdate in [true, false] {
            #expect(Homebrew.environment(autoUpdate: autoUpdate)["HOMEBREW_NO_INSTALL_CLEANUP"] == "1")
        }
    }

    /// Formulae and casks are upgraded in two calls, and the second is made even when the first never finished,
    /// as when it ran out of time: the casks were otherwise never tried, and the report left them out.
    @Test func upgradesTheCasksEvenWhenTheFormulaeNeverFinished() async {
        let packages = [HomebrewPackage(name: "wget", kind: .formula, installedVersion: "1.0"), HomebrewPackage(name: "firefox", kind: .cask, installedVersion: "1.0")]
        let asked = Mutex<[String]>([])

        do {
            _ = try await Homebrew.upgrade(packages) { arguments throws(Homebrew.CommandFailure) in
                asked.withLock { $0.append(arguments[1]) }
                guard arguments[1] == "--cask" else { throw Homebrew.CommandFailure(output: "The formulae ran out of time.") }
                return Homebrew.Attempt(status: 0, standardOutput: "firefox was upgraded.\n", standardError: "")
            }
            Issue.record("a batch that never finished read as a success")
        } catch {
            #expect(error.output == "The formulae ran out of time.\nfirefox was upgraded.\n")
        }
        #expect(asked.withLock { $0 } == ["--formula", "--cask"])
    }

    /// Homebrew writes warnings to stderr and still exits 0, for example for a formula from a tap that uses a
    /// deprecated method. So the answer is read from stdout alone: JSON with a warning after it is not JSON.
    @Test func readsAnAnswerFromWhatWasPrintedAsTheAnswer() throws {
        let json = #"{"formulae": [], "casks": [{"token": "sample", "installed": "2.1.0", "version": "2.1.0", "outdated": false}]}"#
        let warned = Homebrew.Attempt(status: 0, standardOutput: json, standardError: "Warning: Calling plist_options is deprecated!\n")

        #expect(try Homebrew.parseInstalled(Data(warned.answer().utf8))?.map(\.name) == ["sample"])
        #expect(try warned.transcript().hasSuffix("is deprecated!\n"), "what the user is shown keeps the warning")

        let failed = Homebrew.Attempt(status: 1, standardOutput: "", standardError: "Error: No such keg\n")
        #expect(throws: Homebrew.CommandFailure.self) { try failed.answer() }
        #expect(throws: Homebrew.CommandFailure.self) { try failed.transcript() }
    }

    @Test func parsesInstalledFormulaeAndCasks() throws {
        let json = """
        {
          "formulae": [
            {"name": "openssl@3", "desc": "Cryptography and SSL/TLS Toolkit", "homepage": "https://openssl-library.org",
             "installed": [{"version": "3.5.2", "installed_on_request": false}], "versions": {"stable": "3.5.3"}, "revision": 2,
             "outdated": true, "pinned": false, "dependencies": ["ca-certificates"]},
            {"name": "bat", "full_name": "sharkdp/tap/bat", "desc": "Clone of cat(1)", "homepage": "https://github.com/sharkdp/bat",
             "installed": [{"version": "0.26.1", "installed_on_request": true}], "versions": {"stable": "0.26.1"},
             "outdated": false, "pinned": true, "dependencies": ["libgit2", "oniguruma"]}
          ],
          "casks": [
            {"token": "sample", "desc": "A sample app", "homepage": "https://example.org/sample",
             "installed": "2.1.0", "version": "2.1.0", "outdated": false}
          ]
        }
        """
        let packages = try #require(Homebrew.parseInstalled(Data(json.utf8)))

        #expect(packages.map(\.id) == ["formula/bat", "formula/openssl@3", "cask/sample"])
        let openssl = try #require(packages.first { $0.name == "openssl@3" })
        #expect(openssl.isOutdated)
        #expect(openssl.installedVersion == "3.5.2")
        // The revision is part of the version Homebrew installs. Without it, an installed `1.11.1_4` would look
        // newer than the latest `1.11.1`.
        #expect(openssl.latestVersion == "3.5.3_2")
        #expect(packages.first { $0.name == "bat" }?.latestVersion == "0.26.1")
        #expect(!openssl.isInstalledOnRequest)
        #expect(openssl.dependencies == ["ca-certificates"])
        #expect(packages.first { $0.name == "bat" }?.isPinned == true)
        #expect(packages.first { $0.name == "bat" }?.fullName == "sharkdp/tap/bat")
        #expect(openssl.fullName == "openssl@3", "an older Homebrew says no full name, and the short one stands in")
        #expect(packages.last?.kind == .cask)
        #expect(packages.last?.installedVersion == "2.1.0")
    }

    /// Homebrew pins a cask as it pins a formula (`brew pin --cask`, since 6.0.0), and says so in the cask's JSON, as
    /// 7.0.4 writes it. A pinned cask is left out of Upgrade All, since `brew upgrade` refuses to upgrade it.
    @Test func readsAPinnedCask() throws {
        let json = """
        {
          "formulae": [],
          "casks": [
            {"token": "sample", "installed": "2.1.0", "version": "2.2.0", "outdated": true, "pinned": true, "pinned_version": "2.1.0"},
            {"token": "other", "installed": "1.0", "version": "1.1", "outdated": true, "pinned": false, "pinned_version": null}
          ]
        }
        """
        let packages = try #require(Homebrew.parseInstalled(Data(json.utf8)))

        #expect(packages.first { $0.name == "sample" }?.isPinned == true)
        #expect(packages.first { $0.name == "other" }?.isPinned == false)
    }

    /// Homebrew runs some steps of a cask as root with `sudo`, which asks for a password only a terminal can give
    /// (`cask/artifact/pkg.rb` and `abstract_uninstall.rb`, 7.0.4). The artifacts are written as `brew info
    /// --json=v2` writes Zoom's, Adobe AIR's, and a plain app's.
    @Test func knowsWhichCasksNeedAnAdministrator() throws {
        let json = """
        {
          "formulae": [],
          "casks": [
            {"token": "meeting", "installed": "6.0", "version": "6.1", "outdated": true, "artifacts": [
              {"uninstall": [{"launchctl": ["org.example.meeting.updater"], "pkgutil": "org.example.meeting.pkg",
                              "delete": ["/Library/Internet Plug-Ins/Meeting.plugin"]}]},
              {"pkg": ["MeetingInstaller.pkg"]}]},
            {"token": "runtime", "installed": "51.1", "version": "51.2", "outdated": true, "artifacts": [
              {"uninstall": [{"script": {"executable": "Runtime Installer.app/Contents/MacOS/Runtime Installer",
                                         "args": ["-uninstall"], "sudo": true}, "rmdir": ["/Applications/Runtime"]}]},
              {"installer": [{"script": {"executable": "Runtime Installer.app/Contents/MacOS/Runtime Installer",
                                         "args": ["-silent"], "sudo": true}}]}]},
            {"token": "player", "installed": "3.0", "version": "3.0", "outdated": false, "artifacts": [
              {"app": ["Player.app"]},
              {"uninstall": [{"launchctl": "org.example.player.helper", "quit": "org.example.player"}]},
              {"zap": [{"trash": ["~/Library/Application Support/Player"], "delete": "/Library/Player"}]}]},
            {"token": "helper", "installed": "1.0", "version": "1.1", "outdated": true, "artifacts": [
              {"installer": [{"script": {"executable": "Install Helper", "sudo": false}}]},
              {"uninstall": [{"kext": "org.example.helper.driver"}]}]}
          ]
        }
        """
        let packages = try #require(Homebrew.parseInstalled(Data(json.utf8)))
        let needs = { (name: String) in
            packages.first { $0.name == name }.map { [$0.upgradeNeedsAnAdministrator, $0.uninstallNeedsAnAdministrator] }
        }

        #expect(needs("meeting") == [true, true], "an installer package and `pkgutil` both run with sudo")
        #expect(needs("runtime") == [true, true], "scripts run with sudo")
        #expect(needs("player") == [false, false], "launchctl goes on without sudo, and zap is not what uninstalling runs")
        #expect(needs("helper") == [true, true], "a kernel extension is unloaded with sudo, when upgrading too")
    }

    /// The JSON follows what Homebrew 7.0.4 reports for packages it has stopped or will stop offering. A package
    /// can be deprecated and disabled at once (disabled wins), a deprecated one carries the day it will be
    /// disabled, and a reason is one of Homebrew's keywords or a sentence a maintainer wrote.
    @Test func readsWhatHomebrewNoLongerOffers() throws {
        let json = """
        {
          "formulae": [
            {"name": "aces_container", "installed": [{"version": "1.0.2"}], "versions": {"stable": "1.0.2"},
             "deprecated": true, "deprecation_date": "2026-06-05", "deprecation_reason": "repo_archived",
             "deprecation_replacement_formula": "openimageio", "disabled": false, "disable_date": "2027-06-05"},
            {"name": "aescrypt-packetizer", "installed": [{"version": "3.16"}], "versions": {"stable": "3.16"},
             "deprecated": true, "deprecation_date": "2025-03-17", "deprecation_reason": "switched to a commercial license in v4",
             "disabled": true, "disable_date": "2026-03-17", "disable_reason": "switched to a commercial license in v4"},
            {"name": "abricate", "installed": [{"version": "1.0.1"}], "versions": {"stable": "1.0.1"},
             "deprecated": false, "deprecation_date": "2027-03-31", "disabled": false}
          ],
          "casks": [
            {"token": "1kc-razer", "installed": "1.0", "version": "1.0",
             "deprecated": false, "disabled": true, "disable_date": "2026-09-01", "disable_reason": "fails_gatekeeper_check",
             "disable_replacement_cask": "razer-synapse"},
            {"token": "active-trader-pro", "installed": "2.0", "version": "2.0",
             "deprecated": true, "deprecation_date": "2025-12-17", "deprecation_reason": "discontinued", "disabled": false,
             "disable_date": "2026-12-17"},
            {"token": "sample", "installed": "2.1.0", "version": "2.1.0"}
          ]
        }
        """
        let packages = try #require(Homebrew.parseInstalled(Data(json.utf8)))
        func retirement(_ name: String) -> HomebrewRetirement? { packages.first { $0.name == name }?.retirement }
        func day(_ text: String) -> Date { try! Date(text, strategy: .iso8601.year().month().day()) }

        #expect(retirement("aces_container") == HomebrewRetirement(stage: .deprecated, reason: .repositoryArchived, disableDate: day("2027-06-05"), replacement: .formula("openimageio")))
        #expect(retirement("aescrypt-packetizer") == HomebrewRetirement(stage: .disabled, reason: .written("switched to a commercial license in v4"), disableDate: day("2026-03-17"), replacement: nil))
        #expect(retirement("1kc-razer") == HomebrewRetirement(stage: .disabled, reason: .failsGatekeeperCheck, disableDate: day("2026-09-01"), replacement: .cask("razer-synapse")))
        #expect(retirement("active-trader-pro") == HomebrewRetirement(stage: .deprecated, reason: .discontinued, disableDate: day("2026-12-17"), replacement: nil))
        #expect(retirement("abricate") == nil, "a deprecation dated ahead has not happened yet")
        #expect(retirement("sample") == nil)
    }

    /// Every reason keyword Homebrew 7.0.4 declares in `deprecate_disable.rb` is recognized, and any other text
    /// is kept as written.
    @Test func knowsEveryReasonHomebrewNames() {
        let words = [
            "discontinued", "moved_to_mas", "no_longer_available", "no_longer_meets_criteria", "unmaintained",
            "fails_gatekeeper_check", "unreachable", "does_not_build", "no_license", "repo_archived", "repo_removed",
            "unsupported", "deprecated_upstream", "versioned_formula", "checksum_mismatch",
        ]
        let reasons = words.map(HomebrewRetirement.Reason.init)
        #expect(Set(reasons).count == words.count)
        #expect(!reasons.contains { if case .written = $0 { true } else { false } })
        #expect(HomebrewRetirement.Reason("needs deprecated `blast`") == .written("needs deprecated `blast`"))
    }

    @Test func rejectsUnexpectedOutput() {
        #expect(Homebrew.parseInstalled(Data("Error: Unknown command".utf8)) == nil)
    }

    @Test func readsTheVersionAReleasedHomebrewReports() {
        let installation = HomebrewInstallation(version: "7.0.4", prefix: URL(filePath: "/opt/homebrew"))

        #expect(installation.reportsHealthAsJSON)
        #expect(installation.checksVulnerabilities)
    }

    /// A Homebrew installed from git reports how far past the tag it is, which is not part of the version.
    @Test func readsTheVersionACheckedOutHomebrewReports() {
        let installation = HomebrewInstallation(version: "7.0.4-2-g4ad6fe9", prefix: URL(filePath: "/opt/homebrew"))

        #expect(installation.reportsHealthAsJSON)
        #expect(installation.checksVulnerabilities)
    }

    /// `brew doctor --json` arrived in 6.0.12 but left out every check that still answered in prose, so it could
    /// print `[]` for a broken installation. From 6.0.13 every check is included.
    @Test func keepsJSONDiagnosticsForTheVersionThatMadeThemWhole() {
        #expect(!HomebrewInstallation(version: "6.0.12", prefix: URL(filePath: "/opt/homebrew")).reportsHealthAsJSON)
        #expect(HomebrewInstallation(version: "6.0.13", prefix: URL(filePath: "/opt/homebrew")).reportsHealthAsJSON)
        #expect(!HomebrewInstallation(version: "4.6.9", prefix: URL(filePath: "/usr/local")).reportsHealthAsJSON)
        #expect(HomebrewInstallation(version: "8.1.0", prefix: URL(filePath: "/opt/homebrew")).reportsHealthAsJSON)
    }

    /// `brew vulns` arrived in 6.0.11, one release before the JSON diagnostics.
    @Test func keepsTheVulnerabilityScanForTheVersionThatAddedIt() {
        #expect(!HomebrewInstallation(version: "6.0.10", prefix: URL(filePath: "/opt/homebrew")).checksVulnerabilities)
        #expect(HomebrewInstallation(version: "6.0.11", prefix: URL(filePath: "/opt/homebrew")).checksVulnerabilities)
        #expect(!HomebrewInstallation(version: "5.9.99", prefix: URL(filePath: "/usr/local")).checksVulnerabilities)
        #expect(HomebrewInstallation(version: "6.1", prefix: URL(filePath: "/opt/homebrew")).checksVulnerabilities)
    }

    @Test func survivesAVersionItCannotRead() {
        let installation = HomebrewInstallation(version: "unknown", prefix: URL(filePath: "/opt/homebrew"))

        #expect(!installation.reportsHealthAsJSON)
        #expect(!installation.checksVulnerabilities)
    }

    @Test func readsWhatACleanUpWouldFree() {
        let output = """
        Would remove: /opt/homebrew/Cellar/x265/4.2 (12 files, 17MB)
        Would remove (broken link): /opt/homebrew/bin/sample
        ==> This operation would free approximately 61.2MB of disk space.
        """

        #expect(Homebrew.reclaimableBytes(in: output, countsInThousands: true) == 61_200_000)
    }

    /// Homebrew drops the decimal on a round number, and its largest unit is GB. From 5.0.0 it counts in thousands
    /// (`utils/formatter.rb` divides by 1000.0). Earlier versions count in 1024s, whatever the unit says.
    @Test func readsEveryUnitACleanUpUses() {
        #expect(Homebrew.reclaimableBytes(in: "would free approximately 512B of disk space.", countsInThousands: true) == 512)
        #expect(Homebrew.reclaimableBytes(in: "would free approximately 3KB of disk space.", countsInThousands: true) == 3_000)
        #expect(Homebrew.reclaimableBytes(in: "would free approximately 1.5GB of disk space.", countsInThousands: true) == 1_500_000_000)
        #expect(Homebrew.reclaimableBytes(in: "would free approximately 3KB of disk space.", countsInThousands: false) == 3_072)
        #expect(Homebrew.reclaimableBytes(in: "would free approximately 1.5GB of disk space.", countsInThousands: false) == Int64(1.5 * 1024 * 1024 * 1024))
        #expect(HomebrewInstallation(version: "5.0.0", prefix: URL(filePath: "/opt/homebrew")).countsInThousands)
        #expect(!HomebrewInstallation(version: "4.6.20", prefix: URL(filePath: "/opt/homebrew")).countsInThousands)
    }

    /// Homebrew prints the total only when it is not zero (`unless cleanup.disk_cleanup_size.zero?` in `cmd/cleanup.rb`)
    /// and lists each file it would remove (`Would remove: <path> (<size>)` in `cleanup.rb`), so a dry run that lists no
    /// file has nothing to free. A broken link or an empty folder takes no room.
    @Test func aCleanUpThatListsNothingFreesNothing() {
        #expect(Homebrew.reclaimableBytes(in: "", countsInThousands: true) == 0)
        #expect(Homebrew.reclaimableBytes(in: "Would remove (broken link): /opt/homebrew/bin/old\n", countsInThousands: true) == 0)
        #expect(Homebrew.reclaimableBytes(in: "Would remove: /Users/me/Library/Caches/Homebrew/foo--1.0.tar.gz (1.2MB)\n", countsInThousands: true) == nil)
    }

    @Test func leavesTheFigureOutWhenHomebrewDoesNotGiveOne() {
        #expect(Homebrew.reclaimableBytes(in: "would free approximately lots of disk space.", countsInThousands: true) == nil)
        // A figure too large for an `Int64` counts as no figure, instead of crashing the app.
        #expect(Homebrew.reclaimableBytes(in: "would free approximately 99999999999999999999GB of disk space.", countsInThousands: true) == nil)
    }

    @Test func readsWhatHomebrewFoundWrong() throws {
        let json = """
        {
          "tier": 1,
          "findings": [
            {
              "text": "Broken symlinks were found:\\n  /opt/homebrew/bin/sample\\n",
              "tier": 1,
              "affects": [],
              "links": [],
              "remediation": {"commands": ["brew cleanup"], "text": "Remove them with `brew cleanup`\\n"}
            },
            {"text": "An unrelated note.", "tier": 2, "affects": [], "links": []}
          ]
        }
        """
        let report = try JSONDecoder().decode(Homebrew.DoctorReport.self, from: Data(json.utf8))
        let findings = report.findings.map(\.finding)

        #expect(findings.count == 2)
        #expect(findings[0].text == "Broken symlinks were found:\n  /opt/homebrew/bin/sample")
        #expect(findings[0].remedy == "Remove them with `brew cleanup`")
        #expect(findings[0].commands == ["brew cleanup"])
        #expect(findings[1].remedy == nil)
        #expect(findings[1].commands.isEmpty)
    }

    @Test func readsWhatAVulnerabilityScanFound() throws {
        let json = """
        {
          "findings": [
            {
              "formula": "libssh2", "version": "1.11.1", "tag": "libssh2-1.11.1",
              "repo_url": "https://github.com/libssh2/libssh2",
              "vulnerabilities": [
                {"id": "CVE-2019-17498", "severity": "UNKNOWN", "summary": "Out-of-bounds read", "aliases": [], "fixed_versions": []},
                {"id": "CVE-2020-22218", "severity": "MEDIUM", "summary": "Memory corruption", "aliases": [], "fixed_versions": []}
              ],
              "patched": []
            },
            {
              "formula": "openssl@3", "version": "3.6.3", "tag": "openssl-3.6.3",
              "repo_url": "https://github.com/openssl/openssl",
              "vulnerabilities": [
                {"id": "CVE-2026-14456", "severity": "HIGH", "summary": "Unbounded memory growth", "aliases": [], "fixed_versions": ["f089acd"]},
                {"id": "CVE-2026-14999", "severity": "CRITICAL", "summary": "Remote code execution", "aliases": [], "fixed_versions": []},
                {"id": "CVE-2026-14001", "severity": "critical", "summary": "Certificate check bypass", "aliases": [], "fixed_versions": []},
                {"id": "CVE-2026-14100", "severity": "LOW", "summary": "Timing side channel", "aliases": [], "fixed_versions": []}
              ],
              "patched": []
            }
          ],
          "skipped_formulae": ["mpg123", "ca-certificates"]
        }
        """
        let report = try JSONDecoder().decode(Homebrew.VulnsReport.self, from: Data(json.utf8)).report

        #expect(report.advisories.map(\.formula) == ["openssl@3", "libssh2"])
        #expect(report.skipped == ["ca-certificates", "mpg123"])

        let openssl = try #require(report.advisories.first)
        #expect(openssl.version == "3.6.3")
        #expect(openssl.highestSeverity == .critical)
        #expect(openssl.vulnerabilities.map(\.id) == ["CVE-2026-14001", "CVE-2026-14999", "CVE-2026-14456", "CVE-2026-14100"])
        #expect(openssl.vulnerabilities.map(\.severity) == [.critical, .critical, .high, .low])
        #expect(openssl.vulnerabilities.first?.summary == "Certificate check bypass")

        let libssh2 = try #require(report.advisories.last)
        #expect(libssh2.highestSeverity == .medium)
        #expect(libssh2.vulnerabilities.map(\.severity) == [.medium, .unknown])
    }

    /// From 6.0.11 to 6.0.18 the scan answers with a list, and from 6.0.19 with an object that holds one. Both
    /// shapes are read, so an older Homebrew's answer is not thrown away as a failure.
    @Test func readsTheScanAnOlderHomebrewWrites() throws {
        let older = #"[{"formula":"libssh2","version":"1.11.0","vulnerabilities":[{"id":"CVE-2023-48795","severity":"MEDIUM","summary":"Terrapin"}],"patched":[]}]"#

        let report = try JSONDecoder().decode(Homebrew.VulnsReport.self, from: Data(older.utf8)).report

        #expect(report.advisories.map(\.formula) == ["libssh2"])
        #expect(report.skipped.isEmpty)
    }

    /// The scan keeps a formula whose every vulnerability is patched, with nothing open under it. Listing it
    /// would show an empty entry under "Known Vulnerabilities" instead of saying none were found.
    @Test func leavesOutAFormulaWithNothingOpen() throws {
        let json = #"{"findings":[{"formula":"curl","version":"8.0","vulnerabilities":[],"patched":[{"id":"CVE-1"}]}]}"#

        #expect(try JSONDecoder().decode(Homebrew.VulnsReport.self, from: Data(json.utf8)).report.advisories.isEmpty)
    }

    @Test func survivesAScanWithNothingInIt() throws {
        let report = try JSONDecoder()
            .decode(Homebrew.VulnsReport.self, from: Data(#"{"findings": []}"#.utf8))
            .report

        #expect(report.advisories.isEmpty)
        #expect(report.skipped.isEmpty)
    }

    /// From 6.0.0 Homebrew keeps its copy of the definitions in one file. Earlier versions keep one file for
    /// formulae and one for casks. Either layout counts as a local copy.
    @Test func findsHomebrewsCopyOfItsDefinitionsInEitherLayout() throws {
        let newer = try TemporaryDirectory()
        try newer.file("api/internal/packages.arm64_tahoe.jws.json")
        #expect(Homebrew.hasLocalDefinitions(inCache: newer.url))

        let older = try TemporaryDirectory()
        try older.file("api/formula.jws.json")
        #expect(!Homebrew.hasLocalDefinitions(inCache: older.url), "a cask query would still fetch the cask file")
        try older.file("api/cask.jws.json")
        #expect(Homebrew.hasLocalDefinitions(inCache: older.url))

        let empty = try TemporaryDirectory()
        try empty.directory("api/internal")
        #expect(!Homebrew.hasLocalDefinitions(inCache: empty.url))
    }
}
