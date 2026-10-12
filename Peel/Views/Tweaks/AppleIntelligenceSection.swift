import AppKit
import PeelCore
import SwiftUI

@available(macOS 27, *)
struct AppleIntelligenceSection: View {
    var body: some View {
        Section {
            ForEach(AppleIntelligenceSwitch.allCases, id: \.self) { feature in
                AppleIntelligenceRow(feature: feature)
            }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text("Peel doesn’t change these. Each button opens the place where Apple says to turn that feature off.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

@available(macOS 27, *)
private struct AppleIntelligenceRow: View {
    let feature: AppleIntelligenceSwitch

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.words.title)
                    .font(.body.weight(.semibold))
                Text(feature.words.place)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            button
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var button: some View {
        switch feature.place {
        case .settings(let address):
            Button("Open System Settings") {
                NSWorkspace.shared.open(address)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .app(let identifier):
            let app = Self.apps[identifier]
            Button("Open \(app?.name ?? identifier)") {
                guard let url = app?.url else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(app == nil)
        }
    }

    /// Each app the rows open, with its name as Finder shows it, read once.
    private static let apps: [String: (url: URL, name: String)] = {
        var apps: [String: (url: URL, name: String)] = [:]
        for case .app(let identifier) in AppleIntelligenceSwitch.allCases.map(\.place) where apps[identifier] == nil {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { continue }
            apps[identifier] = (url, AppInspector.displayName(of: url))
        }
        return apps
    }()
}

extension AppleIntelligenceSwitch {
    struct Words {
        let title: LocalizedStringResource
        /// Where the switch is, in macOS's own words.
        let place: LocalizedStringResource
    }

    var words: Words {
        switch self {
        case .siri: Words(
            title: "Siri AI (Beta)",
            place: "System Settings > Siri > Turn Off Siri. To keep Siri without Siri AI, turn Siri on again and select Use Siri Classic."
        )
        case .notificationSummaries: Words(
            title: "Notification summaries", place: "System Settings > Notifications > Summarize Notifications"
        )
        case .messagesSummaries: Words(title: "Messages summaries", place: "Messages > Settings > Summarize Messages")
        case .emailSummaries: Words(
            title: "Email summaries", place: "Mail > Settings > Viewing > Summarize Message Previews"
        )
        case .smartReplies: Words(
            title: "Personalized Smart Replies in Mail", place: "Mail > Settings > Composing > Personalize Smart Replies"
        )
        case .voicemailSuggestions: Words(
            title: "Voicemail suggestions in Phone", place: "Phone > Settings > Calls > Suggestions in Voicemail"
        )
        case .writingPrompts: Words(
            title: "Writing Prompts in Journal", place: "Journal > Settings > General > Get Writing Prompts"
        )
        case .screenTime: Words(
            title: "Siri in Screen Time",
            place: "System Settings > Screen Time > Content & Privacy > Siri, to turn off Siri AI or block capabilities such as Writing Assistance."
        )
        }
    }
}
