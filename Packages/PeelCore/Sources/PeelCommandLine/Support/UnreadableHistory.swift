import Foundation
import PeelCore

/// What `peel` says before a removal while History cannot be read: nothing moves, since what moved could not be
/// listed for Put Back, and the Peel app can start History over.
enum UnreadableHistory {
    static func note(at url: URL = RemovalHistory.defaultURL) -> String? {
        guard !RemovalLog.canBeRead(at: url) else { return nil }
        return "Peel couldn't read its History at \(url.path(percentEncoded: false)), so nothing will be moved. Open Peel and click Start Over in History."
    }
}
