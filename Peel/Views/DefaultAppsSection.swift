import PeelCore
import SwiftUI

/// What an app opens by default: a row of badges for its kinds of files and one for its kinds of links, each badge
/// naming the app that would open them once it is gone, or No app, and opening their list. Its heading opens and
/// closes it, as the sidebar's groups do, and it starts closed for every app.
struct DefaultAppsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let roles: [DefaultRole]
    /// The app the page shows.
    let app: URL
    /// The app the section is open for, so the page of another app finds it closed.
    @Binding var openFor: URL?

    private var isExpanded: Bool { openFor == app }

    private func toggle() {
        withAnimation(reduceMotion ? nil : Motion.step.animation) {
            openFor = isExpanded ? nil : app
        }
    }

    var body: some View {
        let files = DefaultApps.handOvers(roles, of: .fileKind)
        let links = DefaultApps.handOvers(roles, of: .link)
        if !files.isEmpty || !links.isEmpty {
            Section {
                if isExpanded, !files.isEmpty {
                    HandOverRow(
                        lead: links.isEmpty ? "Once it’s gone, they open with" : "Once it’s gone, its files open with",
                        handOvers: files, kind: .fileKind
                    )
                }
                if isExpanded, !links.isEmpty {
                    HandOverRow(lead: "Once it’s gone, its links open with", handOvers: links, kind: .link)
                }
            } header: {
                let title = Self.title(files: files.map(\.count).reduce(0, +), links: links.map(\.count).reduce(0, +))
                HStack(spacing: 5) {
                    Text(verbatim: title)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHeading(.h2)
                        .onTapGesture(perform: toggle)
                    InfoNote(
                        name: title, detail: Text(verbatim: Self.note(files: !files.isEmpty, links: !links.isEmpty))
                    )
                    Spacer(minLength: 0)
                    Button(action: toggle) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .minimumTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: title))
                    .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
                }
            }
        }
    }

    static func title(files: Int, links: Int) -> String {
        switch (files, links) {
        case (_, 0): String(inflecting: "Default App for ^[\(files) Kind](inflect: true) of ^[File](agreeWithArgument: 1)")
        case (0, _): String(inflecting: "Default App for ^[\(links) Kind](inflect: true) of ^[Link](agreeWithArgument: 1)")
        default:
            String(inflecting: "Default App for ^[\(files) Kind](inflect: true) of ^[File](agreeWithArgument: 1) and ^[\(links) Kind](inflect: true) of ^[Link](agreeWithArgument: 2)")
        }
    }

    static func note(files: Bool, links: Bool) -> String {
        [
            files ? String(localized: "These kinds of files open with this app when you double-click one.\n\nOnce the app is gone, macOS opens each kind with another app that can read it, and Peel shows which app that would be. A kind under No app has nothing else on this Mac to open it.\n\nYour files stay where they are. Peel never changes which app opens what: you choose that in Finder, with Get Info.") : nil,
            links ? String(localized: "These kinds of links open with this app when you click one, and once it’s gone with the app Peel shows. For a kind of link, choose it in System Settings or in the app itself.") : nil,
        ].compactMap(\.self).joined(separator: "\n\n")
    }
}

/// What the kinds of one sort would open with: a sentence, then a badge for each app that would take some over,
/// and No app last.
struct HandOverRow: View {
    let lead: LocalizedStringResource
    let handOvers: [DefaultHandOver]
    let kind: DefaultRole.Kind

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(lead)
                .layoutPriority(1)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(handOvers) { handOver in
                    HandOverBadge(handOver: handOver, kind: kind)
                }
            }
        }
        .listRowSeparator(.hidden)
    }
}

private struct HandOverBadge: View {
    let handOver: DefaultHandOver
    let kind: DefaultRole.Kind
    @State private var showsList = false

    var body: some View {
        Button {
            showsList = true
        } label: {
            HStack(spacing: 5) {
                if handOver.app == nil {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.accentColor)
                }
                if let app = handOver.app {
                    Text(verbatim: app)
                } else {
                    Text("No app")
                }
                Text(handOver.count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .contentShape(Capsule())
            .minimumTarget()
        }
        .buttonStyle(RowButtonStyle())
        .fixedSize()
        .accessibilityLabel(Text(verbatim: HandOverList.title(of: handOver, kind: kind)))
        .popover(isPresented: $showsList) {
            HandOverList(handOver: handOver, kind: kind)
        }
    }
}

/// The kinds one badge stands for, as tall as they are up to the height popovers keep and scrolling past it.
struct HandOverList: View {
    let handOver: DefaultHandOver
    let kind: DefaultRole.Kind

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                Text(verbatim: Self.title(of: handOver, kind: kind))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if handOver.app == nil {
                    Text(kind == .fileKind
                        ? "The files stay where they are. They won’t open with a double-click until you install an app that reads them."
                        : "Clicking such a link opens nothing until you install an app that opens it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(handOver.kinds, id: \.self) { name in
                    Text(verbatim: Self.breakable(name))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 340)
        .frame(maxHeight: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `name` with a place to break a line before each extension after the first.
    static func breakable(_ name: String) -> String {
        // Unicode allows no break before a period, even after a space; a zero width space allows one after it.
        name.replacingOccurrences(of: ", .", with: ", \u{200B}.")
    }

    static func title(of handOver: DefaultHandOver, kind: DefaultRole.Kind) -> String {
        let count = handOver.count
        return switch (handOver.app, kind) {
        case (let app?, .fileKind):
            String(inflecting: "\(app) would open ^[\(count) kind](inflect: true) of ^[file](agreeWithArgument: 2)")
        case (let app?, .link):
            String(inflecting: "\(app) would open ^[\(count) kind](inflect: true) of ^[link](agreeWithArgument: 2)")
        case (nil, .fileKind):
            String(inflecting: "No app on this Mac opens ^[\(count) kind](inflect: true) of ^[file](agreeWithArgument: 1)")
        case (nil, .link):
            String(inflecting: "No app on this Mac opens ^[\(count) kind](inflect: true) of ^[link](agreeWithArgument: 1)")
        }
    }
}
