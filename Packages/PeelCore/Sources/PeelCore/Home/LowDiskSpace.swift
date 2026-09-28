public import Foundation

/// When Peel tells the person that the disk their home folder is on is nearly full: once less than a tenth of it is
/// free, and again only after an eighth of it was free, so a disk hovering at the line is not told about at every
/// check.
public enum LowDiskSpace {
    public struct Answer: Sendable, Hashable {
        public let tell: Bool
        /// Whether Peel has told since the disk last had room, which the next check is given.
        public let told: Bool
    }

    static let nearlyFull = 0.10
    static let roomAgain = 0.125

    public static func check(_ storage: DeviceInfo.Storage, told: Bool) -> Answer {
        guard storage.total > 0 else { return Answer(tell: false, told: told) }
        let free = Double(storage.free) / Double(storage.total)
        if free < nearlyFull { return Answer(tell: !told, told: true) }
        return Answer(tell: false, told: told && free < roomAgain)
    }

    @concurrent
    public static func storage(of home: URL = .homeDirectory) async -> DeviceInfo.Storage {
        DeviceInfo.storage(of: home)
    }
}
