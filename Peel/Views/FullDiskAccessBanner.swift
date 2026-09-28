import AppKit
import SwiftUI

struct FullDiskAccessBanner: View {
    @Environment(HomeModel.self) private var home

    var body: some View {
        Notice(
            title: Text("Some folders couldn’t be read"),
            detail: Text("Give Peel Full Disk Access so it can read the folders macOS protects.")
        ) {
            // Full Disk Access applies only to a new process, so once it may have been given, Peel offers to reopen.
            if home.needsRelaunchForFullDiskAccess {
                Button("Reopen Peel") { home.relaunch() }
            }
            Button("Open System Settings") {
                home.openFullDiskAccessSettings()
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }
}
