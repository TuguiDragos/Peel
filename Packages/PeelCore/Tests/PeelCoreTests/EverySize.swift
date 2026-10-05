import Foundation
@testable import PeelCore

extension DuplicateScanOptions {
    /// Options that compare copies of every size, since a test's files are smaller than Peel's default.
    static func everySize(in folders: [URL]) -> DuplicateScanOptions {
        var options = DuplicateScanOptions(folders: folders)
        options.minimumSize = 1
        return options
    }
}
