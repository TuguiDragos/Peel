import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// For a test that fills a disk image to its last block and counts on it staying full. Under the load of the whole
    /// suite such a disk can take a new file again right after, which the test checks and then proves nothing. On
    /// GitHub's runner the whole run is under that load, so the test is skipped there and runs on a Mac.
    static var fillsADiskToItsLastBlock: Self {
        .disabled(
            if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
            "a full disk does not stay full on GitHub's runner"
        )
    }
}
