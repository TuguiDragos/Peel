import PeelCore
import SwiftUI

/// Over a page that needs the helper for what it does. It says what that is, and which of the four things is in the
/// way, since "install it" is no use to somebody whose helper is installed and is not allowed to use it.
struct HelperRequiredBanner: View {
    @Environment(HelperModel.self) private var helper
    @Environment(\.openSettings) private var openSettings

    /// What the page needs the helper for.
    enum Need {
        /// Moving this many of its items to the Trash.
        case moving(Int)
        case forgettingThisReceipt
        /// Starting, stopping, enabling or disabling the job on the page, or moving its file.
        case changingThisJob
    }

    let need: Need

    var body: some View {
        Notice(title: title, detail: detail) {
            if helper.standing != .notThisAccount {
                Button(helper.standing == .waitingForApproval ? "Open System Settings" : "Open Peel Settings") {
                    if helper.standing == .waitingForApproval {
                        PrivilegedHelper.openLoginItemsSettings()
                    } else {
                        SettingsPane.helper.open(with: openSettings)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    private var title: Text {
        switch need {
        case .moving(let count): Text("Moving ^[\(count) item](inflect: true) needs administrator access")
        case .forgettingThisReceipt: Text("Forgetting this receipt needs administrator access")
        case .changingThisJob: Text("Changing this job needs administrator access")
        }
    }

    private var detail: Text {
        Text(helper.standing.whyItCannotAct(registeredByAnotherCopy: helper.isRegisteredByAnotherCopy))
    }
}

extension PrivilegedHelper.Standing {
    /// Never while another copy's registration stands: every copy shares one helper label and one background item
    /// record, and a second registration from another bundle is what keeps the helper from starting.
    func offersInstall(registeredByAnotherCopy: Bool) -> Bool {
        self == .notInstalled && !registeredByAnotherCopy
    }

    /// Why Peel's helper can't act, for a page or a control that needs it.
    func whyItCannotAct(registeredByAnotherCopy: Bool) -> LocalizedStringResource {
        switch self {
        case .ready, .notInstalled:
            registeredByAnotherCopy
                ? "Peel’s helper was installed by another copy of Peel, and this copy can’t use it. Open the copy of Peel that installed it."
                : "Install Peel’s helper, which does this as an administrator in the system folders it serves."
        case .waitingForApproval: "Peel’s helper is waiting to be allowed in System Settings, under Login Items & Extensions."
        case .notThisAccount: "Only an administrator can use Peel’s helper, so Peel can’t do this from this account."
        case .notAnswering: "Peel’s helper isn’t answering. Repair it in Settings."
        }
    }
}
