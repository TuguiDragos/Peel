import PeelCore
import SwiftUI
import UserNotifications

struct HomePermissionsContent: View {
    @Environment(HomeModel.self) private var home
    @Environment(HelperModel.self) private var helper
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(\.openSettings) private var openSettings
    @State private var pointingAt: HomeModel.Permission?
    @State private var helperFailure: HelperModel.Failure?

    static let markSize: CGFloat = 36
    /// A whole number of points, so the mark's body (30) and edge (3 on each side) fall on whole pixels at
    /// any scale. With a half-point edge, one side of the circle looks thicker on a screen that is not Retina.
    static let markEdge: CGFloat = 3
    static let markBody: CGFloat = markSize - markEdge * 2
    static let tapeAngle: Double = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            // The tape is rotated, so it reaches above the card it sits on. The gap leaves room for it under
            // the banner, so the tape and the banner don't look stuck together.
            card(HomeModel.Permission.allCases.filter(\.isRequired), named: "Required", tapedAt: .topTrailing)
                .padding(.top, 42)
            card(
                HomeModel.Permission.allCases.filter { !$0.isRequired },
                named: "Optional",
                tapedAt: .bottomLeading,
                fill: Album.cream,
                ink: Album.charcoal
            )
            .padding(.top, 18)
        }
        // Each tape sticks out past its card's corner by a quarter of its width, so the sides keep more room
        // than the cards need. Without that room, the tapes would look like they fall off the window.
        .padding(.horizontal, 44)
        .padding(.top, 10)
        .padding(.bottom, 34)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(value: home.states)
        .motion(value: helper.changing)
        .helperFailureAlert($helperFailure)
    }

    /// A card for one section, laid out as a grid so the states line up in one column and the actions in
    /// another, whatever each row says. A strip of tape across `corner` names the section, so no heading
    /// floats above the card.
    private func card(
        _ permissions: [HomeModel.Permission],
        named title: LocalizedStringResource,
        tapedAt corner: Alignment,
        fill: Color = Album.orange,
        ink: Color = Album.onOrange
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            ForEach(Array(permissions.enumerated()), id: \.element.id) { index, permission in
                if index > 0 {
                    Perforation().padding(.leading, Self.markSize + 12)
                }
                row(permission)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .sticker(radius: 14)
        .overlay(alignment: corner) {
            TapeHeader(title: Text(title), fill: fill, ink: ink, angle: Self.tapeAngle)
                .alignmentGuide(.top) { $0[.top] + $0.height / 2 }
                .alignmentGuide(.bottom) { $0[.bottom] - $0.height / 2 }
                .alignmentGuide(.leading) { $0[.leading] + $0.width / 4 }
                .alignmentGuide(.trailing) { $0[.trailing] - $0.width / 4 }
        }
    }

    private func row(_ permission: HomeModel.Permission) -> some View {
        let state = home.state(of: permission)
        let changing = permission == .helper ? helper.changing : nil
        return GridRow {
            // The state sits under the name, as in System Settings, and a long name wraps instead of
            // shrinking. A column of its own for the state would leave a translated name almost no room.
            HStack(spacing: 12) {
                // The mark opens the same place as the name beside it, and lights up with it. VoiceOver and the
                // keyboard reach that place through the name, so the mark is one more way in for the pointer only.
                Button { show(permission) } label: {
                    mark(permission, state: state)
                        .scaleEffect(pointingAt == permission ? 1.07 : 1)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityHidden(true)
                .pointerStyle(.link)
                .motion(.touch, .movement, value: pointingAt == permission)
                .onHover { pointingAt = $0 ? permission : nil }
                .help(help(for: permission))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        name(permission, state: state)
                        InfoNote(
                            name: String(localized: permission.title),
                            detail: Text(permission.detail),
                            symbol: permission.symbol,
                            isAlbum: true
                        )
                    }
                    Text(changing?.progress ?? home.status(of: permission))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(state.isMissing && changing == nil ? Album.red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action(permission, state: state)
                .gridColumnAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }

    private func name(_ permission: HomeModel.Permission, state: HomeModel.State) -> some View {
        let isPointedAt = pointingAt == permission
        return Button { show(permission) } label: {
            // The name swells a little under the pointer, and the mark beside it with it.
            Text(permission.title)
                .font(.system(.body, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(state.isMissing ? Album.red : isPointedAt ? Album.orangeInk : Album.ink)
                .scaleEffect(isPointedAt ? 1.04 : 1, anchor: .leading)
                .minimumTarget()
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .motion(.touch, .movement, value: isPointedAt)
        .onHover { pointingAt = $0 ? permission : nil }
        .help(help(for: permission))
    }

    private func help(for permission: HomeModel.Permission) -> Text {
        permission.isInSystemSettings
            ? Text("Show \(String(localized: permission.title)) in System Settings")
            : Text("Open Peel Settings")
    }

    /// Opens where the setting is kept: its place in System Settings, or, for the command, which Peel puts on the
    /// path itself, the General tab of Peel's own Settings.
    private func show(_ permission: HomeModel.Permission) {
        if permission.isInSystemSettings {
            reveal(permission)
        } else {
            SettingsPane.general.open(with: openSettings)
        }
    }

    /// Opens the place in System Settings where macOS keeps the setting. The row's button may do something
    /// else, such as install the helper.
    private func reveal(_ permission: HomeModel.Permission) {
        switch permission {
        case .fullDiskAccess: home.openFullDiskAccessSettings()
        case .helper, .openAtLogin: home.openLoginItemsSettings()
        case .appManagement: home.openAppManagementSettings()
        case .notifications: home.openNotificationSettings()
        case .finderExtension: home.openFinderExtensionSettings()
        case .commandLine: break
        }
    }

    @ViewBuilder
    private func action(_ permission: HomeModel.Permission, state: HomeModel.State) -> some View {
        if let action = home.action(for: permission) {
            // The command-line row uses `CopyButton`, which says "Copied" once the command is on the pasteboard.
            if permission == .commandLine, let command = SettingsKey.commandLineInstallCommand() {
                CopyButton(text: command, title: action)
                    .buttonStyle(.stickerQuiet)
                    .accessibilityLabel(Text("\(String(localized: action)): \(String(localized: permission.title))", comment: "What VoiceOver reads for a button. The first %@ is the action, such as Install. The second is what it acts on, such as Helper."))
            } else {
                Button { perform(permission, state: state) } label: {
                    Text(action)
                        .keepsWordsWhole(String(localized: action))
                }
                .buttonStyle(state.isMissing ? .sticker(fill: Album.redFill, size: 11.5) : .stickerQuiet)
                .disabled(permission == .helper && helper.isChanging)
                .accessibilityLabel(Text("\(String(localized: action)): \(String(localized: permission.title))", comment: "What VoiceOver reads for a button. The first %@ is the action, such as Install. The second is what it acts on, such as Helper."))
            }
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    private func mark(_ permission: HomeModel.Permission, state: HomeModel.State) -> some View {
        ZStack(alignment: .topTrailing) {
            if state == .on {
                let colors = colors(for: permission)
                Image(systemName: permission.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.ink)
                    .frame(width: Self.markBody, height: Self.markBody)
                    .sticker(radius: Self.markBody / 2, fill: colors.fill, edge: Self.markEdge)
                    .rotationEffect(.degrees(permission.tilt))
            } else {
                // Any state but on is a flat, filled circle, not a dashed ring, which would look unfinished.
                // On is a raised sticker with an edge and a shadow, so the two stay easy to tell apart.
                Circle()
                    .fill(state.isMissing ? Album.red.opacity(0.16) : Album.slot)
                    .overlay(
                        Image(systemName: permission.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(state.isMissing ? Album.red : Color.secondary)
                    )
            }
            if state.isMissing {
                AttentionBadge(fill: Album.redFill).offset(x: 3, y: -3)
            }
        }
        .frame(width: Self.markSize, height: Self.markSize)
    }

    /// Unreadable exclusions come first: until they are read, nothing moves at all.
    @ViewBuilder
    private var banner: some View {
        if exclusions.exclusions.isUnreadable {
            Notice(
                title: Text("Peel couldn’t read your exclusions"),
                detail: Text("Peel removes nothing and puts nothing back until you start the list over in Settings."),
                isAlbum: true
            ) {
                Button("Open Peel Settings") { SettingsPane.exclusions.open(with: openSettings) }
                    .buttonStyle(.sticker(fill: Album.redFill, size: 11.5))
            }
        } else if home.needsAttention {
            let notice = MissingPermissionsNotice(
                helper: helper.standing,
                othersMissing: home.missingRequired.contains { $0 != .helper }
            )
            let toSetUp = home.missingRequired.filter { notice == .setUp || $0 != .helper }
            let missing = toSetUp.map { String(localized: $0.title) }.formatted(.list(type: .and))
            let detail = switch notice {
            case .setUp: Text("Set up \(missing) below.")
            case .repairTheHelper: Text("Repair it below. Until then, Peel can’t move anything that needs an administrator.")
            case .setUpAndRepairTheHelper: Text("Set up \(missing) below, and repair the helper.")
            }
            Notice(
                title: notice == .repairTheHelper
                    ? Text("Peel’s helper isn’t answering")
                    : Text("Peel can’t see or remove everything yet"),
                detail: detail,
                isAlbum: true
            ) {
                if home.needsRelaunchForFullDiskAccess {
                    Button("Reopen Peel") { home.relaunch() }
                        .buttonStyle(.sticker(fill: Album.redFill, size: 11.5))
                }
            }
        } else if !home.waitingRequired.isEmpty, home.hasChecked {
            // A required permission that is still pending is not set up. For example, a helper waiting for
            // approval cannot move anything that needs an administrator, so Home must not say "You're all set".
            let waiting = home.waitingRequired.map { String(localized: $0.title) }.formatted(.list(type: .and))
            Notice(
                title: Text("Almost there"),
                detail: Text("Check \(waiting) in System Settings."),
                kind: .note,
                isAlbum: true
            ) {}
        } else {
            HStack(spacing: 12) {
                Image(.peelGlyph)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Album.orange)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(home.hasChecked && !home.isStillChecking ? "You’re all set" : "Checking what Peel can reach")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Album.ink)
                    Text(
                        home.hasChecked && !home.isStillChecking
                            ? "Peel can see everything it needs to."
                            : "Asking macOS what is allowed."
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .sticker()
        }
    }

    private func colors(for permission: HomeModel.Permission) -> (fill: Color, ink: Color) {
        switch permission {
        case .fullDiskAccess: (Album.charcoal, .white)
        case .helper: (Album.orange, Album.onOrange)
        case .appManagement: (Album.cream, Album.orangeOnCream)
        default: (Album.cream, Album.charcoal)
        }
    }

    private func perform(_ permission: HomeModel.Permission, state: HomeModel.State) {
        switch permission {
        case .helper:
            // Registering a helper that is already registered returns an error (`SMAppService.h`), so one
            // that is registered but does not answer is repaired instead.
            if state == .pending {
                home.openLoginItemsSettings()
            } else if helper.standing == .notAnswering {
                Task { helperFailure = await helper.repair() }
            } else {
                Task { helperFailure = await helper.install() }
            }
        case .notifications: Task { await home.requestNotifications() }
        case .fullDiskAccess, .appManagement, .finderExtension, .openAtLogin: reveal(permission)
        // Its `CopyButton` copies the command by itself, so `perform` is never called for it.
        case .commandLine: break
        }
    }
}

fileprivate extension HomeModel {
    func status(of permission: Permission) -> LocalizedStringResource {
        guard hasChecked else { return "Checking…" }
        return switch (permission, state(of: permission)) {
        case (_, .checking): "Checking…"
        case (.helper, .missing):
            if helper.standing == .notAnswering {
                "Not answering"
            } else if helper.isRegisteredByAnotherCopy {
                // The helper belongs to the bundle that registered it, and that is not this one.
                "Installed by another copy of Peel"
            } else {
                "Not installed"
            }
        case (.helper, .pending): "Needs approval, or was turned off"
        case (.finderExtension, .off) where isFinderExtensionFromAnotherCopy: "On in another copy of Peel"
        case (_, .notThisAccount): "Needs an administrator"
        case (.appManagement, .pending): "Checked at first removal"
        case (.commandLine, .on): "Installed"
        case (.commandLine, _):
            HomeModel.commandLineStanding == .somethingElse ? "Something else is there" : "Not installed"
        case (_, .on): "On"
        case (_, .pending): LocalizedStringResource("Unknown (permission state)", defaultValue: "Unknown")
        case (_, .off), (_, .missing): "Off"
        }
    }

    func action(for permission: Permission) -> LocalizedStringResource? {
        guard hasChecked else { return nil }
        let state = state(of: permission)
        switch permission {
        case .fullDiskAccess: return state == .on ? nil : "Open System Settings"
        case .helper:
            switch state {
            case .on, .notThisAccount, .checking: return nil
            case .pending: return "Open System Settings"
            case .missing, .off: return helper.standing == .notAnswering ? "Repair" : "Install"
            }
        case .appManagement: return state == .on ? nil : "Open System Settings"
        // The optional rows open System Settings from their name, so they need no button. Notifications has
        // one until Peel has asked, because macOS lists Peel under Notifications only after that.
        case .notifications: return notificationStatus == .notDetermined ? "Turn On" : nil
        case .finderExtension, .openAtLogin: return nil
        // Short on purpose: every row shares the grid's button column, so a wide label here would narrow
        // every row's name. The row's name says what is copied, and the note beside it explains.
        case .commandLine: return state == .on || SettingsKey.commandLineInstallCommand() == nil ? nil : "Copy"
        }
    }
}

extension HomeModel.Permission {
    /// Whether the setting lives in System Settings. The command-line tool is a symlink in `/usr/local/bin`,
    /// so its row is the one with no pane to open.
    var isInSystemSettings: Bool { self != .commandLine }

    var tilt: Double {
        switch self {
        case .fullDiskAccess: -6
        case .helper: 5
        case .appManagement: -3
        case .notifications: 4
        case .finderExtension: -5
        case .openAtLogin: 3
        case .commandLine: -2
        }
    }
}
