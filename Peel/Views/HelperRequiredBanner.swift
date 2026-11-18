import PeelCore
import SwiftUI

/// Over a page that needs the helper for what it does. It says what that is, and which of the four things is in the
/// way, since "install it" is no use to somebody whose helper is installed, or who isn't an administrator.
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
        Text(helper.whyItCannotAct)
    }
}

extension PrivilegedHelper.Standing {
    /// Never while another copy's registration stands: every copy shares one helper label and one background item
    /// record, and a second registration from another bundle is what keeps the helper from starting.
    func offersInstall(registeredByAnotherCopy: Bool) -> Bool {
        self == .notInstalled && !registeredByAnotherCopy
    }

    /// Only an administrator changes the helper, so only an administrator is offered to uninstall it.
    func offersUninstall(isAdministrator: Bool) -> Bool {
        isAdministrator && [.ready, .waitingForApproval, .notAnswering].contains(self)
    }

    /// Why Peel's helper can't act, for a page or a control that needs it. An account that isn't an administrator's
    /// hears where the helper stands, by its `status`, the step an administrator takes, and what follows.
    func whyItCannotAct(registeredByAnotherCopy: Bool, status: PrivilegedHelper.Status) -> LocalizedStringResource {
        switch self {
        case .ready, .notInstalled:
            registeredByAnotherCopy
                ? "Peel’s helper was installed by another copy of Peel, and this copy can’t use it. Open the copy of Peel that installed it."
                : "Install Peel’s helper, which does this as an administrator in the system folders it serves."
        case .waitingForApproval: "The Peel helper is waiting to be allowed in System Settings > General > Login Items & Extensions."
        case .notThisAccount:
            switch status {
            case .notRegistered, .unavailable:
                "The Peel helper is not installed, and only an administrator can install it. Log in as an administrator, open Peel there, and install the helper. Then this account can use it, with an administrator name and password each time."
            case .requiresApproval:
                "The Peel helper is installed but not yet allowed, and only an administrator can allow it. Log in as an administrator, open Peel there, and allow the helper. Then this account can use it, with an administrator name and password each time."
            case .enabled:
                "The Peel helper is not answering, and only an administrator can repair it. Log in as an administrator, open Peel there, and repair the helper. Then this account can use it, with an administrator name and password each time."
            }
        case .notAnswering: "Peel’s helper isn’t answering. Repair it in Settings."
        }
    }
}
