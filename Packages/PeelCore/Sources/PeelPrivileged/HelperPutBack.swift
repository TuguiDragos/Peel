import Darwin
public import Foundation

public enum HelperPutBack {
    /// Nil once the item at `trashPath` is back at `destination`, otherwise why it isn't.
    public static func run(
        _ trashPath: String,
        to destination: String,
        for user: uid_t,
        policy: PrivilegedPathPolicy,
        ledger: () -> HelperLedger? = { HelperLedger() }
    ) -> String? {
        run(
            trashPath, to: destination, for: user, policy: policy, ledger: ledger,
            exclusively: TrashMover.renameExclusively
        )
    }

    static func run(
        _ trashPath: String,
        to destination: String,
        for user: uid_t,
        policy: PrivilegedPathPolicy,
        ledger: () -> HelperLedger?,
        exclusively: TrashMover.ExclusiveRename
    ) -> String? {
        guard
            let trash = policy.openTrash(ownedBy: user),
            let trashed = policy.openInTrash(trashPath, trash: trash)
        else { return HelperRefusal.notInTrash.rawValue }

        switch policy.openDestination(destination, for: trashed) {
        case .failure(let rejection):
            return rejection.explanation
        case .success(let target):
            // The request comes from History's record, which any process the user runs can rewrite. So the item
            // goes back only if the ledger shows the helper moved it, and only to the path recorded there.
            guard
                let ledger = ledger(),
                case .success(let origin) = Result(catching: { try ledger.origin(of: trashed, movedBy: user) })
            else {
                return HelperRefusal.cannotReadRecord.rawValue
            }
            guard origin == target.path else { return HelperRefusal.notInRecord.rawValue }
            let moved = ledger.whileStaging { staging in
                TrashMover.move(
                    trashed, to: [target.name], in: target.parent, through: staging, for: user,
                    refusing: { policy.refusal(ofPuttingBack: target.path, owner: $0.st_uid, mode: $0.st_mode) },
                    exclusively: exclusively
                )
            }
            switch moved {
            case nil:
                return HelperRefusal.cannotReadRecord.rawValue
            case .success?:
                ledger.forget([trashed])
                return nil
            case .failure(let failure)?:
                return failure.explanation
            }
        }
    }
}
