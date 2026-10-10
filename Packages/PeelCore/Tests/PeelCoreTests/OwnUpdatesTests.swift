import Foundation
@testable import PeelCore
import Testing

struct OwnUpdatesTests {
    @Test func asksAboutItsOwnUpdatesOnItsOwnOnlyWhileUpdateChecksAreOn() {
        #expect(OwnUpdateCheck.mayAsk(askedByThePerson: true, checksForAppUpdates: true))
        #expect(OwnUpdateCheck.mayAsk(askedByThePerson: true, checksForAppUpdates: false))
        #expect(OwnUpdateCheck.mayAsk(askedByThePerson: false, checksForAppUpdates: true))
        #expect(!OwnUpdateCheck.mayAsk(askedByThePerson: false, checksForAppUpdates: false))
    }

    @Test func readsItsOwnSignedFeedAsTheReleaseWritesIt() throws {
        let feed = """
        <?xml version="1.0" standalone="yes"?><!-- sparkle-sign-warning:
        IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires re-signing this file with \
        generate_appcast or sign_update! The signed signature will be embedded at the end of this file.
        --><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
            <channel>
                <title>Peel</title>
                <item>
                    <title>1.0.2</title>
                    <pubDate>Fri, 16 Oct 2026 12:00:00 +0200</pubDate>
                    <sparkle:criticalUpdate></sparkle:criticalUpdate>
                    <sparkle:version>261016</sparkle:version>
                    <sparkle:shortVersionString>1.0.2</sparkle:shortVersionString>
                    <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
                    <enclosure url="https://github.com/TuguiDragos/Peel/releases/download/v1.0.2/Peel-1.0.2.dmg" \
        length="21902039" type="application/octet-stream" sparkle:edSignature="SJIZHrsKVqH33o+uqeJLzi1+o7BHT5gquqpypaSOx2vf"></enclosure>
                </item>
            </channel>
        </rss><!-- sparkle-signatures:
        edSignature: jBug6R4cqU+Ivsnuc5vseBntmIm08j46rXbczysF1BygZVmrCJBXQClNwtfnIbjXyUrNSZcYVeTmj0v+Pf9vAA==
        length: 1143
        -->
        """
        for isAppleSilicon in [true, false] {
            let releases = Appcast.releases(in: Data(feed.utf8), systemVersion: "26.0.0", isAppleSilicon: isAppleSilicon)
            let release = try #require(releases?.first)
            #expect(release.version == "261016")
            #expect(release.displayVersion == "1.0.2")
        }
    }

    @Test func installsOnlySignedUpdatesFromItsOwnFeedWhenThePersonChooses() throws {
        let repository = StringCatalogTests.repository
        let plist = try Data(contentsOf: repository.appending(path: "Support/Peel-Info.plist"))
        let info = try #require(try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])

        #expect(info["SUFeedURL"] as? String == "https://github.com/TuguiDragos/Peel/releases/latest/download/appcast.xml")
        #expect(info["SUPublicEDKey"] as? String == "$(SPARKLE_PUBLIC_ED_KEY)")
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUAllowsAutomaticUpdates"] as? Bool == false)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUEnableSystemProfiling"] == nil)
        #expect(!info.keys.contains { $0.hasPrefix("SUEnable") && $0.hasSuffix("Service") })

        let project = try String(contentsOf: repository.appending(path: "Peel.xcodeproj/project.pbxproj"), encoding: .utf8)
        let keys = project.matches(of: /SPARKLE_PUBLIC_ED_KEY = "?([A-Za-z0-9+\/=]+)"?;/).map { String($0.output.1) }
        #expect(keys.count == 2, "the app's Debug and Release configurations each name the key")
        #expect(Set(keys).count == 1)
        #expect(keys.first.flatMap { Data(base64Encoded: $0) }?.count == 32)
    }
}
