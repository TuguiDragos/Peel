@testable import PeelCore
import Testing

struct LowDiskSpaceTests {
    private static let gigabyte: Int64 = 1_000_000_000

    private static func disk(free: Int64, of total: Int64 = 500 * gigabyte) -> DeviceInfo.Storage {
        DeviceInfo.Storage(total: total, free: free)
    }

    private static func check(free gigabytes: Int64, told: Bool) -> LowDiskSpace.Answer {
        LowDiskSpace.check(disk(free: gigabytes * gigabyte), told: told, canTell: true)
    }

    @Test func tellsOnceWhenLessThanATenthIsFree() {
        #expect(Self.check(free: 60, told: false) == .init(tell: false, told: false))
        #expect(Self.check(free: 49, told: false) == .init(tell: true, told: true))
        #expect(Self.check(free: 20, told: true) == .init(tell: false, told: true))
    }

    @Test func tellsAgainOnlyAfterTheDiskHadRoom() {
        #expect(Self.check(free: 60, told: true) == .init(tell: false, told: true))
        #expect(Self.check(free: 49, told: true) == .init(tell: false, told: true))
        #expect(Self.check(free: 65, told: true) == .init(tell: false, told: false))
        #expect(Self.check(free: 49, told: false) == .init(tell: true, told: true))
    }

    @Test func aWarningMacOSCannotShowIsStillOwed() {
        let full = Self.disk(free: 49 * Self.gigabyte)
        #expect(LowDiskSpace.check(full, told: false, canTell: false) == .init(tell: false, told: false))
        #expect(LowDiskSpace.check(full, told: false, canTell: true) == .init(tell: true, told: true))
        #expect(LowDiskSpace.check(full, told: true, canTell: false) == .init(tell: false, told: true))
    }

    @Test func saysNothingOfADiskWhoseSizeIsUnknown() {
        let unknown = Self.disk(free: 0, of: 0)
        #expect(LowDiskSpace.check(unknown, told: false, canTell: true) == .init(tell: false, told: false))
    }
}
