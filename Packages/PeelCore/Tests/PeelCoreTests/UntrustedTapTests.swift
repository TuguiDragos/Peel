import Foundation
@testable import PeelCore
import Testing

struct UntrustedTapTests {
    private static func installed(read: Bool) -> Data {
        let definition = read
            ? #""name": ["Tidepool"], "desc": "A made-up app", "homepage": "https://example.org/", "url": "https://example.org/Tidepool-2.0.zip", "ruby_source_path": "Casks/tidepool.rb""#
            : #""name": [], "desc": null, "homepage": null, "url": "", "ruby_source_path": null"#
        return Data("""
            {"formulae": [], "casks": [{"token": "tidepool", "full_token": "example/test/tidepool",
            "tap": "example/test", \(definition), "version": "2.0", "installed": "2.0", "outdated": false,
            "artifacts": [{"app": ["Tidepool.app"], "target": "/Applications/Tidepool.app"}]}]}
            """.utf8)
    }

    @Test func aCaskHomebrewCouldNotReadNamesItsTapOnlyWhileHomebrewDoesNotTrustIt() throws {
        let refused = try #require(Homebrew.parseInstalled(Self.installed(read: false))?.first)
        let read = try #require(Homebrew.parseInstalled(Self.installed(read: true))?.first)

        #expect(refused.tapWithoutDefinition == "example/test")
        #expect(read.tapWithoutDefinition == nil)
        #expect(refused.noting(untrustedTaps: ["example/test"]).untrustedTap == "example/test")
        #expect(refused.noting(untrustedTaps: []).untrustedTap == nil)
        #expect(read.noting(untrustedTaps: ["example/test"]).untrustedTap == nil)
    }

    @Test func readsWhichInstalledTapsHomebrewDoesNotTrust() {
        let info = Data(#"""
            [{"name": "example/test", "installed": true, "trusted": false},
             {"name": "example/other", "installed": true, "trusted": true},
             {"name": "example/gone", "installed": false, "trusted": false}]
            """#.utf8)

        #expect(Homebrew.untrustedTaps(inTapInfo: info) == ["example/test"])
        #expect(Homebrew.untrustedTaps(inTapInfo: Data("not json".utf8)).isEmpty)
    }
}
