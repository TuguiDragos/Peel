import SwiftUI

struct PrivacySettingsView: View {
    @AppStorage(SettingsKey.checksForAppUpdates) private var checksForAppUpdates = true

    private struct Host: Identifiable {
        let address: String
        let purpose: LocalizedStringResource
        var id: String { address }
    }

    private let hosts = [
        Host(address: "itunes.apple.com", purpose: "The latest version of apps installed from the App Store."),
        Host(address: "github.com", purpose: "Peel’s own update feed, the release feed of apps that update through GitHub, and wherever GitHub sends the download. Homebrew also updates itself and its taps from here when you ask it to update, upgrade, or repair its taps, and a tap you added from another address from there."),
        Host(address: "api.github.com", purpose: "When you ask Homebrew to update or upgrade, it first asks here whether Homebrew itself, and each tap kept on GitHub, has changed."),
        Host(address: "formulae.brew.sh", purpose: "Homebrew’s own package list, downloaded when you ask Homebrew to update or upgrade."),
        Host(address: "ghcr.io", purpose: "Where Homebrew downloads the packages it upgrades, and wherever it redirects. A package with no ready-made build for your Mac downloads its source from the address its formula names, and a cask comes from its maker’s own address."),
        Host(address: "api.osv.dev", purpose: "The list of known vulnerabilities Homebrew checks formulae against."),
    ]

    var body: some View {
        Form {
            Section("What Peel Sends") {
                Text("Peel sends no usage data and keeps no account. Update checks ask each app’s own feed, or the App Store for an app bought there, about that app alone, and tell the App Store a country, since its answer depends on it: the country of the store an iPhone or iPad app came from, or else your Mac’s region. Taken together, the checks show the App Store which of its apps you have, and GitHub which of your apps update through it. Homebrew’s vulnerability scan, which you start yourself, is the one thing that sends a list of what is installed all at once: the source and version of each installed formula, to api.osv.dev. Report an Issue puts Peel’s version, your macOS version, and whether your Mac has Apple silicon or Intel in the address it opens.")
                    .font(.callout)
            }

            Section {
                // Each purpose goes under its host's name, not beside it, so every row keeps the same layout
                // however long the purpose is, in any language.
                ForEach(hosts) { host in
                    hostRow(Text(verbatim: host.address), host.purpose)
                }
                // Not an address, so unlike the host names above, this name is translated.
                hostRow(Text("Each app’s own update feed"), "The address written inside the app, and wherever it redirects. For an update that waits, also the page of release notes the feed names, once per version, and again hours later when its server didn’t answer. When the feed names a page for each language, Peel asks for the one in yours, so that server can tell which language you read.")
                LabeledContent {
                    Toggle(isOn: $checksForAppUpdates) { EmptyView() }
                        .labelsHidden()
                        .accessibilityLabel(Text("Check for app updates"))
                } label: {
                    titled("Check for app updates", "With this off, Peel contacts nothing on its own. Homebrew goes online only when you ask it to: Update, Upgrade (there or on an app’s own page), Repair Taps, and the vulnerability scan. Your own Homebrew settings, in a brew.env file, can change that, and the Homebrew page then says what they change.")
                }
            } header: {
                Text("Hosts Peel Can Contact")
            }
        }
        .formStyle(.grouped)
    }

    private func hostRow(_ name: Text, _ purpose: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            name
            Text(purpose)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
