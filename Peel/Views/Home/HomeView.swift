import PeelCore
import SwiftUI

struct HomeView: View {
    @Environment(HomeModel.self) private var home
    @Environment(HelperModel.self) private var helper
    @State private var isRescanning = false
    /// The narrowest width that fits both halves side by side: the left half (360) and the narrowest width the
    /// permissions read well at (480, which `HomeSnapshot` also renders).
    private static let sideBySide: CGFloat = 360 + 480

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                // Each half is held to its own width limit rather than left to fill the window, so the pair
                // keeps a width of its own and sits in the middle of a wide window instead of against its
                // left edge. When the window is too narrow for both side by side, one goes above the other.
                let layout = proxy.size.width >= Self.sideBySide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                    : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    HomeContent()
                        .frame(width: 360)
                    HomePermissionsContent()
                        .frame(maxWidth: 720)
                }
                .frame(maxWidth: .infinity)
                // At least as tall as the window, so shorter content sits in the middle rather than at the
                // top. Taller content still scrolls, since a minimum height caps nothing.
                .frame(minHeight: proxy.size.height)
            }
        }
        .navigationTitle(Text(Tool.home.title))
        // The greeting serves as the page's title, so the smaller title in the toolbar is removed. The
        // navigation title stays set, so the window keeps its name in Mission Control and the Window menu.
        .toolbar(removing: .title)
        // Every tool has a button in the toolbar, and the window would change height between pages if its
        // toolbar came and went. Here the button checks the permissions and the free disk space again.
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning) {
                    await home.refresh(helper: helper)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                let change = Greeting.change(after: .now)
                try? await Task.sleep(until: .now + .seconds(max(1, change.timeIntervalSinceNow)), clock: .continuous)
                guard !Task.isCancelled else { return }
                home.updateGreeting()
            }
        }
    }
}

struct HomeContent: View {
    @Environment(HomeModel.self) private var home
    @Environment(LifetimeStats.self) private var stats
    @State private var isPointingAtDevice = false

    var body: some View {
        VStack(spacing: 0) {
            Text(home.greeting.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Album.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let device = home.device {
                deviceCard(device).padding(.top, 38)
                specs(device).padding(.top, 22)
                StorageStrip(storage: device.storage, isAlbum: true).padding(.top, 44)
                if stats.hasCleaned {
                    totals.padding(.top, 40)
                }
            } else {
                ProgressView().controlSize(.small).padding(.top, 40)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
    }

    private func deviceCard(_ device: DeviceInfo) -> some View {
        Button { home.openAboutThisMac() } label: {
            VStack(spacing: 10) {
                if let image = device.image {
                    DieCut(image: image)
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(4))
                        .accessibilityHidden(true)
                }
                Text(verbatim: device.model)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(isPointingAtDevice ? Album.orangeInk : Album.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .motion(.touch, value: isPointingAtDevice)
        .onHover { isPointingAtDevice = $0 }
        .help(Text("Show About This Mac"))
    }

    /// What Peel has moved to the Trash, from the same counters the menu bar panel reads. The biggest single
    /// removal is shown only in the menu bar panel, since a fourth sticker doesn't fit the column.
    private var totals: some View {
        HStack(spacing: 10) {
            DeviceSticker(
                value: stats.bytesFreed.text,
                amount: Double(stats.bytesFreed.known),
                label: "Moved to Trash",
                fill: Album.orange,
                ink: Album.onOrange,
                labelOpacity: 1,
                width: 86,
                radius: 16,
                angle: -3
            )
            DeviceSticker(
                value: stats.appsRemoved.shortCount,
                amount: Double(stats.appsRemoved),
                label: stats.appsRemoved == 1 ? "App removed" : "Apps removed",
                fill: Album.charcoal, ink: .white, width: 60, radius: 30, angle: 3
            )
            DeviceSticker(
                value: stats.itemsRemoved.shortCount,
                amount: Double(stats.itemsRemoved),
                label: stats.itemsRemoved == 1 ? "File removed" : "Files removed",
                fill: Album.cream, ink: Album.charcoal, width: 60, radius: 10, angle: -2
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func specs(_ device: DeviceInfo) -> some View {
        HStack(spacing: 12) {
            DeviceSticker(
                value: device.chipName,
                label: "Chip",
                fill: Album.charcoal,
                ink: .white,
                width: 62,
                radius: 12,
                angle: -4
            )
            DeviceSticker(
                value: device.memory.formatted(.byteCount(style: .memory)),
                label: "Memory",
                fill: Album.cream,
                ink: Album.charcoal,
                width: 66,
                radius: 33,
                angle: 3
            )
            DeviceSticker(
                value: device.systemVersion,
                label: "macOS",
                fill: Album.quietFill,
                ink: Album.ink,
                width: 76,
                radius: 31,
                angle: -1.5
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
