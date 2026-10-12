import AppKit
import Foundation
@testable import PeelCore
import Testing

struct AppleIntelligenceSwitchTests {
    private static let isMacOS27 = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
    )

    @Test(.enabled(if: isMacOS27)) func everyPlaceIsOneThisMacHas() throws {
        let folder = "/System/Library/ExtensionKit/Extensions"
        let panes = try FileManager.default.contentsOfDirectory(atPath: folder).compactMap { name in
            NSDictionary(contentsOfFile: "\(folder)/\(name)/Contents/Info.plist")?["CFBundleIdentifier"] as? String
        }
        for feature in AppleIntelligenceSwitch.allCases {
            switch feature.place {
            case .settings(let address):
                let scheme = "x-apple.systempreferences:"
                #expect(address.absoluteString.hasPrefix(scheme))
                let pane = String(address.absoluteString.dropFirst(scheme.count).prefix { $0 != "?" })
                #expect(panes.contains(pane), "\(feature) opens \(pane)")
            case .app(let identifier):
                let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
                #expect(app?.path(percentEncoded: false).hasPrefix("/System/Applications/") == true, "\(feature)")
            }
        }
    }
}
