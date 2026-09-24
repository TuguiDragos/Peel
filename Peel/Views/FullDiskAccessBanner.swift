import AppKit
import SwiftUI

struct FullDiskAccessBanner: View {
    @Environment(HomeModel.self) private var home

    var body: some View {
        Notice(
            title: Text("Some folders couldn’t be read"),
            detail: Text("Give Peel Full Disk Access so it can read the folders macOS protects.")
        ) {
            Button("Open System Settings") {
                home.openFullDiskAccessSettings()
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }
}
