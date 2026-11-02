import Foundation
@testable import PeelCore
import Testing

@Suite struct TrustedRootTests {
    @Test func namesTheRootAToolLeavesTrustedAfterHomebrewRemovesIt() {
        func root(_ name: String, _ kind: HomebrewPackage.Kind, fullName: String? = nil) -> TrustedRoot? {
            TrustedRoot.of(HomebrewPackage(name: name, kind: kind, fullName: fullName))
        }

        #expect(root("caddy", .formula)?.step == .command("caddy untrust"))
        #expect(root("mkcert", .formula)?.step == .command("mkcert -uninstall"))
        #expect(root("puma-dev", .formula, fullName: "puma/puma/puma-dev")?.step == .command("puma-dev -uninstall"))
        #expect(root("mitmproxy", .cask) == TrustedRoot(certificate: "mitmproxy", step: .keychainAccess))
        #expect(root("caddy", .formula, fullName: "example/tap/caddy") == nil)
        #expect(root("mitmproxy", .formula) == nil)
        #expect(root("charles", .cask) == nil, "Homebrew's uninstall deletes Charles's certificate")
        #expect(root("proxyman", .cask) == nil)
    }

    @Test func namesTheRootAnAppLeavesTrustedOncePeelHasMovedIt() {
        func root(_ identifier: String) -> TrustedRoot? {
            TrustedRoot.of(InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: identifier, name: "Example"))
        }

        #expect(root("com.xk72.Charles") == TrustedRoot(certificate: "Charles Proxy", step: .keychainAccess))
        #expect(root("com.proxyman.NSProxy")?.step == .menu("Certificate > Reset all Proxyman Certificates"))
        #expect(root("org.example.charles") == nil)
    }
}
