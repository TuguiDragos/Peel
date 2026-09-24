import PeelCore
import SwiftUI

/// Over a list holding items only the helper can move. It says which of the four things is in the way, since
/// "install it" is no use to somebody whose helper is installed and is not allowed to use it.
struct HelperRequiredBanner: View {
    @Environment(HelperModel.self) private var helper
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Notice(title: Text("Some items need administrator access"), detail: detail) {
            if helper.standing != .notThisAccount {
                Button(helper.standing == .waitingForApproval ? "Open System Settings" : "Open Peel Settings") {
                    if helper.standing == .waitingForApproval {
                        PrivilegedHelper.openLoginItemsSettings()
                    } else {
                        openSettings()
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    private var detail: Text {
        switch helper.standing {
        case .ready, .notInstalled:
            helper.isRegisteredByAnotherCopy
                ? Text("Peel’s helper was installed by another copy of Peel, and this copy can’t use it.")
                : Text("Install Peel’s helper to remove the items in the system folders it serves.")
        case .waitingForApproval: Text("Peel’s helper is waiting to be allowed in System Settings, under Login Items & Extensions.")
        case .notThisAccount: Text("Only an administrator can use Peel’s helper, so Peel can’t remove these from this account.")
        case .notAnswering: Text("Peel’s helper isn’t answering. Repair it in Settings.")
        }
    }
}
